import Darwin
import Foundation
import Synchronization

/// Reviews linked agent worktrees. Scan never contacts a remote or changes Git.
/// Cleanup retains the branch and locks its administrative entry for recovery.
public actor AgentWorkEngine {
    private let home: URL
    private let activityDirectory: URL
    private let runner: @Sendable (URL, [String], URL?, TimeInterval) async throws -> AgentCommandResult
    private let processReader: @Sendable () async throws -> AgentProcessSnapshot
    private let trash: @Sendable (URL) throws -> URL
    private let fixtureTrash: URL?
    private let clock: @Sendable () -> Date
    private let fixtureRemote: Bool
    private var candidates: [String: AgentCandidate] = [:]
    private var operationID: UUID?
    private var isMutating = false

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, activityDirectory: URL? = nil) {
        self.home = homeDirectory.roomLexicallyNormalized
        self.activityDirectory = activityDirectory ?? homeDirectory.appendingPathComponent("Library/Application Support/Room/AgentWork", isDirectory: true)
        self.runner = AgentCommand.run
        self.processReader = AgentProcesses.read
        self.trash = { url in var result: NSURL?; try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            guard let result else { throw AgentWorkError.message("Trash did not return a recovery location.") }; return result as URL }
        self.fixtureTrash = nil; self.clock = Date.init; self.fixtureRemote = false
    }
    init(home: URL, activity: URL, fixtureTrash: URL?,
         clock: @escaping @Sendable () -> Date = Date.init,
         runner: @escaping @Sendable (URL, [String], URL?, TimeInterval) async throws -> AgentCommandResult = AgentCommand.run,
         processes: @escaping @Sendable () async throws -> AgentProcessSnapshot = { AgentProcessSnapshot(paths: [], complete: true) }) {
        self.home = home; self.activityDirectory = activity; self.fixtureTrash = fixtureTrash
        self.clock = clock; self.runner = runner; self.processReader = processes; self.fixtureRemote = true
        self.trash = { source in
            if let fixtureTrash {
                let destination = fixtureTrash.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.moveItem(at: source, to: destination); return destination
            }
            var destination: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
            guard let destination else { throw AgentWorkError.message("Trash did not return a recovery location.") }
            return destination as URL
        }
    }

    public nonisolated static func shutdownOwnedCommands() { AgentOwnedCommands.shared.shutdown() }

    public func scan(approvedProjectRoots: [URL] = [], progress: (@Sendable (AgentWorkProgress) -> Void)? = nil) async -> AgentWorkReport {
        let operation = UUID()
        guard !isMutating else { return AgentWorkReport(id: operation, scannedAt: clock(), items: [], processAssociations: [],
            issues: [ScanIssue(url: home, message: "Finish the current cleanup or recovery before scanning again.")], cancelled: false, isPartial: true) }
        operationID = operation; candidates.removeAll()
        var pending: [String: AgentCandidate] = [:]
        var discovered: [(URL, AgentWorkOwner)] = [], issues: [ScanIssue] = [], associations: [AgentWorkProcessAssociation] = []
        for (path, owner) in [(".codex/worktrees", AgentWorkOwner.codex), (".claude/worktrees", .claude)] {
            do { discovered += try AgentFilesystem.discover(home.appendingPathComponent(path, isDirectory: true), owner: owner) }
            catch { issues.append(ScanIssue(url: home.appendingPathComponent(path), message: error.localizedDescription)) }
        }
        for root in approvedProjectRoots.prefix(32) {
            do {
                _ = try AgentFilesystem.identity(root, directory: true)
                let output = try await git(["worktree", "list", "--porcelain", "-z"], at: root)
                discovered += try AgentGit.parseWorktrees(output).map { record in
                    let path = record.url.path
                    let owner: AgentWorkOwner
                    if path.hasPrefix(home.appendingPathComponent(".codex/worktrees").path + "/") { owner = .codex }
                    else if path.hasPrefix(home.appendingPathComponent(".claude/worktrees").path + "/")
                        || path.hasPrefix(root.appendingPathComponent(".claude/worktrees").path + "/") { owner = .claude }
                    else { owner = .project }
                    return (record.url, owner)
                }
            } catch { issues.append(ScanIssue(url: root, message: "The approved repository's worktrees could not be inspected safely.")) }
        }
        let activity: AgentProcessSnapshot
        do { activity = try await processReader() }
        catch { activity = AgentProcessSnapshot(paths: [], complete: false) }
        var seen: Set<String> = [], items: [AgentWorkItem] = []
        for (url, owner) in discovered.prefix(256) where seen.insert(url.roomLexicallyNormalized.path).inserted {
            if Task.isCancelled || operationID != operation { break }
            progress?(AgentWorkProgress(inspectedCount: items.count, currentPath: url.path))
            do {
                let candidate = try await inspect(url, owner: owner, activity: activity)
                pending[candidate.item.id] = candidate
                items.append(candidate.item)
                for pid in candidate.item.processIDs {
                    let name = activity.paths.first { $0.pid == pid }?.name ?? "Process"
                    associations.append(AgentWorkProcessAssociation(processID: pid, processName: name,
                        worktreeID: candidate.item.id, detail: "Observed working directory or open file inside this worktree or its Git administrative directory."))
                }
            } catch is CancellationError { break }
            catch {
                issues.append(ScanIssue(url: url, message: "This worktree could not be verified safely: " + error.localizedDescription))
                items.append(AgentWorkItem(id: url.path, url: url, title: url.lastPathComponent, owner: owner,
                    repositoryURL: nil, gitAdminURL: nil, gitCommonURL: nil, branch: nil, head: nil, lastActivityAt: nil, allocatedBytes: 0, isPartial: true,
                    changedCount: 0, untrackedCount: 0, ignoredCount: 0, processIDs: [], isLinkedWorktree: false,
                    isLocked: false, isPrunable: false, heldReasons: ["Git or filesystem inspection is incomplete. Keep this worktree."], pushVerification: .notChecked))
            }
        }
        let cancelled = Task.isCancelled || operationID != operation
        if operationID == operation { candidates = cancelled ? [:] : pending }
        return AgentWorkReport(id: operation, scannedAt: clock(), items: items.sorted { $0.allocatedBytes > $1.allocatedBytes },
            processAssociations: associations, issues: issues, cancelled: cancelled,
            isPartial: cancelled || !issues.isEmpty || items.contains(where: \.isPartial) || discovered.count > 256)
    }

    /// Explicit user action: no cached tracking reference is used as remote proof.
    public func verifyRemote(worktreeID: String) async -> AgentWorkPushVerification {
        await verify(worktreeID: worktreeID, duringMutation: false)
    }
    private func verify(worktreeID: String, duringMutation: Bool) async -> AgentWorkPushVerification {
        guard !isMutating || duringMutation else { return .notChecked }
        let generation = operationID
        guard var candidate = candidates[worktreeID], let head = candidate.item.head else { return .notChecked }
        var proof: AgentWorkPushVerification
        do {
            try requireCurrent(candidate)
            let names = try await git(["remote"], at: candidate.item.url).text.split(separator: "\n").map(String.init)
            var verified: String?, matchedRef: String?, localURL: URL?, localIdentity: FileIdentity?
            for name in names.prefix(8) {
                guard AgentGit.safeRemoteName(name) else { continue }
                let remote = try await git(["config", "--get", "remote.\(name).url"], at: candidate.item.url).text.trimmingCharacters(in: .whitespacesAndNewlines)
                let local = remote.hasPrefix("/")
                guard AgentGit.allowedRemote(remote) || local else { continue }
                if local { try await validateLocalRemote(URL(fileURLWithPath: remote, isDirectory: true), candidate: candidate) }
                let command = AgentGit.options + (local ? ["-c", "protocol.file.allow=always"] : [])
                    + ["ls-remote", "--refs", "--heads", "--tags", "--", remote]
                let output = try await runner(URL(fileURLWithPath: "/usr/bin/git"), command,
                    URL(fileURLWithPath: "/var/empty", isDirectory: true), 20)
                guard output.status == 0 else { throw AgentWorkError.message("Remote verification failed.") }
                if let ref = AgentGit.exactRemoteRef(head: head, data: output.data) {
                    verified = (local ? "Local remote · " : "") + name; matchedRef = ref
                    if local { localURL = URL(fileURLWithPath: remote, isDirectory: true); localIdentity = try AgentFilesystem.identity(localURL!, directory: true) }
                    break
                }
            }
            try requireCurrent(candidate)
            let currentHead = try await git(["rev-parse", "--verify", "HEAD"], at: candidate.item.url).text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentHead == head else { throw AgentWorkError.message("HEAD changed during verification. Scan again.") }
            proof = AgentWorkPushVerification(state: verified == nil ? .mismatch : .verified, checkedAt: clock(), head: head,
                remoteName: verified, detail: verified == nil
                    ? "No supported live remote ref exactly matched this HEAD. Ahead remote refs are not assumed to contain it."
                    : "A live remote branch or tag exactly matched this HEAD. Cleanup will verify it again.")
            proof.remoteRef = matchedRef; proof.localRemoteURL = localURL; proof.localRemoteIdentity = localIdentity
        } catch {
            proof = AgentWorkPushVerification(state: .unavailable, checkedAt: clock(), head: head, remoteName: nil,
                detail: "Live remote verification failed or was cancelled. Keep this worktree; local tracking refs are not sufficient.")
        }
        guard operationID == generation, !Task.isCancelled,
              candidates[worktreeID]?.snapshot.fingerprint == candidate.snapshot.fingerprint else {
            return AgentWorkPushVerification(state: .unavailable, checkedAt: clock(), head: head, remoteName: nil,
                detail: "The scan changed or verification was cancelled. Scan and verify again.")
        }
        candidate.item.pushVerification = proof
        candidates[worktreeID] = candidate
        return proof
    }

    public func authorizationLocations(worktreeID: String) throws -> [URL] {
        guard let candidate = candidates[worktreeID], candidate.item.canReviewForCleanup else {
            throw AgentWorkError.message("Verify the remote and resolve every hold before requesting write access.")
        }
        try requireCurrent(candidate)
        return [candidate.item.url, candidate.adminURL]
    }

    public func history() -> [AgentWorkReceipt] {
        guard (try? AgentFilesystem.identity(activityDirectory, directory: true)) != nil,
              let files = try? FileManager.default.contentsOfDirectory(at: activityDirectory, includingPropertiesForKeys: nil) else { return [] }
        let candidates = files.compactMap { url -> (URL, FileIdentity)? in
            guard url.pathExtension == "json", let identity = try? AgentFilesystem.identity(url, directory: false),
                  identity.byteCount <= 64_000 else { return nil }; return (url, identity)
        }.sorted { $0.1.modifiedSeconds > $1.1.modifiedSeconds }
        return candidates.prefix(4_096).compactMap { url, _ in
            guard let data = try? AgentFilesystem.smallFile(url, limit: 64_000) else { return nil }
            guard var receipt = try? JSONDecoder().decode(AgentWorkReceipt.self, from: data),
                  url.lastPathComponent == receipt.id.uuidString + ".json" else { return nil }
            if [.pending, .failed].contains(receipt.status), (try? validateOwnedLock(receipt)) != nil {
                receipt.lockAcquired = true; receipt.status = .needsAttention
                receipt.detail = "A recovery lock remains from an interrupted operation. Restore to reconcile it; Room never guesses that a missing source was trashed."
            }
            if [.pending, .needsAttention].contains(receipt.status),
               !AgentFilesystem.exists(receipt.adminURL.appendingPathComponent("locked")),
               (try? validateLinkage(receipt)) != nil, recoveredSourceMatches(receipt) {
                receipt.status = .restored; receipt.lockAcquired = false
                receipt.detail = "The worktree is at its original location and the owned recovery lock is absent."
            }
            if candidates.count > 4_096 { receipt.detail += " Recovery history is limited to the newest 4,096 records; older receipt files remain in the recovery folder." }
            return receipt
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func clean(worktreeID: String, confirmsFinished: Bool) async throws -> AgentWorkReceipt {
        guard !isMutating else { throw AgentWorkError.message("Another worktree operation is already in progress.") }
        isMutating = true; defer { isMutating = false }
        guard confirmsFinished else { throw AgentWorkError.message("Confirm this work is finished before reviewing cleanup.") }
        guard let original = candidates[worktreeID], original.item.heldReasons.isEmpty else {
            throw AgentWorkError.message("This worktree is held. Resolve every review reason and scan again.")
        }
        let proof = await verify(worktreeID: worktreeID, duringMutation: true)
        guard proof.state == .verified else { throw AgentWorkError.message("Current HEAD could not be verified on the live remote.") }
        let activity = try await processReader()
        let fresh = try await inspect(original.item.url, owner: original.item.owner, activity: activity)
        guard fresh.item.heldReasons.isEmpty, fresh.snapshot.fingerprint == original.snapshot.fingerprint,
              fresh.item.head == proof.head else { throw AgentWorkError.message("The worktree changed or is active. Scan again.") }
        let id = UUID()
        var receipt = AgentWorkReceipt(id: id, createdAt: clock(), worktreeID: worktreeID, originalURL: fresh.item.url,
            repositoryURL: fresh.item.repositoryURL!, trashURL: nil, status: .pending, detail: "Preparing reversible worktree cleanup.",
            lockReason: "Room recovery " + id.uuidString, originalIdentity: fresh.snapshot.identity, parentIdentity: fresh.parent,
            adminURL: fresh.adminURL, adminIdentity: fresh.adminIdentity, fingerprint: fresh.snapshot.fingerprint,
            head: fresh.item.head!, branch: fresh.item.branch, dotGitPointer: String(decoding: try AgentFilesystem.smallFile(fresh.item.url.appendingPathComponent(".git")), as: UTF8.self), pushVerification: proof, commonURL: fresh.commonURL, commonIdentity: fresh.commonIdentity,
            dotGitIdentity: fresh.dotGitIdentity, lockAcquired: false, trashIdentity: nil)
        try persist(receipt)
        do {
            _ = try await git(["--git-dir=" + receipt.commonURL.path, "worktree", "lock", "--reason", receipt.lockReason, "--", fresh.item.url.path], at: URL(fileURLWithPath: "/var/empty", isDirectory: true))
            receipt.lockAcquired = true; try persist(receipt)
            try validateOwnedLock(receipt)
            try requireCurrent(fresh)
            let check = try await processReader()
            guard check.complete, AgentProcesses.matches(check, worktree: receipt.originalURL, admin: receipt.adminURL).isEmpty else {
                throw AgentWorkError.message("A process is using this worktree. Keep it in place.")
            }
            let final = try AgentFilesystem.snapshot(receipt.originalURL)
            guard final.fingerprint == receipt.fingerprint else { throw AgentWorkError.message("Worktree files changed before cleanup.") }
            let finalHead = try await git(["rev-parse", "--verify", "HEAD"], at: receipt.originalURL).text.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalStatus = try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching", "--ignore-submodules=all"], at: receipt.originalURL)
            guard finalHead == receipt.head, finalStatus.data.isEmpty else { throw AgentWorkError.message("Git state changed before cleanup.") }
            try validateOwnedLock(receipt)
            try requireCurrent(fresh)
            if let remote = proof.localRemoteURL, let identity = proof.localRemoteIdentity {
                guard AgentFilesystem.sameNode(try AgentFilesystem.identity(remote, directory: true), identity) else { throw AgentWorkError.message("The local remote changed before cleanup.") }
            }
            let destination = try trash(receipt.originalURL)
            receipt.trashURL = destination; receipt.status = .trashed
            receipt.detail = "In Trash. The branch and locked Git entry remain for recovery. Restore with Room."
            // Save returned Trash location before any additional filesystem work.
            try persist(receipt)
            try validateTrash(destination, original: receipt.originalURL)
            receipt.trashIdentity = try AgentFilesystem.identity(destination, directory: true, direct: fixtureTrash == nil)
            try persist(receipt)
            candidates.removeValue(forKey: worktreeID)
            return receipt
        } catch {
            if receipt.trashURL != nil {
                receipt.status = .needsAttention; receipt.detail = "The worktree moved to Trash; recovery metadata needs attention. Keep its Git lock and restore through Room or Finder."
            } else {
                if (try? validateOwnedLock(receipt)) != nil { receipt.lockAcquired = true }
                let intact = (try? AgentFilesystem.snapshot(receipt.originalURL))
                if receipt.lockAcquired, intact?.identity == receipt.originalIdentity, intact?.fingerprint == receipt.fingerprint {
                    do { try await unlockOwned(receipt); receipt.lockAcquired = false; receipt.status = .failed }
                    catch { receipt.status = .needsAttention }
                } else if receipt.lockAcquired { receipt.status = .needsAttention }
                else { receipt.status = .failed }
                receipt.detail = error.localizedDescription
            }
            try? persist(receipt)
            throw error
        }
    }

    public func restore(receiptID: UUID) async throws -> AgentWorkReceipt {
        guard !isMutating else { throw AgentWorkError.message("Another worktree operation is already in progress.") }
        isMutating = true; defer { isMutating = false }
        guard var receipt = history().first(where: { $0.id == receiptID }),
              [.trashed, .needsAttention].contains(receipt.status) else {
            throw AgentWorkError.message("No recoverable worktree receipt was found.")
        }
        try validateOwnedLock(receipt)
        try await validateReceiptHEAD(receipt)
        guard let source = receipt.trashURL else {
            let intact = try AgentFilesystem.snapshot(receipt.originalURL)
            guard intact.identity == receipt.originalIdentity, intact.fingerprint == receipt.fingerprint else {
                throw AgentWorkError.message("The interrupted operation is uncertain. Its protective Git lock remains; inspect the worktree manually.")
            }
            try await unlockOwned(receipt); receipt.lockAcquired = false; receipt.status = .restored
            receipt.detail = "The worktree stayed at its original location. Its owned recovery lock was released."
            try persist(receipt); return receipt
        }
        if !AgentFilesystem.exists(source), recoveredSourceMatches(receipt) {
            try await unlockOwned(receipt); receipt.lockAcquired = false; receipt.status = .restored
            receipt.detail = "The files were already restored; the owned recovery lock was released."
            try persist(receipt); return receipt
        }
        try validateTrash(source, original: receipt.originalURL)
        let parent = try AgentFilesystem.identity(receipt.originalURL.deletingLastPathComponent(), directory: true)
        guard AgentFilesystem.sameNode(parent, receipt.parentIdentity), !AgentFilesystem.exists(receipt.originalURL) else {
            throw AgentWorkError.message("The original location changed or is occupied. Room will not overwrite files.")
        }
        let measured = try AgentFilesystem.snapshot(source, rootReference: receipt.originalIdentity, exactTrash: fixtureTrash == nil)
        guard measured.fingerprint == receipt.fingerprint, !measured.partial, measured.safe else {
            throw AgentWorkError.message("The item in Trash changed. Inspect it manually before restoring.")
        }
        let activity = try await processReader()
        guard activity.complete, AgentProcesses.matches(activity, worktree: receipt.originalURL, admin: receipt.adminURL).isEmpty else {
            throw AgentWorkError.message("Git metadata is in use or activity could not be checked.")
        }
        try validateOwnedLock(receipt)
        try await validateReceiptHEAD(receipt)
        let pointer = String(decoding: try AgentFilesystem.smallFile(source.appendingPathComponent(".git"), direct: fixtureTrash == nil), as: UTF8.self)
        guard pointer == receipt.dotGitPointer else { throw AgentWorkError.message("The recovered Git pointer changed.") }
        _ = try AgentFilesystem.identity(receipt.originalURL.deletingLastPathComponent(), directory: true)
        guard AgentFilesystem.sameNode(try AgentFilesystem.identity(receipt.originalURL.deletingLastPathComponent(), directory: true), receipt.parentIdentity),
              !AgentFilesystem.exists(receipt.originalURL), try AgentFilesystem.identity(source, directory: true, direct: fixtureTrash == nil) == measured.identity else {
            throw AgentWorkError.message("A recovery location changed. Nothing was overwritten.")
        }
        try FileManager.default.moveItem(at: source, to: receipt.originalURL)
        receipt.status = .restored; receipt.detail = "Worktree restored to its original location."
        try persist(receipt)
        do { try await unlockOwned(receipt); receipt.lockAcquired = false; try persist(receipt) }
        catch { receipt.status = .needsAttention; receipt.detail = "Files are restored; the protective Git lock remains. Review its lock before further changes."; try? persist(receipt); throw error }
        return receipt
    }

    private func inspect(_ url: URL, owner: AgentWorkOwner, activity: AgentProcessSnapshot) async throws -> AgentCandidate {
        let snapshot = try AgentFilesystem.snapshot(url)
        let dotGit = url.appendingPathComponent(".git", isDirectory: false)
        let dotIdentity = try AgentFilesystem.identity(dotGit, directory: false)
        let filters = try await git(["config", "--local", "--no-includes", "--null", "--name-only", "--get-regexp", ".*"], at: url, accepted: [0, 1])
        let keys = filters.data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        guard !keys.map({ $0.lowercased() }).contains(where: {
            $0.hasPrefix("filter.") || $0.hasPrefix("include.") || $0.hasPrefix("includeif.") || $0 == "extensions.worktreeconfig" || $0 == "core.worktree"
        }) else { throw AgentWorkError.message("This repository configures content filters, included/worktree configuration or a redirected tree. Keep it in place for manual review.") }
        let top = try await git(["rev-parse", "--show-toplevel"], at: url).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(fileURLWithPath: top, isDirectory: true).roomLexicallyNormalized.path == url.path else {
            throw AgentWorkError.message("Git redirected inspection to a different worktree.")
        }
        let head = try await git(["rev-parse", "--verify", "HEAD"], at: url).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AgentGit.isOID(head) else { throw AgentWorkError.message("Git HEAD is not a complete commit identifier.") }
        let commonText = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: url).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let adminText = try await git(["rev-parse", "--path-format=absolute", "--git-dir"], at: url).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let common = URL(fileURLWithPath: commonText, isDirectory: true).roomLexicallyNormalized
        let admin = URL(fileURLWithPath: adminText, isDirectory: true).roomLexicallyNormalized
        let commonIdentity = try AgentFilesystem.identity(common, directory: true)
        let adminIdentity = try AgentFilesystem.identity(admin, directory: true)
        _ = try AgentFilesystem.identity(common.appendingPathComponent("config"), directory: false)
        let listing = try AgentGit.parseWorktrees(try await git(["worktree", "list", "--porcelain", "-z"], at: url))
        guard let record = listing.first(where: { $0.url.path == url.path }) else { throw AgentWorkError.message("The worktree is not registered with this repository.") }
        let linked = admin.path.hasPrefix(common.path + "/worktrees/") && admin.deletingLastPathComponent().path == common.path + "/worktrees"
        let repository = listing.first?.url
        var reasons: [String] = []
        if !linked || listing.first?.url.path == url.path { reasons.append("Main repositories and unregistered directories are never cleaned.") }
        if snapshot.identity.device != (try AgentFilesystem.identity(home, directory: true)).device {
            reasons.append("Automatic worktree recovery currently supports only the user's home volume.")
        }
        if record.locked { reasons.append("Git marks this worktree locked.") }
        if record.prunable { reasons.append("Git marks this entry prunable. Review its registry manually.") }
        // Detached agent work is retained in the locked administrative HEAD and
        // is eligible only after that exact commit is advertised by a live remote.
        if !snapshot.safe { reasons.append("Links, special files, hardlinks, nested repositories or foreign-owned files require manual review.") }
        if snapshot.partial { reasons.append("File inspection is incomplete; displayed size is a lower bound.") }
        var latest = snapshot.latest
        for path in ["HEAD", "index", "logs/HEAD"] {
            if let metadata = try? AgentFilesystem.identity(admin.appendingPathComponent(path), directory: false) {
                latest = max(latest, Date(timeIntervalSince1970: Double(max(metadata.modifiedSeconds, metadata.changedSeconds))))
            }
        }
        if clock().timeIntervalSince(latest) < 7 * 86_400 { reasons.append("Files or Git metadata were active within the last 7 days.") }
        if owner != .project, activity.paths.contains(where: { path in
            let name = path.name.lowercased()
            return owner == .codex ? (name.hasPrefix("codex") || name.hasPrefix("chatgpt")) : (name.hasPrefix("claude") || name == "node")
        }) { reasons.append("The owning agent is running; an idle session may still need this worktree.") }
        for path in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG", "rebase-merge", "rebase-apply", "sequencer"] {
            if AgentFilesystem.exists(admin.appendingPathComponent(path)) { reasons.append("A Git operation is in progress."); break }
        }
        let indexFlags = try await git(["ls-files", "-v", "-z"], at: url)
        if indexFlags.data.split(separator: 0).contains(where: { row in
            guard let flag = row.first else { return true }; return flag == 83 || (97...122).contains(flag)
        }) { reasons.append("The index hides paths with skip-worktree or assume-unchanged flags.") }
        let sparse = try await git(["config", "--bool", "--get", "core.sparseCheckout"], at: url, accepted: [0, 1])
        if sparse.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" { reasons.append("Sparse checkouts require manual review.") }
        let pids = AgentProcesses.matches(activity, worktree: url, admin: admin)
        if !pids.isEmpty { reasons.append("A running process has a working directory or open file here.") }
        if !activity.complete { reasons.append("Running-process file access could not be checked completely.") }
        let status = try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching", "--ignore-submodules=all"], at: url)
        let counts = try AgentGit.statusCounts(status.data)
        if counts.changed > 0 { reasons.append("Tracked files have local changes.") }
        if counts.untracked > 0 { reasons.append("Untracked files are present.") }
        if counts.ignored > 0 { reasons.append("Ignored local files or build resources are present.") }
        let submodules = try await git(["ls-files", "--stage", "-z"], at: url)
        if submodules.data.split(separator: 0).contains(where: { $0.starts(with: Array("160000 ".utf8)) }) { reasons.append("Submodules need manual review.") }
        if [common.appendingPathComponent("lfs"), common.appendingPathComponent("annex"), url.appendingPathComponent(".lfsconfig")].contains(where: AgentFilesystem.exists) {
            reasons.append("Large-file or annex payloads need separate backup verification; Git commit proof is insufficient.")
        }
        if reasons.isEmpty {
            let staged = submodules.data.split(separator: 0)
            if staged.count > 4_096 { reasons.append("Filter-attribute verification exceeds the review limit.") }
            else {
                var paths: [String] = []
                for row in staged {
                    guard let tab = row.firstIndex(of: 9), let path = String(data: Data(row.suffix(from: row.index(after: tab))), encoding: .utf8) else {
                        throw AgentWorkError.message("A tracked path could not be inspected safely.")
                    }
                    paths.append(path)
                }
                var batch: [String] = [], length = 0
                func hasFilter(_ result: AgentCommandResult) -> Bool {
                    let fields = result.data.split(separator: 0, omittingEmptySubsequences: true)
                    return stride(from: 2, to: fields.count, by: 3).contains { index in
                        let value = String(decoding: fields[index], as: UTF8.self)
                        return value != "unspecified" && value != "unset"
                    }
                }
                for path in paths {
                    if batch.count >= 128 || length + path.utf8.count > 32_000 {
                        if hasFilter(try await git(["check-attr", "--cached", "-z", "filter", "--"] + batch, at: url)) {
                            reasons.append("Tracked files use content filters; a Git commit does not prove their payloads are backed up."); break
                        }
                        batch = []; length = 0
                    }
                    batch.append(path); length += path.utf8.count
                }
                if reasons.isEmpty, !batch.isEmpty,
                   hasFilter(try await git(["check-attr", "--cached", "-z", "filter", "--"] + batch, at: url)) {
                    reasons.append("Tracked files use content filters; a Git commit does not prove their payloads are backed up.")
                }
            }
        }
        let item = AgentWorkItem(id: url.path, url: url, title: url.lastPathComponent, owner: owner,
            repositoryURL: repository, gitAdminURL: admin, gitCommonURL: common, branch: record.branch, head: head, lastActivityAt: latest,
            allocatedBytes: snapshot.bytes, isPartial: snapshot.partial, changedCount: counts.changed,
            untrackedCount: counts.untracked, ignoredCount: counts.ignored, processIDs: pids,
            isLinkedWorktree: linked, isLocked: record.locked, isPrunable: record.prunable,
            heldReasons: reasons, pushVerification: .notChecked)
        return AgentCandidate(item: item, snapshot: snapshot, parent: try AgentFilesystem.identity(url.deletingLastPathComponent(), directory: true),
            adminURL: admin, adminIdentity: adminIdentity, commonURL: common, commonIdentity: commonIdentity, dotGitIdentity: dotIdentity)
    }

    private func requireCurrent(_ item: AgentCandidate) throws {
        guard try AgentFilesystem.identity(item.item.url, directory: true) == item.snapshot.identity,
              AgentFilesystem.sameNode(try AgentFilesystem.identity(item.adminURL, directory: true), item.adminIdentity),
              AgentFilesystem.sameNode(try AgentFilesystem.identity(item.commonURL, directory: true), item.commonIdentity),
              try AgentFilesystem.identity(item.item.url.appendingPathComponent(".git"), directory: false) == item.dotGitIdentity,
              AgentFilesystem.sameNode(try AgentFilesystem.identity(item.item.url.deletingLastPathComponent(), directory: true), item.parent) else {
            throw AgentWorkError.message("Worktree or Git metadata identity changed. Scan again.")
        }
    }
    private func validateLinkage(_ receipt: AgentWorkReceipt) throws {
        guard receipt.lockReason == "Room recovery " + receipt.id.uuidString, receipt.worktreeID == receipt.originalURL.path,
              AgentGit.isOID(receipt.head), receipt.adminURL.deletingLastPathComponent().path == receipt.commonURL.appendingPathComponent("worktrees").path,
              AgentFilesystem.sameNode(try AgentFilesystem.identity(receipt.commonURL, directory: true), receipt.commonIdentity),
              AgentFilesystem.sameNode(try AgentFilesystem.identity(receipt.adminURL, directory: true), receipt.adminIdentity) else {
            throw AgentWorkError.message("Git administrative metadata was replaced.")
        }
        let gitdir = String(decoding: try AgentFilesystem.smallFile(receipt.adminURL.appendingPathComponent("gitdir")), as: UTF8.self).trimmingCharacters(in: .newlines)
        guard URL(fileURLWithPath: gitdir, relativeTo: receipt.adminURL).absoluteURL.roomLexicallyNormalized.path == receipt.originalURL.appendingPathComponent(".git").path else {
            throw AgentWorkError.message("This Git entry no longer registers the original worktree path.")
        }
        let commonPointer = String(decoding: try AgentFilesystem.smallFile(receipt.adminURL.appendingPathComponent("commondir")), as: UTF8.self).trimmingCharacters(in: .newlines)
        guard URL(fileURLWithPath: commonPointer, relativeTo: receipt.adminURL).absoluteURL.roomLexicallyNormalized.path == receipt.commonURL.path,
              receipt.repositoryURL.path == receipt.commonURL.path || receipt.repositoryURL.path == receipt.commonURL.deletingLastPathComponent().path else {
            throw AgentWorkError.message("The repository linkage changed.")
        }
        let head = String(decoding: try AgentFilesystem.smallFile(receipt.adminURL.appendingPathComponent("HEAD")), as: UTF8.self).trimmingCharacters(in: .newlines)
        let expected = receipt.branch.map { "ref: refs/heads/" + $0 } ?? receipt.head
        guard head == expected else { throw AgentWorkError.message("The worktree branch or detached HEAD changed.") }
        }
    private func validateOwnedLock(_ receipt: AgentWorkReceipt) throws {
        try validateLinkage(receipt)
        let lock = receipt.adminURL.appendingPathComponent("locked", isDirectory: false)
        _ = try AgentFilesystem.identity(lock, directory: false)
        let data = try AgentFilesystem.smallFile(lock)
        guard String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines) == receipt.lockReason else {
            throw AgentWorkError.message("The Git lock changed; Room will not unlock it.")
        }
    }
    private func recoveredSourceMatches(_ receipt: AgentWorkReceipt) -> Bool {
        guard let snapshot = try? AgentFilesystem.snapshot(receipt.originalURL, rootReference: receipt.originalIdentity) else { return false }
        return snapshot.safe && !snapshot.partial && snapshot.fingerprint == receipt.fingerprint
            && AgentFilesystem.sameNode(snapshot.identity, receipt.originalIdentity)
    }
    private func validateReceiptHEAD(_ receipt: AgentWorkReceipt) async throws {
        let output = try await git(["--git-dir=" + receipt.adminURL.path, "rev-parse", "--verify", "HEAD"], at: URL(fileURLWithPath: "/var/empty", isDirectory: true))
        guard output.text.trimmingCharacters(in: .whitespacesAndNewlines) == receipt.head else { throw AgentWorkError.message("The recorded branch or commit changed while recovery was pending.") }
    }
    private func unlockOwned(_ receipt: AgentWorkReceipt) async throws {
        try validateOwnedLock(receipt)
        try await validateReceiptHEAD(receipt)
        _ = try await git(["--git-dir=" + receipt.commonURL.path, "worktree", "unlock", "--", receipt.originalURL.path], at: URL(fileURLWithPath: "/var/empty", isDirectory: true))
    }
    private func validateTrash(_ url: URL, original: URL) throws {
        if let fixtureTrash {
            guard url.deletingLastPathComponent().path == fixtureTrash.path else { throw AgentWorkError.message("Unexpected recovery location.") }
            _ = try AgentFilesystem.identity(fixtureTrash, directory: true)
            return
        }
        let known = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        guard url.deletingLastPathComponent().path == known.path else { throw AgentWorkError.message("Automatic restore is unavailable for this volume. Restore this item through Finder.") }
        _ = try AgentFilesystem.identity(known, directory: true, direct: true)
    }
    private func persist(_ receipt: AgentWorkReceipt) throws {
        try AgentFilesystem.ensureDirectory(activityDirectory)
        _ = try AgentFilesystem.identity(activityDirectory, directory: true)
        let url = activityDirectory.appendingPathComponent(receipt.id.uuidString + ".json", isDirectory: false)
        if AgentFilesystem.exists(url) { _ = try AgentFilesystem.identity(url, directory: false) }
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        _ = chmod(url.path, 0o600)
    }
    private func validateLocalRemote(_ url: URL, candidate: AgentCandidate) async throws {
        guard ![candidate.item.url, candidate.commonURL].contains(where: {
            url.path == $0.path || url.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(url.path + "/")
        }) else { throw AgentWorkError.message("A local remote must be outside this worktree and its shared Git data.") }
        _ = try AgentFilesystem.identity(url, directory: true)
        _ = try AgentFilesystem.identity(url.appendingPathComponent("config"), directory: false)
        for path in ["objects/info/alternates", "info/grafts", "refs/replace"] {
            guard !AgentFilesystem.exists(url.appendingPathComponent(path)) else { throw AgentWorkError.message("This local remote uses alternate or replacement objects and needs manual review.") }
        }
        let keys = try await git(["config", "--local", "--no-includes", "--name-only", "--null", "--list"], at: url)
        let allowed: Set<String> = ["core.repositoryformatversion", "core.filemode", "core.bare", "core.logallrefupdates", "core.ignorecase", "core.precomposeunicode"]
        guard keys.data.split(separator: 0).allSatisfy({ allowed.contains(String(decoding: $0, as: UTF8.self).lowercased()) }) else {
            throw AgentWorkError.message("This local remote has custom configuration and needs manual review.")
        }
        let bare = try await git(["rev-parse", "--is-bare-repository"], at: url)
        guard bare.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { throw AgentWorkError.message("A local remote must be a separate bare repository.") }
    }
    private func git(_ arguments: [String], at url: URL, timeout: TimeInterval = 8, accepted: Set<Int32> = [0]) async throws -> AgentCommandResult {
        let result = try await runner(URL(fileURLWithPath: "/usr/bin/git"), AgentGit.options + arguments, url, timeout)
        guard accepted.contains(result.status) else { throw AgentWorkError.message("Git inspection could not be completed safely.") }
        return result
    }
}

