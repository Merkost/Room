import Darwin
import Foundation

/// Read-only review. No emulator/Gradle execution, deletion, or implicit home
/// discovery occurs. Paths and timestamps are evidence, not an unused verdict.
public actor DeveloperResourcesEngine {
    public init() { }

    /// Reads the same bounded cwd/open-file evidence used by worktree review.
    /// Incomplete coverage is never converted into an unused-resource verdict.
    public static func activitySnapshot() async -> DeveloperActivitySnapshot {
        #if ROOM_APP_STORE
        return .unknown
        #else
        do {
            let sample = try await AgentProcesses.read()
            let groups = Dictionary(grouping: sample.paths, by: \.pid)
            let processes = groups.keys.sorted().prefix(4_096).compactMap { pid -> DeveloperResourceProcess? in
                guard let paths = groups[pid], let first = paths.first else { return nil }
                return DeveloperResourceProcess(processID: pid, name: first.name, paths: paths.map(\.url))
            }
            return DeveloperActivitySnapshot(processes: processes, isComplete: sample.complete && groups.count <= 4_096
                && !groups.values.contains(where: { $0.count > 256 }))
        } catch { return .unknown }
        #endif
    }

    public func scan(request: DeveloperResourcesRequest,
                     progress: (@Sendable (DeveloperResourcesProgress) -> Void)? = nil) async -> DeveloperResourcesReport {
        let roles = [!request.projectRoots.isEmpty, !request.avdRoots.isEmpty, !request.gradleHomes.isEmpty].filter { $0 }.count
        guard roles > 1, request.limits.maximumNodes >= roles, request.limits.maximumResources >= roles else {
            return await scanPhase(request: request, progress: progress)
        }
        // Each selected role receives a reserved share. A large projects tree
        // cannot consume the Android/Gradle portions of the bounded review.
        let limits = DeveloperResourcesLimits(maximumNodes: max(1, request.limits.maximumNodes / roles),
            maximumDepth: request.limits.maximumDepth, maximumResources: max(1, request.limits.maximumResources / roles),
            maximumFileBytes: request.limits.maximumFileBytes, timeLimit: request.limits.timeLimit / Double(roles))
        var phases: [DeveloperResourcesRequest] = []
        if !request.projectRoots.isEmpty {
            phases.append(DeveloperResourcesRequest(approvedFolders: request.approvedFolders,
                projectRoots: request.projectRoots, activity: request.activity, limits: limits))
        }
        if !request.avdRoots.isEmpty {
            phases.append(DeveloperResourcesRequest(approvedFolders: request.approvedFolders,
                avdRoots: request.avdRoots, activity: request.activity, limits: limits))
        }
        if !request.gradleHomes.isEmpty {
            phases.append(DeveloperResourcesRequest(approvedFolders: request.approvedFolders,
                gradleHomes: request.gradleHomes, activity: request.activity, limits: limits))
        }
        let id = UUID(), date = Date()
        var avds: [AndroidVirtualDeviceResource] = [], gradle: [GradleDeveloperResource] = []
        var wrappers: [GradleProjectWrapper] = [], issues: [ScanIssue] = []
        var partial = false
        for phase in phases {
            if Task.isCancelled { break }
            let report = await scanPhase(request: phase, knownWrappers: wrappers, progress: progress)
            avds.append(contentsOf: report.androidDevices)
            gradle.append(contentsOf: report.gradleResources)
            wrappers = report.projectWrappers
            issues.append(contentsOf: report.issues)
            partial = partial || report.isPartial
        }
        return DeveloperResourcesReport(id: id, scannedAt: date,
            androidDevices: avds.sorted { $0.allocatedBytes > $1.allocatedBytes },
            gradleResources: gradle.sorted { $0.allocatedBytes > $1.allocatedBytes },
            projectWrappers: wrappers, issues: Array(issues.prefix(384)), cancelled: Task.isCancelled,
            isPartial: partial || Task.isCancelled)
    }

    private func scanPhase(request: DeveloperResourcesRequest, knownWrappers: [GradleProjectWrapper] = [],
                           progress: (@Sendable (DeveloperResourcesProgress) -> Void)? = nil) async -> DeveloperResourcesReport {
        let id = UUID(), date = Date()
        let budget = DRBudget(request.limits)
        var avds: [AndroidVirtualDeviceResource] = [], gradle: [GradleDeveloperResource] = []
        var wrappers = knownWrappers
        var approvals: [URL] = []
        for supplied in request.approvedFolders.prefix(64) {
            let url = supplied.roomLexicallyNormalized
            do {
                guard supplied.isFileURL, url.path != "/" else { throw DRReadError.invalidRoot }
                _ = try DRFiles.directory(url)
                if !approvals.contains(where: { $0.path == url.path }) { approvals.append(url) }
            } catch { budget.note(url, "The approved folder is unavailable, linked or not owned by this user.") }
        }
        if request.approvedFolders.count > 64 { budget.note(URL(fileURLWithPath: "/"), "Only the first 64 approved folders were considered.") }
        func permitted(_ supplied: URL) -> URL? {
            let url = supplied.roomLexicallyNormalized
            guard supplied.isFileURL, approvals.contains(where: { DRFiles.contains(url, in: $0) }) else {
                budget.note(url, "This requested location needs explicit folder approval. It was not inspected.")
                return nil
            }
            return url
        }
        func update(_ phase: String, _ url: URL) {
            progress?(DeveloperResourcesProgress(phase: phase, inspectedCount: budget.nodes, currentPath: url.path))
        }
        do {
            var searched: Set<String> = []
            for supplied in request.projectRoots.prefix(32) {
                try budget.check()
                guard let root = permitted(supplied), searched.insert(root.path).inserted else { continue }
                update("Project wrappers", root)
                do { try DRProjects.find(root, budget: budget, wrappers: &wrappers) }
                catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(root, "Project wrapper inspection was incomplete; no scripts or build configuration were executed.") }
                await Task.yield()
            }
            var seenAVDs: Set<String> = []
            for supplied in request.avdRoots.prefix(32) {
                try budget.check()
                guard let root = permitted(supplied) else { continue }
                update("Android devices", root)
                let candidates: [URL]
                do {
                    candidates = root.lastPathComponent.lowercased().hasSuffix(".avd") ? [root]
                        : try DRFiles.children(root, budget: budget).filter { $0.lastPathComponent.lowercased().hasSuffix(".avd") }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(root, "The selected AVD location could not be enumerated safely."); continue }
                for url in candidates where seenAVDs.insert(url.path).inserted {
                    try budget.resource()
                    update("Android devices", url)
                    do { avds.append(try androidDevice(url, request: request, budget: budget,
                        verificationProgress: { update("Verifying resource", url) })) }
                    catch is CancellationError { throw CancellationError() }
                    catch is DRStop { throw DRStop.limit }
                    catch { budget.note(url, "This AVD could not be inspected safely. Linked or inaccessible directories are skipped.") }
                }
                await Task.yield()
            }
            var seenGradle: Set<String> = []
            for supplied in request.gradleHomes.prefix(32) {
                guard supplied.isFileURL else { budget.note(supplied, "Choose a local Gradle home folder."); continue }
                let home = supplied.roomLexicallyNormalized
                for (relative, kind) in [("wrapper/dists", GradleDeveloperResourceKind.distribution), ("caches", .sharedCache)] {
                    try budget.check()
                    // An approved caches/dists child can be inspected without
                    // opening an unapproved Gradle home or its properties file.
                    let target = home.appendingPathComponent(relative, isDirectory: true)
                    guard let root = permitted(target) else { continue }
                    update("Gradle resources", root)
                    let children: [URL]
                    do { children = try DRFiles.children(root, budget: budget) }
                    catch is CancellationError { throw CancellationError() }
                    catch is DRStop { throw DRStop.limit }
                    catch { budget.note(root, "This Gradle cache/distribution directory is unavailable or inaccessible."); continue }
                    for url in children where seenGradle.insert(url.path).inserted {
                        try budget.resource()
                        update("Gradle resources", url)
                        do {
                            let info = try DRFiles.metadata(url)
                            guard DRFiles.isDirectory(info) else { continue }
                            let distribution = DRVersions.distribution(url.lastPathComponent)
                            if kind == .distribution, distribution == nil { continue }
                            let version = kind == .distribution ? distribution?.version : DRVersions.version(url.lastPathComponent)
                            let type = kind == .distribution ? distribution?.type : nil
                            let measured = try DRFiles.measure(url, budget: budget,
                                beforeFinalValidation: { update("Verifying resource", url) })
                            let matches = version.map { value in wrappers.filter {
                                $0.version == value && (kind != .distribution || $0.distributionType == type)
                            } } ?? []
                            let note: String
                            if version == nil { note = "Shared across Gradle versions. Selected project wrappers cannot establish that this cache is unused." }
                            else if matches.isEmpty { note = "No discovered wrapper in the selected projects references this \(kind == .distribution ? "distribution" : "version"). Other projects and offline builds may still need it." }
                            else { note = "Referenced by \(matches.count) selected project \(matches.count == 1 ? "wrapper" : "wrappers"). This is configuration evidence, not proof of recent execution." }
                            gradle.append(GradleDeveloperResource(url: url, name: url.lastPathComponent,
                                kind: kind == .distribution ? .distribution : version == nil ? .sharedCache : .versionCache,
                                version: version, distributionType: type, allocatedBytes: measured.allocated,
                                logicalBytes: measured.logical, isPartial: measured.partial,
                                projectUses: matches, usageNote: note, evidence: measured.evidence,
                                activity: try activity(for: url, avdName: nil, measured: measured, snapshot: request.activity, budget: budget)))
                        } catch is CancellationError { throw CancellationError() }
                        catch is DRStop { throw DRStop.limit }
                        catch { budget.note(url, "This Gradle resource could not be inspected safely.") }
                    }
                }
                await Task.yield()
            }
        } catch is CancellationError { }
        catch { budget.limited = true }
        if request.projectRoots.count > 32 || request.avdRoots.count > 32 || request.gradleHomes.count > 32 {
            budget.note(approvals.first ?? URL(fileURLWithPath: "/"), "Each resource role is limited to its first 32 selected roots.")
        }
        if budget.limited { budget.note(approvals.first ?? URL(fileURLWithPath: "/"), "The bounded scan reached a time, depth, node or resource limit. Results and size measurements may be incomplete.") }
        return DeveloperResourcesReport(id: id, scannedAt: date,
            androidDevices: avds.sorted { $0.allocatedBytes > $1.allocatedBytes },
            gradleResources: gradle.sorted { $0.allocatedBytes > $1.allocatedBytes },
            projectWrappers: wrappers.sorted { $0.propertiesURL.path < $1.propertiesURL.path },
            issues: budget.issues, cancelled: Task.isCancelled,
            isPartial: Task.isCancelled || budget.limited || !budget.issues.isEmpty || avds.contains(where: \.isPartial)
                || gradle.contains(where: \.isPartial) || wrappers.contains(where: \.isPartial))
    }

    private func androidDevice(_ url: URL, request: DeveloperResourcesRequest, budget: DRBudget,
                               verificationProgress: () -> Void) throws -> AndroidVirtualDeviceResource {
        _ = try DRFiles.directory(url)
        var config: [String: String] = [:], configPartial = false
        let configURL = url.appendingPathComponent("config.ini")
        do {
            config = try DRProperties.selected(try DRFiles.text(configURL, budget: budget), keys: [
                "avd.ini.displayname", "AvdId", "target", "abi.type", "hw.cpu.arch", "hw.device.name", "hw.device.manufacturer", "image.sysdir.1"
            ])
        } catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch { configPartial = true; budget.note(configURL, "AVD configuration is missing, malformed, changed or exceeds the bounded read size. Some device details are unknown.") }
        let measured = try DRFiles.measure(url, budget: budget, beforeFinalValidation: verificationProgress)
        let name = String(url.lastPathComponent.dropLast(4))
        let api = DRProperties.androidAPI(config["target"]) ?? DRProperties.androidAPI(config["image.sysdir.1"])
        let hardware = [config["hw.device.manufacturer"], config["hw.device.name"]].compactMap { $0 }.joined(separator: " ")
        return AndroidVirtualDeviceResource(url: url, name: name,
            displayName: config["avd.ini.displayname"] ?? config["AvdId"] ?? name,
            apiLevel: api, abi: config["abi.type"] ?? config["hw.cpu.arch"], device: hardware.isEmpty ? nil : hardware,
            allocatedBytes: measured.allocated, logicalBytes: measured.logical,
            isPartial: measured.partial || configPartial, lastUsedAt: nil,
            lastUseNote: "Last launch is not recorded reliably in the inspected standard files. Log, launch-record, snapshot and file dates below are evidence only; they do not establish last use or that this device is unnecessary.",
            evidence: measured.evidence,
            activity: try activity(for: url, avdName: name, measured: measured, snapshot: request.activity, budget: budget))
    }

    private func activity(for url: URL, avdName: String?, measured: DRMeasurement,
                          snapshot: DeveloperActivitySnapshot, budget: DRBudget) throws -> DeveloperResourceActivity {
        if budget.limited {
            return DeveloperResourceActivity(state: .unknown, processIDs: [],
                indicators: ["The scan limit prevented complete activity review. Running or idle status remains unknown."], sampledAt: snapshot.sampledAt)
        }
        var exact: [DeveloperResourceProcess] = [], named: [DeveloperResourceProcess] = [], related: [DeveloperResourceProcess] = []
        for process in snapshot.processes {
            try budget.check()
            if process.paths.contains(where: { $0.isFileURL && DRFiles.contains($0.roomLexicallyNormalized, in: url) }) { exact.append(process) }
            if avdName.map({ process.avdNames.contains($0) }) ?? false { named.append(process) }
            let name = process.name.lowercased()
            if avdName == nil ? name.contains("gradle") || name == "java" : name.contains("emulator") || name.contains("qemu") { related.append(process) }
        }
        var indicators = exact.map { "Observed file or working-directory use by \($0.name) (PID \($0.processID))." }
        if !named.isEmpty { indicators.append("A process sample names this AVD; this is not a verified live process-to-device identity.") }
        if measured.evidence.contains(where: { $0.kind == .lockPresent }) { indicators.append("Lock indicators are present. Locks may remain after an emulator or build exits.") }
        if exact.isEmpty && !related.isEmpty { indicators.append("A related emulator/build process was sampled; its resource ownership is not established.") }
        let state: DeveloperResourceActivityState
        if !exact.isEmpty { state = .observedUse }
        else if !indicators.isEmpty { state = .possibleUse }
        else if snapshot.isComplete { state = .notObserved; indicators.append("No use was observed in the supplied sample. This does not prove the resource is unused.") }
        else { state = .unknown; indicators.append("Complete process activity was not available. Running or idle status is unknown.") }
        return DeveloperResourceActivity(state: state, processIDs: Array(Set(exact.map(\.processID) + named.map(\.processID))).sorted(),
            indicators: indicators, sampledAt: snapshot.sampledAt)
    }
}