private struct AgentCandidate: Sendable {
    var item: AgentWorkItem
    let snapshot: AgentTreeSnapshot
    let parent: FileIdentity
    let adminURL: URL
    let adminIdentity: FileIdentity
    let commonURL: URL
    let commonIdentity: FileIdentity
    let dotGitIdentity: FileIdentity
}
struct AgentCommandResult: Sendable { let status: Int32; let data: Data; var stderr: Data = Data(); var text: String { String(decoding: data, as: UTF8.self) } }
struct AgentProcessPath: Sendable { let pid: Int32; let name: String; let url: URL }
struct AgentProcessSnapshot: Sendable { let paths: [AgentProcessPath]; let complete: Bool }
enum AgentWorkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum AgentGit {
    static let options = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
        "-c", "core.untrackedCache=false", "-c", "core.preloadIndex=false", "-c", "gc.auto=0", "-c", "maintenance.auto=false",
        "-c", "credential.helper=", "-c", "core.askPass=", "-c", "core.pager=cat", "-c", "diff.external=",
        "-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "protocol.ssh.allow=always"]
    struct Worktree { let url: URL; let branch: String?; let locked: Bool; let prunable: Bool }
    static func parseWorktrees(_ output: AgentCommandResult) throws -> [Worktree] {
        guard output.status == 0 else { throw AgentWorkError.message("Git worktree registry is unavailable.") }
        var result: [Worktree] = [], path: String?, branch: String?, locked = false, prunable = false
        func finish() { if let path { result.append(Worktree(url: URL(fileURLWithPath: path, isDirectory: true).roomLexicallyNormalized,
            branch: branch, locked: locked, prunable: prunable)) } }
        for raw in output.data.split(separator: 0, omittingEmptySubsequences: false) {
            let field = String(decoding: raw, as: UTF8.self)
            if field.isEmpty { finish(); path = nil; branch = nil; locked = false; prunable = false }
            else if field.hasPrefix("worktree ") { path = String(field.dropFirst(9)) }
            else if field.hasPrefix("branch refs/heads/") { branch = String(field.dropFirst(18)) }
            else if field == "locked" || field.hasPrefix("locked ") { locked = true }
            else if field == "prunable" || field.hasPrefix("prunable ") { prunable = true }
        }
        finish()
        guard result.count <= 256 else { throw AgentWorkError.message("The worktree registry exceeds the review limit.") }
        return result
    }
    static func isOID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
    static func safeRemoteName(_ value: String) -> Bool {
        !value.isEmpty && value.count < 128 && value.first != "-" && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-/".contains($0)) }
    }
    static func allowedRemote(_ value: String, fixture: Bool = false) -> Bool {
        if fixture, value.hasPrefix("/private/tmp/RoomAgent-") { return true }
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\\" }), !value.hasPrefix("-") else { return false }
        if let components = URLComponents(string: value), ["https", "ssh"].contains(components.scheme),
           let host = components.host, !host.isEmpty, !host.hasPrefix("-"), components.password == nil,
           components.query == nil, components.fragment == nil,
           components.scheme != "https" || components.user == nil {
            return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".:-[]".contains($0)) }
                && (components.user?.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-".contains($0)) } ?? true)
        }
        // Conventional SCP-style Git SSH URLs; no shell metacharacters or options.
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[1].isEmpty else { return false }
        let authority = parts[0].split(separator: "@", maxSplits: 1)
        guard authority.count == 2, !authority[0].isEmpty, !authority[1].isEmpty else { return false }
        return authority[0].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-".contains($0)) }
            && authority[1].first != "-" && authority[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }
            && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_./-".contains($0)) }
    }
    static func exactRemoteRef(head: String, data: Data) -> String? {
        guard isOID(head) else { return nil }
        for line in data.split(separator: 10) {
            let parts = line.split(separator: 9, maxSplits: 1)
            if parts.count == 2, String(decoding: parts[0], as: UTF8.self) == head,
               parts[1].starts(with: Array("refs/heads/".utf8)) || parts[1].starts(with: Array("refs/tags/".utf8)) {
                return String(decoding: parts[1], as: UTF8.self)
            }
        }
        return nil
    }
    static func remoteContainsExact(head: String, data: Data) -> Bool { exactRemoteRef(head: head, data: data) != nil }
    static func statusCounts(_ data: Data) throws -> (changed: Int, untracked: Int, ignored: Int) {
        let fields = data.split(separator: 0)
        var changed = 0, untracked = 0, ignored = 0, index = 0
        while index < fields.count {
            let bytes = fields[index]
            guard bytes.count >= 4, bytes[bytes.startIndex + 2] == 32 else { throw AgentWorkError.message("Git status output was incomplete.") }
            let prefix = Array(bytes.prefix(2))
            if prefix == [63, 63] { untracked += 1 }
            else if prefix == [33, 33] { ignored += 1 }
            else { changed += 1; if prefix.contains(82) || prefix.contains(67) { index += 1 } }
            index += 1
        }
        return (changed, untracked, ignored)
    }
}

enum AgentCommand {
    static func run(_ executable: URL, _ arguments: [String], _ cwd: URL?, _ timeout: TimeInterval) async throws -> AgentCommandResult {
        try Task.checkCancellation()
        let process = Process(), pipe = Pipe(), errors = Pipe()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = cwd
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin", "HOME": "/var/empty", "LANG": "en_US.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false",
            "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1",
            "GIT_SSH_COMMAND": "/usr/bin/ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no -o ProxyCommand=none -o ProxyJump=none -o PermitLocalCommand=no -o ConnectTimeout=5"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = errors
        let fd = pipe.fileHandleForReading.fileDescriptor
        let errorFD = errors.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(errorFD, F_SETFL, fcntl(errorFD, F_GETFL) | O_NONBLOCK) == 0 else { throw AgentWorkError.message("The inspection pipe is unavailable.") }
        let commandID = UUID()
        try AgentOwnedCommands.shared.start(id: commandID, process: process)
        try? pipe.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        defer { AgentOwnedCommands.shared.remove(id: commandID); try? pipe.fileHandleForReading.close(); try? errors.fileHandleForReading.close() }
        var data = Data(), stderr = Data()
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        func drain(_ descriptor: Int32, into destination: inout Data, limit: Int) throws -> Bool {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 { guard destination.count + count <= limit else { throw AgentWorkError.message("Inspection output exceeded its safety limit.") }; destination.append(contentsOf: buffer.prefix(count)) }
                else if count == 0 { return true }
                else if errno == EAGAIN || errno == EWOULDBLOCK { return false }
                else if errno != EINTR { throw AgentWorkError.message("Inspection output could not be read.") }
            }
        }
        do {
            while process.isRunning {
                _ = try drain(fd, into: &data, limit: 8_000_000)
                _ = try drain(errorFD, into: &stderr, limit: 1_000_000)
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw AgentWorkError.message("Inspection timed out. Keep this worktree.") }
                try await Task.sleep(for: .milliseconds(15))
            }
            let finalDeadline = ContinuousClock.now.advanced(by: .milliseconds(300))
            while true {
                let stdoutClosed = try drain(fd, into: &data, limit: 8_000_000)
                let stderrClosed = try drain(errorFD, into: &stderr, limit: 1_000_000)
                if stdoutClosed && stderrClosed { break }
                guard ContinuousClock.now < finalDeadline else { throw AgentWorkError.message("Inspection output did not close.") }
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            await Task.detached(priority: .utility) {
                if process.isRunning { process.interrupt() }
                let first = ContinuousClock.now.advanced(by: .milliseconds(250))
                while process.isRunning, ContinuousClock.now < first { try? await Task.sleep(for: .milliseconds(15)) }
                if process.isRunning { process.terminate() }
                let second = ContinuousClock.now.advanced(by: .milliseconds(250))
                while process.isRunning, ContinuousClock.now < second { try? await Task.sleep(for: .milliseconds(15)) }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }.value
            throw error
        }
        return AgentCommandResult(status: process.terminationStatus, data: data, stderr: stderr)
    }
}