private final class DRBudget {
    let limits: DeveloperResourcesLimits
    let deadline: ContinuousClock.Instant
    var nodes = 0, resources = 0
    var limited = false
    var issues: [ScanIssue] = []
    init(_ limits: DeveloperResourcesLimits) {
        self.limits = limits; deadline = ContinuousClock.now.advanced(by: .seconds(limits.timeLimit))
    }
    func check() throws {
        try Task.checkCancellation()
        guard !limited, ContinuousClock.now < deadline else { limited = true; throw DRStop.limit }
    }
    func node() throws {
        try check(); nodes += 1
        guard nodes <= limits.maximumNodes else { limited = true; throw DRStop.limit }
    }
    func resource() throws {
        try check(); resources += 1
        guard resources <= limits.maximumResources else { limited = true; throw DRStop.limit }
    }
    func note(_ url: URL, _ message: String) {
        if issues.count < 128 { issues.append(ScanIssue(url: url, message: message)) }
    }
}
private enum DRStop: Error { case limit }
private enum DRReadError: Error { case invalidRoot, unreadable, malformed, oversize, changed }
private struct DRMeasurement { var allocated: Int64 = 0; var logical: Int64 = 0; var partial = false; var evidence: [DeveloperResourceEvidence] = [] }

private enum DRFiles {
    static func contains(_ child: URL, in parent: URL) -> Bool { child.path == parent.path || child.path.hasPrefix(parent.path + "/") }
    static func isDirectory(_ info: stat) -> Bool { info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    static func isRegular(_ info: stat) -> Bool { info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_size == b.st_size
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.pathComponents.count <= 128 else { throw DRReadError.invalidRoot }
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DRReadError.unreadable }
        for component in url.pathComponents where component != "/" {
            let next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw DRReadError.unreadable }; fd = next
        }
        return fd
    }
    @discardableResult static func directory(_ url: URL) throws -> stat {
        let fd = try openDirectory(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, isDirectory(info), info.st_uid == getuid() else { throw DRReadError.invalidRoot }
        return info
    }
    static func metadata(_ url: URL) throws -> stat {
        let fd = try openDirectory(url.deletingLastPathComponent()); defer { close(fd) }
        var info = stat()
        guard fstatat(fd, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_uid == getuid() else { throw DRReadError.unreadable }
        return info
    }
    static func children(_ url: URL, budget: DRBudget) throws -> [URL] {
        try budget.node()
        let fd = try openDirectory(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid() else { throw DRReadError.unreadable }
        // Reopen the exact directory for readdir; O_SEARCH itself is not readable.
        let readable = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard readable >= 0 else { throw DRReadError.unreadable }
        guard let stream = fdopendir(readable) else { close(readable); throw DRReadError.unreadable }
        defer { closedir(stream) }
        var result: [URL] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            try budget.node()
            result.append(url.appendingPathComponent(name, isDirectory: false))
            errno = 0
        }
        guard errno == 0 else { throw DRReadError.unreadable }
        var end = stat()
        guard fstat(fd, &end) == 0, same(info, end) else { throw DRReadError.changed }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func text(_ url: URL, budget: DRBudget) throws -> String {
        try budget.node()
        let parent = try openDirectory(url.deletingLastPathComponent()); defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw DRReadError.unreadable }; defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_uid == getuid(), isRegular(before), before.st_nlink == 1 else { throw DRReadError.unreadable }
        guard before.st_size >= 0, before.st_size <= budget.limits.maximumFileBytes else { throw DRReadError.oversize }
        var bytes: [UInt8] = [], chunk = [UInt8](repeating: 0, count: 8_192)
        while true {
            try budget.check()
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw DRReadError.unreadable }
            bytes.append(contentsOf: chunk.prefix(count))
            guard bytes.count <= budget.limits.maximumFileBytes else { throw DRReadError.oversize }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, same(before, after) else { throw DRReadError.changed }
        guard let text = String(bytes: bytes, encoding: .utf8), !text.contains("\0") else { throw DRReadError.malformed }
        return text
    }
    static func measure(_ url: URL, budget: DRBudget, beforeFinalValidation: () -> Void = {}) throws -> DRMeasurement {
        var result = DRMeasurement(), seen: Set<String> = []
        var latest: Date?
        let root = try directory(url)
        func walk(_ current: URL, depth: Int) throws {
            try budget.check()
            guard depth <= budget.limits.maximumDepth else { result.partial = true; budget.note(current, "The resource depth limit was reached."); return }
            let entries = try children(current, budget: budget)
            for child in entries {
                do {
                    let info = try metadata(child)
                    let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                    if latest == nil || date > latest! { latest = date }
                    let relative = String(child.path.dropFirst(url.path.count + 1))
                    if let evidence = evidence(child, relative: relative, info: info), result.evidence.count < 32 { result.evidence.append(evidence) }
                    if isDirectory(info) { try walk(child, depth: depth + 1) }
                    else if isRegular(info) {
                        let key = "\(info.st_dev):\(info.st_ino)"
                        if seen.insert(key).inserted { result.allocated += max(0, Int64(info.st_blocks)) * 512; result.logical += max(0, Int64(info.st_size)) }
                    } else { result.partial = true; budget.note(child, "A link or special item was skipped; its target was not inspected.") }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { result.partial = true; budget.note(child, "An item is inaccessible, changed or not owned by this user; size is a lower bound.") }
            }
        }
        do { try walk(url, depth: 0) }
        catch is CancellationError { throw CancellationError() }
        catch is DRStop { result.partial = true }
        catch { result.partial = true; budget.note(url, "Resource measurement was incomplete.") }
        beforeFinalValidation()
        let unchanged = (try? directory(url)).map { same(root, $0) } == true
        if !unchanged { result.partial = true; budget.note(url, "The resource changed or became unavailable while it was measured.") }
        if let latest {
            result.evidence.append(DeveloperResourceEvidence(kind: .filesystemChanged, label: "Latest measured file change", url: url, date: latest,
                uncertainty: "File modification is not a last-launch or last-build timestamp."))
        }
        return result
    }
    static func evidence(_ url: URL, relative: String, info: stat) -> DeveloperResourceEvidence? {
        let name = url.lastPathComponent.lowercased(), lower = relative.lowercased()
        let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        let kind: DeveloperResourceEvidenceKind, label: String, note: String
        if name.hasSuffix(".lock") || name.hasSuffix(".lck") {
            kind = .lockPresent; label = "Lock indicator present"; note = "A lock may be stale. Its presence does not prove a live process."
        } else if name == "emu-launch-params.txt" {
            kind = .launchRecordChanged; label = "Launch record modified"; note = "This is the file's modification date, not a verified emulator launch time."
        } else if ["emulator.log", "emulator-launch.log", "launch.log"].contains(name) {
            kind = .logChanged; label = "Available emulator log modified"; note = "Only file metadata was inspected; a log change does not establish last launch."
        } else if lower.hasPrefix("snapshots/") && ["snapshot.pb", "ram.img", "snapshot.lock"].contains(name) {
            kind = .snapshotChanged; label = "Snapshot file modified"; note = "Snapshots preserve device/app/user state. A saved-file date does not prove last use or safe removal."
        } else if name == "config.ini" {
            kind = .configurationChanged; label = "AVD configuration modified"; note = "Configuration edits are not emulator launch evidence."
        } else { return nil }
        return DeveloperResourceEvidence(kind: kind, label: label, url: url, date: date, uncertainty: note)
    }
}

private enum DRProjects {
    static let skipped: Set<String> = [".git", ".gradle", ".build", ".claude", ".codex", "node_modules", "build", "dist", "Pods", "vendor",
        "local.properties", "gradle.properties", ".env", ".env.local"]
    static func find(_ root: URL, budget: DRBudget, wrappers: inout [GradleProjectWrapper]) throws {
        func walk(_ url: URL, depth: Int) throws {
            try budget.check()
            guard depth <= budget.limits.maximumDepth else { budget.note(url, "Nested project search reached its depth limit."); return }
            for child in try DRFiles.children(url, budget: budget) {
                if skipped.contains(child.lastPathComponent) { continue }
                do {
                    let info = try DRFiles.metadata(child)
                    if DRFiles.isDirectory(info) { try walk(child, depth: depth + 1) }
                    else if DRFiles.isRegular(info), child.lastPathComponent == "gradle-wrapper.properties",
                            child.deletingLastPathComponent().lastPathComponent == "wrapper",
                            child.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "gradle" {
                        if wrappers.contains(where: { $0.propertiesURL.path == child.path }) { continue }
                        try budget.resource()
                        let project = child.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        do {
                            let properties = try DRProperties.selected(try DRFiles.text(child, budget: budget), keys: ["distributionUrl"])
                            let parsed = properties["distributionUrl"].flatMap(DRVersions.distributionURL)
                            wrappers.append(GradleProjectWrapper(projectURL: project, propertiesURL: child,
                                version: parsed?.version, distributionType: parsed?.type,
                                note: parsed == nil ? "The selected wrapper's version is unknown; its distribution URL is missing or nonstandard. No URL credentials are retained."
                                    : "Version inferred from this wrapper's distribution filename. The archive was not executed; this does not establish when the project last ran.", isPartial: parsed == nil))
                        } catch is CancellationError { throw CancellationError() }
                        catch is DRStop { throw DRStop.limit }
                        catch {
                            budget.note(child, "Wrapper metadata is malformed, changed, inaccessible or exceeds the bounded read size.")
                            wrappers.append(GradleProjectWrapper(projectURL: project, propertiesURL: child,
                                version: nil, distributionType: nil, note: "Wrapper version is unknown. No build scripts or credentials files were read.", isPartial: true))
                        }
                    } else if !DRFiles.isRegular(info) { budget.note(child, "A linked or special project item was skipped; its target was not inspected.") }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(child, "A project item is inaccessible or changed. No symbolic-link target was followed.") }
            }
        }
        try walk(root, depth: 0)
    }
}

private enum DRProperties {
    static func selected(_ text: String, keys: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("!") { continue }
            guard line.utf8.count <= 4_096 else { throw DRReadError.malformed }
            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key) else { continue }
            guard result[key] == nil else { throw DRReadError.malformed }
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            guard value.utf8.count <= (key == "distributionUrl" ? 2_048 : 256) else { throw DRReadError.oversize }
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw DRReadError.malformed }
            result[key] = value
        }
        return result
    }
    static func androidAPI(_ value: String?) -> String? {
        guard let value else { return nil }
        for component in value.split(separator: "/") where component.hasPrefix("android-") {
            let api = String(component.dropFirst(8))
            if !api.isEmpty, api.count <= 40, api.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }) { return api }
        }
        return nil
    }
}

enum DRVersions {
    static func version(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 96 else { return nil }
        let main = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = main[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(numbers.count), numbers.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) else { return nil }
        if main.count == 2 {
            guard !main[1].isEmpty, main[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-+".contains($0)) }) else { return nil }
        }
        return text
    }
    static func distribution(_ name: String) -> (version: String, type: String)? {
        let stem = name.hasSuffix(".zip") ? String(name.dropLast(4)) : name
        guard stem.hasPrefix("gradle-") else { return nil }
        for type in ["bin", "all"] where stem.hasSuffix("-" + type) {
            let value = String(stem.dropFirst(7).dropLast(type.count + 1))
            if let version = version(value) { return (version, type) }
        }
        return nil
    }
    static func distributionURL(_ raw: String) -> (version: String, type: String)? {
        // Read only the filename. Discard host, query, tokens, and userinfo.
        let value = raw.replacingOccurrences(of: "\\:", with: ":").replacingOccurrences(of: "\\/", with: "/")
        guard !value.hasSuffix("\\"), let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http", "file"].contains(scheme),
              let name = components.path.split(separator: "/").last.map(String.init), name.hasSuffix(".zip") else { return nil }
        return distribution(name.removingPercentEncoding ?? name)
    }
}