enum AgentProcesses {
    static func read() async throws -> AgentProcessSnapshot {
        let before = try await inventory()
        let output = try await AgentCommand.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-nP", "-a", "-u", String(getuid()), "-F0pcfn"], nil, 6)
        let after = try await inventory()
        let stable = Set(before.keys.filter { before[$0] == after[$0] && $0 != getpid() })
        let observed = observedPIDs(output.data)
        let parsed = parse(output)
        return AgentProcessSnapshot(paths: parsed.paths, complete: parsed.complete && stable.isSubset(of: observed))
    }
    static func parse(_ output: AgentCommandResult) -> AgentProcessSnapshot {
        var paths: [AgentProcessPath] = [], pid: Int32?, name = "Process", accessError = !output.stderr.isEmpty
        for field in output.data.split(separator: 0) {
            let value = String(decoding: field, as: UTF8.self).drop(while: { $0 == "\n" })
            guard let type = value.first else { continue }
            let content = String(value.dropFirst())
            switch type {
            case "p": pid = Int32(content)
            case "c": name = content
            case "n":
                let lower = content.lowercased()
                if lower.contains("info error") || lower.contains("permission denied") || lower.contains("operation not permitted") { accessError = true }
                if let pid, content.hasPrefix("/"), pid != getpid() {
                paths.append(AgentProcessPath(pid: pid, name: name, url: URL(fileURLWithPath: content, isDirectory: false).roomLexicallyNormalized))
            }
            default: break
            }
        }
        return AgentProcessSnapshot(paths: paths, complete: output.status == 0 && !paths.isEmpty && !accessError)
    }
    private static func inventory() async throws -> [Int32: String] {
        let result = try await AgentCommand.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "uid=,pid=,lstart=,comm="], nil, 3)
        guard result.status == 0, result.stderr.isEmpty else { throw AgentWorkError.message("Process identity coverage could not be checked.") }
        var values: [Int32: String] = [:]
        for line in result.text.split(separator: "\n") {
            let fields = line.split(maxSplits: 7, whereSeparator: \.isWhitespace)
            guard fields.count >= 8, UInt32(fields[0]) == getuid(), let pid = Int32(fields[1]), pid > 0 else { continue }
            values[pid] = fields[2...6].joined(separator: " ")
        }
        guard !values.isEmpty else { throw AgentWorkError.message("Same-user process identity coverage is unavailable.") }
        return values
    }
    static func observedPIDs(_ data: Data) -> Set<Int32> {
        Set(data.split(separator: 0).compactMap { field in
            let text = String(decoding: field, as: UTF8.self).drop(while: { $0 == "\n" })
            return text.first == "p" ? Int32(text.dropFirst()) : nil
        })
    }
    static func matches(_ snapshot: AgentProcessSnapshot, worktree: URL, admin: URL) -> [Int32] {
        Set(snapshot.paths.filter { path in
            [worktree, admin].contains { path.url.path == $0.path || path.url.path.hasPrefix($0.path + "/") }
        }.map(\.pid)).sorted()
    }
}

private struct AgentTreeSnapshot: Sendable {
    let identity: FileIdentity
    let fingerprint: String
    let latest: Date
    let bytes: Int64
    let partial: Bool
    let safe: Bool
}
private enum AgentFilesystem {
    static func ensureDirectory(_ url: URL) throws {
        let components = url.pathComponents.filter { $0 != "/" }
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AgentWorkError.message("Recovery storage is unavailable.") }
        defer { close(fd) }
        for component in components {
            var next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                guard mkdirat(fd, component, 0o700) == 0 else { throw AgentWorkError.message("Recovery storage could not be created safely.") }
                next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else { throw AgentWorkError.message("Recovery storage has an inaccessible or symbolic-link ancestor.") }
            close(fd); fd = next
        }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid() else { throw AgentWorkError.message("Recovery storage is not owned by this user.") }
    }
    static func openDirectory(_ url: URL, readable: Bool = false) throws -> Int32 {
        guard url.isFileURL else { throw AgentWorkError.message("Only local file paths can be inspected.") }
        let components = url.pathComponents.filter { $0 != "/" }
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AgentWorkError.message("The filesystem root is unavailable.") }
        for (index, component) in components.enumerated() {
            let next = openat(fd, component, ((readable && index == components.count - 1) ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw AgentWorkError.message("A directory is inaccessible or contains a symbolic link.") }
            fd = next
        }
        return fd
    }
    static func info(_ url: URL, directory: Bool) throws -> stat {
        let parent = try openDirectory(url.deletingLastPathComponent())
        defer { close(parent) }
        var info = stat()
        guard fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_uid == getuid(), info.st_mode & UInt16(S_IFMT) == UInt16(directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw AgentWorkError.message("The item is missing, linked, replaced or not owned by this user.") }
        return info
    }
    static func identity(_ url: URL, directory: Bool, direct: Bool = false) throws -> FileIdentity {
        if !direct { return identity(try info(url, directory: directory)) }
        try validateAncestors(url)
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, metadata.st_uid == getuid(),
              metadata.st_mode & UInt16(S_IFMT) == UInt16(directory ? S_IFDIR : S_IFREG), directory || metadata.st_nlink == 1 else {
            throw AgentWorkError.message("The exact recovery item changed.")
        }
        return identity(metadata)
    }
    static func validateAncestors(_ url: URL) throws {
        var current = url
        while current.path != "/" {
            var metadata = stat()
            guard lstat(current.path, &metadata) == 0, metadata.st_mode & UInt16(S_IFMT) != UInt16(S_IFLNK) else {
                throw AgentWorkError.message("A recovery path contains a missing or symbolic-link ancestor.")
            }
            current.deleteLastPathComponent()
        }
    }
    static func identity(_ metadata: stat) -> FileIdentity {
        FileIdentity(device: UInt64(bitPattern: Int64(metadata.st_dev)), inode: UInt64(metadata.st_ino),
            modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            changedSeconds: Int64(metadata.st_ctimespec.tv_sec), changedNanoseconds: Int64(metadata.st_ctimespec.tv_nsec),
            byteCount: Int64(metadata.st_size), mode: metadata.st_mode)
    }
    static func sameNode(_ a: FileIdentity, _ b: FileIdentity) -> Bool { a.device == b.device && a.inode == b.inode && a.mode == b.mode }
    static func exists(_ url: URL) -> Bool {
        guard let fd = try? openDirectory(url.deletingLastPathComponent()) else { return errno != ENOENT }
        defer { close(fd) }; var info = stat()
        return fstatat(fd, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT
    }
    static func smallFile(_ url: URL, direct: Bool = false, limit: Int = 8_192) throws -> Data {
        let fd: Int32
        if direct {
            _ = try identity(url, directory: false, direct: true)
            fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        } else {
            _ = try info(url, directory: false)
            let parent = try openDirectory(url.deletingLastPathComponent()); defer { close(parent) }
            fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard fd >= 0 else { throw AgentWorkError.message("Git metadata cannot be read.") }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG), info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= limit else { throw AgentWorkError.message("Git metadata exceeds the safety limit or is not a regular owned file.") }
        var data = Data(), buffer = [UInt8](repeating: 0, count: min(limit + 1, 8_192))
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0, data.count + count <= limit else { throw AgentWorkError.message("Git metadata cannot be read completely.") }
            data.append(contentsOf: buffer.prefix(count))
        }
        var final = stat()
        guard fstat(fd, &final) == 0, identity(info) == identity(final) else { throw AgentWorkError.message("Git metadata changed while reading.") }
        return data
    }
    static func discover(_ root: URL, owner: AgentWorkOwner) throws -> [(URL, AgentWorkOwner)] {
        if !exists(root) { return [] }
        var results: [(URL, AgentWorkOwner)] = [], visits = 0
        func visit(_ url: URL, depth: Int) throws {
            try Task.checkCancellation(); visits += 1
            guard visits <= 512 else { throw AgentWorkError.message("Agent worktree discovery exceeded its folder limit.") }
            let fd = try openDirectory(url, readable: true); defer { close(fd) }
            var rootInfo = stat(); guard fstat(fd, &rootInfo) == 0, rootInfo.st_uid == getuid() else { return }
            var gitInfo = stat()
            if fstatat(fd, ".git", &gitInfo, AT_SYMLINK_NOFOLLOW) == 0,
               [UInt16(S_IFREG), UInt16(S_IFDIR)].contains(gitInfo.st_mode & UInt16(S_IFMT)) { results.append((url, owner)); return }
            guard depth > 0 else { return }
            let copied = dup(fd); guard copied >= 0, let stream = fdopendir(copied) else { if copied >= 0 { close(copied) }; return }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = entryName(entry)
                guard name != ".", name != ".." else { continue }
                var child = stat()
                guard fstatat(fd, name, &child, AT_SYMLINK_NOFOLLOW) == 0, child.st_uid == getuid(),
                      child.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { continue }
                try visit(url.appendingPathComponent(name, isDirectory: false), depth: depth - 1)
            }
        }
        try visit(root, depth: 2)
        return results
    }
    static func snapshot(_ url: URL, rootReference: FileIdentity? = nil, exactTrash: Bool = false) throws -> AgentTreeSnapshot {
        let rootFD: Int32
        if exactTrash {
            try validateAncestors(url)
            rootFD = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard rootFD >= 0 else { throw AgentWorkError.message("The exact Trash item could not be inspected.") }
        } else { rootFD = try openDirectory(url, readable: true) }
        defer { close(rootFD) }
        var root = stat(); guard fstat(rootFD, &root) == 0, root.st_uid == getuid() else { throw AgentWorkError.message("The worktree is not owned by this user.") }
        let actual = identity(root)
        var digest: UInt64 = 14_695_981_039_346_656_037, bytes: Int64 = 0, nodes = 0, partial = false, safe = true
        var latest = Date(timeIntervalSince1970: Double(max(root.st_mtimespec.tv_sec, root.st_ctimespec.tv_sec)))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        func append(_ text: String) { for byte in text.utf8 { digest = (digest ^ UInt64(byte)) &* 1_099_511_628_211 } }
        func token(_ metadata: stat, _ path: String) {
            var item = identity(metadata)
            if path == ".", let reference = rootReference,
               sameNode(item, reference), item.byteCount == reference.byteCount,
               item.modifiedSeconds == reference.modifiedSeconds, item.modifiedNanoseconds == reference.modifiedNanoseconds { item = reference }
            append("\(path.utf8.count):\(path)|\(item.device)|\(item.inode)|\(item.mode)|\(item.byteCount)|\(item.modifiedSeconds):\(item.modifiedNanoseconds)|\(item.changedSeconds):\(item.changedNanoseconds);\(metadata.st_nlink);")
        }
        func walk(_ fd: Int32, relative: String, depth: Int) throws {
            try Task.checkCancellation()
            guard depth < 64, nodes < 100_000, ContinuousClock.now < deadline else { partial = true; return }
            let copied = dup(fd); guard copied >= 0 else { partial = true; return }
            guard let stream = fdopendir(copied) else { close(copied); partial = true; return }
            defer { closedir(stream) }
            var names: [String] = []
            while let entry = readdir(stream) {
                let name = entryName(entry)
                if name != ".", name != ".." { names.append(name) }
                if names.count > 100_000 { partial = true; break }
            }
            for name in names.sorted() {
                try Task.checkCancellation()
                guard nodes < 100_000, ContinuousClock.now < deadline else { partial = true; break }
                nodes += 1
                let path = relative.isEmpty ? name : relative + "/" + name
                var metadata = stat()
                guard fstatat(fd, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { partial = true; continue }
                token(metadata, path)
                latest = max(latest, Date(timeIntervalSince1970: Double(max(metadata.st_mtimespec.tv_sec, metadata.st_ctimespec.tv_sec))))
                let type = metadata.st_mode & UInt16(S_IFMT)
                if metadata.st_uid != getuid() || (type != UInt16(S_IFDIR) && type != UInt16(S_IFREG)) || (type == UInt16(S_IFREG) && metadata.st_nlink != 1) { safe = false; continue }
                if name == ".git", !relative.isEmpty { safe = false }
                if type == UInt16(S_IFREG) { bytes += Int64(metadata.st_blocks) * 512 }
                else {
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { partial = true; continue }
                    defer { close(child) }
                    var opened = stat()
                    guard fstat(child, &opened) == 0, identity(opened) == identity(metadata) else { partial = true; continue }
                    try walk(child, relative: path, depth: depth + 1)
                    var finished = stat()
                    guard fstat(child, &finished) == 0, identity(finished) == identity(opened) else { throw AgentWorkError.message("A nested directory changed during inspection.") }
                }
            }
        }
        token(root, "."); try walk(rootFD, relative: "", depth: 0)
        var end = stat(); guard fstat(rootFD, &end) == 0, identity(end) == actual else { throw AgentWorkError.message("The worktree changed during inspection.") }
        return AgentTreeSnapshot(identity: actual, fingerprint: String(digest, radix: 16), latest: latest, bytes: bytes, partial: partial, safe: safe)
    }
    static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
    }
}

/// Holds only children started by this engine; Quit never targets another app.
private final class AgentOwnedCommands: Sendable {
    static let shared = AgentOwnedCommands()
    private let commands = Mutex<[UUID: Process]>([:])
    func start(id: UUID, process: Process) throws {
        try commands.withLock { value in try process.run(); value[id] = process }
    }
    func remove(id: UUID) { _ = commands.withLock { $0.removeValue(forKey: id) } }
    func shutdown() {
        let owned = commands.withLock { Array($0.values) }
        for process in owned where process.isRunning { process.interrupt() }
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline, owned.contains(where: \.isRunning) { Thread.sleep(forTimeInterval: 0.01) }
        for process in owned where process.isRunning { process.terminate() }
        let final = Date().addingTimeInterval(0.3)
        while Date() < final, owned.contains(where: \.isRunning) { Thread.sleep(forTimeInterval: 0.01) }
        for process in owned where process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
}
