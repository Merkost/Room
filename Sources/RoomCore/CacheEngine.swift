import Darwin
import Foundation

/// Serializes scan, Trash and restore work away from the UI actor.
/// Cleanup accepts only IDs minted by the latest completed scan.
public actor CacheEngine {
    private var resolvedConfiguration: CacheConfiguration?
    private let configurationProvider: (@Sendable () -> CacheConfiguration)?
    private var configuration: CacheConfiguration {
        if let resolvedConfiguration { return resolvedConfiguration }
        let value = configurationProvider?() ?? .standard
        resolvedConfiguration = value
        return value
    }
    private let activityDirectory: URL
    private let processProvider: @Sendable () throws -> [String]
    private let trashProvider: @Sendable (URL) throws -> URL
    private let fixtureTrashDirectory: URL?
    private let trashHomeDirectory: URL?
    private let protectedMeasurementNodeLimit: Int
    private let protectedMeasurementTimeLimit: TimeInterval
    private let candidatePartitionUnitLimit: Int
    private let npmContentLimits: NPMContentLimits
    private var candidates: [UUID: Candidate] = [:]
    private var activeScan: UUID?
    private var receipts: [ActivityReceipt] = []

    /// Returns only metadata already resolved by this engine. Disk inspection
    /// can reuse the same policy without probing a second catalogue of paths.
    public func resolvedInspectionConfiguration() -> CacheConfiguration? {
        resolvedConfiguration
    }

    public init(configuration: CacheConfiguration = .standard, activityDirectory: URL? = nil) {
        self.resolvedConfiguration = configuration
        self.configurationProvider = nil
        self.activityDirectory = activityDirectory ?? configuration.homeDirectory
            .appendingPathComponent("Library/Application Support/Room/Activity", isDirectory: true)
        self.processProvider = { try Self.liveProcessNames() }
        self.trashProvider = { try Self.systemTrash($0) }
        self.fixtureTrashDirectory = nil
        self.trashHomeDirectory = nil
        self.protectedMeasurementNodeLimit = 25_000
        self.protectedMeasurementTimeLimit = 1
        self.candidatePartitionUnitLimit = 20_000
        self.npmContentLimits = .standard
    }

    /// Dynamic metadata discovery runs lazily on this actor, never in the caller's initializer.
    public init(configurationProvider: @escaping @Sendable () -> CacheConfiguration, activityDirectory: URL? = nil,
                processProvider: (@Sendable () throws -> [String])? = nil, trashHomeDirectory: URL? = nil) {
        self.resolvedConfiguration = nil
        self.configurationProvider = configurationProvider
        self.activityDirectory = activityDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Room/Activity", isDirectory: true)
        self.processProvider = processProvider ?? { try Self.liveProcessNames() }
        self.trashProvider = { try Self.systemTrash($0) }
        self.fixtureTrashDirectory = nil
        self.trashHomeDirectory = trashHomeDirectory?.roomLexicallyNormalized
        self.protectedMeasurementNodeLimit = 25_000
        self.protectedMeasurementTimeLimit = 1
        self.candidatePartitionUnitLimit = 20_000
        self.npmContentLimits = .standard
    }

    // Tests may substitute only their own isolated Trash folder and process listing.
    init(configuration: CacheConfiguration, activityDirectory: URL,
         processProvider: @escaping @Sendable () throws -> [String],
         fixtureTrashDirectory: URL? = nil,
         protectedMeasurementNodeLimit: Int = 25_000,
         protectedMeasurementTimeLimit: TimeInterval = 1,
         candidatePartitionUnitLimit: Int = 20_000,
         trashProvider: (@Sendable (URL) throws -> URL)? = nil,
         npmContentLimits: NPMContentLimits = .standard) {
        self.resolvedConfiguration = configuration
        self.configurationProvider = nil
        self.activityDirectory = activityDirectory
        self.processProvider = processProvider
        self.trashProvider = trashProvider ?? { try Self.systemTrash($0) }
        self.fixtureTrashDirectory = fixtureTrashDirectory
        self.trashHomeDirectory = nil
        self.protectedMeasurementNodeLimit = max(1, protectedMeasurementNodeLimit)
        self.protectedMeasurementTimeLimit = max(0, protectedMeasurementTimeLimit)
        self.candidatePartitionUnitLimit = max(0, candidatePartitionUnitLimit)
        self.npmContentLimits = npmContentLimits
    }

    public func scan(progress: (@Sendable (CacheScanProgress) async -> Void)? = nil) async -> ScanReport {
        candidates.removeAll()
        let scanID = UUID()
        activeScan = scanID
        defer { if activeScan == scanID { activeScan = nil } }
        let now = Date()
        let volume: VolumeInfo
        if let approved = configuration.readAccessRoots {
            volume = approved.first.map { Self.volumeInfo(at: $0) } ?? VolumeInfo(totalBytes: 0, availableBytes: 0)
        } else { volume = Self.volumeInfo(at: configuration.homeDirectory) }
        var groups: [CacheGroup] = []
        var protectedData: [ProtectedData] = []
        var issues: [ScanIssue] = configuration.inspectionIssues
        var pendingCandidates: [UUID: Candidate] = [:]
        let contentBudget = NPMContentBudget(npmContentLimits)
        let processes: Result<[String], any Error> = configuration.roots.contains(where: { !$0.guardedProcesses.isEmpty })
            ? Result { try processProvider() } : .success([])
        var seenRootIDs: Set<String> = []
        let totalRoots = configuration.roots.count + configuration.protectedLocations.count
        var completedRoots = 0

        func report(incomplete: Bool) -> ScanReport {
            let visibleGroups = incomplete ? groups.map { group in
                CacheGroup(id: group.id, title: group.title, subtitle: group.subtitle, symbol: group.symbol,
                    category: group.category, rootURL: group.rootURL, consequence: group.consequence,
                    entries: group.entries.map { entry in
                        CacheEntry(id: entry.id, url: entry.url, name: entry.name, byteCount: entry.byteCount,
                            modifiedAt: entry.modifiedAt,
                            eligibility: .blocked("The scan has not completed. Scan again before cleanup."), fileCount: entry.fileCount)
                    }, issues: group.issues, isPartial: group.isPartial, isInspectionOnly: group.isInspectionOnly)
            } : groups
            return ScanReport(id: scanID, scannedAt: Date(), groups: visibleGroups, protectedData: protectedData,
                issues: issues, volume: volume, cancelled: incomplete)
        }


        for root in configuration.roots {
            if Task.isCancelled || activeScan != scanID { break }
            if let progress {
                let update = CacheScanProgress(completedRoots: completedRoots, totalRoots: totalRoots,
                    currentPath: root.url.path, partialReport: report(incomplete: true))
                await progress(update)
            }
            if Task.isCancelled || activeScan != scanID { break }
            completedRoots += 1
            guard seenRootIDs.insert(root.id).inserted else {
                issues.append(ScanIssue(url: root.url, message: "Duplicate cache identifier. This location was skipped."))
                continue
            }
            guard Self.existsWithoutFollowingLinks(root.url) else { continue }
            var groupIssues: [ScanIssue] = []
            var entries: [CacheEntry] = []
            var partial = false
            let inspectionOnly: Bool
            if case .inspectOnly = root.cleanupPolicy { inspectionOnly = true } else { inspectionOnly = false }
            let deadline = Date().addingTimeInterval(root.inspectionTimeLimit)
            let boundedMeasurement = inspectionOnly || root.contentValidation != nil
            let measurementDeadline = root.contentValidation == nil ? deadline : min(deadline, contentBudget.deadline)
            var remainingNodes = root.inspectionNodeLimit
            do {
                try Self.validateAncestors(root.url)
                let rootStat = try Self.metadata(root.url)
                let anchor = root.scope == .singleFile ? root.url.deletingLastPathComponent() : root.url
                let anchorMetadata = try Self.metadata(anchor)
                guard rootStat.owner == getuid(), anchorMetadata.owner == getuid() else {
                    throw EngineError.message("This cache location is owned by another user. It was skipped.")
                }
                let anchorIdentity = anchorMetadata.identity
                let children: [URL]
                switch root.scope {
                case .children:
                    guard rootStat.isDirectory else { throw EngineError.message("Expected a cache folder. This location was skipped.") }
                    let rootDescriptor = try Self.openDirectoryWithoutFollowingLinks(root.url)
                    defer { close(rootDescriptor) }
                    var opened = stat()
                    guard fstat(rootDescriptor, &opened) == 0, Self.metadata(opened).identity == rootStat.identity else {
                        throw EngineError.message("The cache folder changed while it was being scanned. Scan again.")
                    }
                    let listing = try Self.directoryNames(rootDescriptor,
                        maximumNames: boundedMeasurement ? min(10_000, root.inspectionNodeLimit) : nil,
                        deadline: root.contentValidation == nil ? nil : measurementDeadline)
                    partial = listing.limited
                    var finished = stat()
                    guard fstat(rootDescriptor, &finished) == 0, Self.metadata(finished).identity == rootStat.identity else {
                        throw EngineError.message("The cache folder changed while it was being scanned. Scan again.")
                    }
                    children = listing.names.filter { root.childNameRule?.matches($0) ?? true }.sorted()
                        .map { root.url.appendingPathComponent($0, isDirectory: false) }
                case .singleFile:
                    guard rootStat.isRegular else { throw EngineError.message("Expected a cache file. This location was skipped.") }
                    children = [root.url]
                }
                for child in children {
                    if Task.isCancelled || activeScan != scanID { partial = true; break }
                    if boundedMeasurement && (remainingNodes <= 0 || Date() >= measurementDeadline) { partial = true; break }
                    if inspectionOnly && (Self.isExcluded(child, exclusions: root.excludedURLs) ||
                        root.excludedChildNameRules.contains(where: { $0.matches(child.lastPathComponent) })) { continue }
                    do {
                        let budget = boundedMeasurement ? MeasurementBudget(maximumNodes: remainingNodes, deadline: measurementDeadline) : nil
                        let snapshot = try Self.snapshot(child, measurementBudget: budget,
                            partitionDepth: boundedMeasurement || isBlockedByOwner(root, processes: processes) ? 0 : root.candidateDepth - 1,
                            maximumPartitionUnits: candidatePartitionUnitLimit, excluding: inspectionOnly ? root.excludedURLs : [])
                        remainingNodes -= snapshot.visitedNodes
                        partial = partial || snapshot.measurementLimited
                        groupIssues.append(contentsOf: snapshot.issues.prefix(max(0, 100 - groupIssues.count)))
                        func append(_ url: URL, _ measured: TreeSnapshot, parentIdentity: FileIdentity) {
                            var eligibility = eligibility(for: root, url: url, snapshot: measured, now: now, processes: processes)
                            if eligibility.isEligible, root.contentValidation != nil {
                                do { try NPMContentPolicy.verify(source: url, originalURL: url, root: root,
                                    identity: measured.identity, budget: contentBudget) }
                                catch { eligibility = .blocked(error.localizedDescription) }
                                partial = partial || contentBudget.limited || Task.isCancelled
                            }
                            // Only known independent caches opt into splitting. A failed
                            // metadata walk never creates eligible descendant candidates.
                            if !inspectionOnly, !eligibility.isEligible, root.candidateDepth > 1,
                               measured.issues.isEmpty, !measured.measurementLimited, measured.partitionComplete,
                               !measured.children.isEmpty, !isBlockedByOwner(root, processes: processes) {
                                for unit in measured.children { append(unit.url, unit.snapshot, parentIdentity: measured.identity) }
                                return
                            }
                            let relative = root.scope == .singleFile ? url.lastPathComponent
                                : String(url.path.dropFirst(root.url.path.count + 1))
                            let entry = CacheEntry(id: UUID(), url: url.roomLexicallyNormalized,
                                name: relative, byteCount: measured.byteCount,
                                modifiedAt: measured.latestModification, eligibility: eligibility, fileCount: measured.fileCount)
                            entries.append(entry)
                            if eligibility.isEligible {
                                pendingCandidates[entry.id] = Candidate(entry: entry, root: root,
                                    anchorIdentity: anchorIdentity, parentIdentity: parentIdentity, snapshot: measured)
                            }
                        }
                        append(child, snapshot, parentIdentity: anchorIdentity)
                    } catch is CancellationError { partial = true; break }
                    catch { groupIssues.append(ScanIssue(url: child, message: error.localizedDescription)) }
                }
            } catch { groupIssues.append(ScanIssue(url: root.url, message: error.localizedDescription)) }
            partial = partial || !groupIssues.isEmpty
            let note = partial ? " Size check limited; displayed size is a lower bound. Inspect in Disk Map for a full folder scan." : ""
            groups.append(CacheGroup(id: root.id, title: root.title, subtitle: root.subtitle,
                symbol: root.symbol, category: root.category, rootURL: root.url,
                consequence: root.consequence + note, entries: entries.sorted { $0.byteCount > $1.byteCount },
                issues: groupIssues, isPartial: partial, isInspectionOnly: {
                    if case .inspectOnly = root.cleanupPolicy { return true }; return false
                }()))
            issues.append(contentsOf: groupIssues)
            if let progress {
                let update = CacheScanProgress(completedRoots: completedRoots, totalRoots: totalRoots,
                    currentPath: root.url.path, partialReport: report(incomplete: true))
                await progress(update)
            }
        }

        for location in configuration.protectedLocations {
            if Task.isCancelled || activeScan != scanID { break }
            if let progress {
                let update = CacheScanProgress(completedRoots: completedRoots, totalRoots: totalRoots,
                    currentPath: location.url.path, partialReport: report(incomplete: true))
                await progress(update)
            }
            completedRoots += 1
            guard !Self.isExcluded(location.url, exclusions: configuration.protectedMeasurementExclusions) else { continue }
            guard Self.existsWithoutFollowingLinks(location.url) else { continue }
            do {
                try Self.validateAncestors(location.url)
                let budget = MeasurementBudget(maximumNodes: protectedMeasurementNodeLimit,
                    deadline: Date().addingTimeInterval(protectedMeasurementTimeLimit))
                let measured = try Self.snapshot(location.url, measurementBudget: budget)
                let isPartial = measured.measurementLimited || !measured.issues.isEmpty
                let note = isPartial ? " Size check limited; displayed size is a lower bound. All contents remain protected." : ""
                protectedData.append(ProtectedData(id: location.id, title: location.title,
                    url: location.url, byteCount: measured.byteCount, reason: location.reason + note, isPartial: isPartial))
                issues.append(contentsOf: measured.issues)
            } catch is CancellationError { break }
            catch { issues.append(ScanIssue(url: location.url, message: error.localizedDescription)) }
        }
        if case .failure(let error) = processes, configuration.roots.contains(where: { !$0.guardedProcesses.isEmpty }) {
            issues.append(ScanIssue(url: URL(fileURLWithPath: "/bin/ps"),
                message: "Running tools could not be checked. Guarded caches stay unavailable. \(error.localizedDescription)"))
        }
        if !Task.isCancelled, activeScan == scanID, let progress {
            let update = CacheScanProgress(completedRoots: completedRoots, totalRoots: totalRoots,
                currentPath: "", partialReport: report(incomplete: true))
            await progress(update)
        }
        let cancelled = Task.isCancelled || activeScan != scanID
        if !cancelled { candidates = pendingCandidates }
        return report(incomplete: cancelled)
    }

    /// Native permission UI may approve these exact existing parent folders.
    /// Returning a location never moves data or grants access by itself.
    public func authorizationLocations(entryIDs: [UUID]) throws -> [URL] {
        guard !entryIDs.isEmpty else { throw EngineError.message("Select eligible cache items before reviewing access.") }
        var locations: [String: URL] = [:]
        let contentBudget = NPMContentBudget(npmContentLimits)
        for id in Set(entryIDs) {
            guard let candidate = candidates[id] else {
                throw EngineError.message("The selection belongs to an older or incomplete scan. Scan again.")
            }
            try validate(candidate, contentBudget: contentBudget)
            let parent = candidate.entry.url.deletingLastPathComponent()
            locations[parent.path] = parent
        }
        return locations.values.sorted { $0.path < $1.path }
    }

    /// Reconstruction uses the current approved catalogue, not arbitrary paths
    /// supplied by a receipt. Native approval is still required before Restore.
    public func restoreAuthorizationLocations(receiptID: UUID) throws -> [URL] {
        guard let receipt = history().first(where: { $0.id == receiptID }) else {
            throw EngineError.message("The recovery receipt could not be found.")
        }
        var locations: [String: URL] = [:]
        for item in receipt.items where item.status == .trashed {
            guard let root = configuration.roots.first(where: { $0.id == item.rootID }),
                  case .allowed = root.cleanupPolicy else {
                throw EngineError.message("Approve the original cache folder before reviewing recovery access.")
            }
            try Self.validateCandidatePath(item.originalURL, root: root)
            let parent = item.originalURL.deletingLastPathComponent()
            locations[parent.path] = parent
        }
        guard !locations.isEmpty else { throw EngineError.message("This receipt has no cache items available to restore.") }
        return locations.values.sorted { $0.path < $1.path }
    }

    /// Only exact moved items are returned. App UI may ask the user to select
    /// these individual files/folders when their saved Store scope is unusable.
    public func restoreTrashAuthorizationLocations(receiptID: UUID) throws -> [URL] {
        #if ROOM_APP_STORE
        guard let receipt = history().first(where: { $0.id == receiptID }) else {
            throw EngineError.message("The recovery receipt could not be found.")
        }
        var locations: [String: URL] = [:]
        for item in receipt.items where item.status == .trashed {
            guard let url = item.trashURL else { continue }
            // Permission preflight must not stat an original parent whose
            // approval has been removed. Validate only the receipt's exact
            // known Trash path here; full volume/identity checks happen after
            // the native grants are active in restore().
            let knownTrash = fixtureTrashDirectory ?? (trashHomeDirectory ?? FileManager.default.homeDirectoryForCurrentUser)
                .appendingPathComponent(".Trash", isDirectory: true)
            guard url.isFileURL, url.roomLexicallyNormalized.deletingLastPathComponent().path == knownTrash.roomLexicallyNormalized.path else {
                throw EngineError.message("This receipt's Trash location needs manual recovery through Finder.")
            }
            do {
                let scope = try restoreTrashAccess(item, approvedTrashItems: [])
                defer { if scope.scoped { scope.url.stopAccessingSecurityScopedResource() } }
                guard let reference = item.trashIdentity,
                      Self.sameRecoveryRoot(try Self.metadata(url).identity, reference) else {
                    locations[url.path] = url; continue
                }
            } catch { locations[url.path] = url }
        }
        return locations.values.sorted { $0.path < $1.path }
        #else
        return []
        #endif
    }

    public func clean(entryIDs: Set<UUID>) async -> ActivityReceipt {
        var receipt = ActivityReceipt(id: UUID(), date: Date(), items: [], issues: [])
        let contentBudget = NPMContentBudget(npmContentLimits)
        for id in entryIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let candidate = candidates[id] else {
                receipt.issues.append(ScanIssue(url: configuration.homeDirectory,
                    message: "An item is no longer eligible or belongs to an older scan. Scan again before cleanup."))
                continue
            }
            receipt.items.append(ActivityItem(id: candidate.entry.id, rootID: candidate.root.id,
                originalURL: candidate.entry.url, trashURL: nil, byteCount: candidate.entry.byteCount,
                originalIdentity: candidate.snapshot.identity, rootIdentity: candidate.anchorIdentity,
                trashIdentity: nil, trashFingerprint: nil, status: .pending, message: nil,
                originalParentIdentity: candidate.parentIdentity))
        }
        guard !receipt.items.isEmpty else { return receipt }
        do { try persist(receipt) }
        catch {
            receipt.issues.append(ScanIssue(url: activityDirectory,
                message: "Nothing moved: the recovery receipt could not be saved. \(error.localizedDescription)"))
            for index in receipt.items.indices { receipt.items[index].status = .failed }
            return receipt
        }

        for index in receipt.items.indices {
            if Task.isCancelled {
                receipt.items[index].status = .failed
                receipt.items[index].message = "Cleanup cancelled before this item moved."
                continue
            }
            let id = receipt.items[index].id
            guard let candidate = candidates[id] else { continue }
            do {
                try validate(candidate, contentBudget: contentBudget, verifyContent: false)
                // Re-check live tools after walking the tree, immediately before the move.
                try requireInactive(candidate.root)
                try Self.validateAncestors(candidate.entry.url)
                guard try Self.metadata(candidate.entry.url).identity == candidate.snapshot.identity,
                      Self.sameObject(try Self.metadata(candidate.entry.url.deletingLastPathComponent()).identity, candidate.parentIdentity) else {
                    throw EngineError.message("The item changed after scanning. Scan again.")
                }
                if candidate.root.contentValidation != nil {
                    try NPMContentPolicy.verify(source: candidate.entry.url, originalURL: candidate.entry.url,
                        root: candidate.root, identity: candidate.snapshot.identity, budget: contentBudget)
                    guard try Self.metadata(candidate.entry.url).identity == candidate.snapshot.identity,
                          Self.sameObject(try Self.metadata(candidate.entry.url.deletingLastPathComponent()).identity, candidate.parentIdentity) else {
                        throw EngineError.message("The npm object or its parent changed after verification. Nothing moved.")
                    }
                }
                let returnedTrashURL = try trashProvider(candidate.entry.url)
                let trashURL = returnedTrashURL.roomLexicallyNormalized
                #if ROOM_APP_STORE
                let movedScope = returnedTrashURL.startAccessingSecurityScopedResource()
                defer { if movedScope { returnedTrashURL.stopAccessingSecurityScopedResource() } }
                #endif
                receipt.items[index].trashURL = trashURL
                receipt.items[index].status = .trashed
                receipt.items[index].message = "In Trash. If recovery recording is interrupted, restore this item from Finder’s Trash."
                candidates.removeValue(forKey: id)
                // Commit the returned location before any potentially long verification walk.
                try persist(receipt)
                // Once moved, always finish the receipt even when cancellation arrives.
                try validateTrashLocation(trashURL, originalURL: candidate.entry.url)
                #if ROOM_APP_STORE
                receipt.items[index].trashAccessBookmark = try returnedTrashURL.bookmarkData(options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil, relativeTo: nil)
                #endif
                try Self.validateAncestors(trashURL)
                let trashed = try Self.snapshot(trashURL, checkCancellation: false, exactTrashItem: true)
                guard trashed.issues.isEmpty, !trashed.hasSymbolicLink, !trashed.hasUnsupportedType else {
                    throw EngineError.message("In Trash. Automatic recovery information is incomplete; restore this item from Finder’s Trash.")
                }
                receipt.items[index].trashIdentity = trashed.identity
                receipt.items[index].trashFingerprint = trashed.fingerprint
                receipt.items[index].message = nil
            } catch {
                if case EngineError.movedWithoutURL = error {
                    receipt.items[index].status = .trashed
                    candidates.removeValue(forKey: id)
                } else if receipt.items[index].trashURL == nil { receipt.items[index].status = .failed }
                receipt.items[index].message = error.localizedDescription
                receipt.issues.append(ScanIssue(url: candidate.entry.url, message: error.localizedDescription))
            }
            do { try persist(receipt) }
            catch {
                receipt.issues.append(ScanIssue(url: activityDirectory,
                    message: "The latest activity receipt could not be saved. Moved items remain in Trash. \(error.localizedDescription)"))
                // Stop further moves if a durable recovery record is unavailable.
                for later in receipt.items.indices where later > index && receipt.items[later].status == .pending {
                    receipt.items[later].status = .failed
                    receipt.items[later].message = "Stopped because the recovery receipt could not be saved."
                }
                break
            }
        }
        upsert(receipt)
        try? persist(receipt)
        return receipt
    }

    public func history() -> [ActivityReceipt] {
        var byID = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        if (try? Self.validateAncestors(activityDirectory)) != nil,
           let files = try? FileManager.default.contentsOfDirectory(at: activityDirectory,
            includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                guard let metadata = try? Self.metadata(file), metadata.isRegular,
                      metadata.owner == getuid(), metadata.identity.byteCount < 8_000_000,
                      let data = try? Data(contentsOf: file),
                      var receipt = try? JSONDecoder().decode(ActivityReceipt.self, from: data),
                      file.lastPathComponent == "\(receipt.id.uuidString).json" else { continue }
                for index in receipt.items.indices where receipt.items[index].status == .pending {
                    receipt.items[index].status = .failed
                    receipt.items[index].message = "An earlier cleanup was interrupted. Check the original location and Finder’s Trash before trying again."
                }
                if byID[receipt.id] == nil { byID[receipt.id] = receipt }
            }
        }
        receipts = byID.values.sorted { $0.date > $1.date }
        return receipts
    }

    public func restore(receiptID: UUID, approvedTrashItems: [URL] = []) async -> RestoreReport {
        let stored = history()
        guard var receipt = stored.first(where: { $0.id == receiptID }) else {
            let issue = ScanIssue(url: activityDirectory, message: "The activity receipt could not be found.")
            return RestoreReport(receipt: ActivityReceipt(id: receiptID, date: Date(), items: [], issues: [issue]),
                restoredCount: 0, issues: [issue])
        }
        var issues: [ScanIssue] = []
        var restoredCount = 0
        let contentBudget = NPMContentBudget(npmContentLimits)
        for index in receipt.items.indices where receipt.items[index].status == .trashed {
            if Task.isCancelled { break }
            let item = receipt.items[index]
            do {
                #if ROOM_APP_STORE
                let trashScope = try restoreTrashAccess(item, approvedTrashItems: approvedTrashItems)
                defer { if trashScope.scoped { trashScope.url.stopAccessingSecurityScopedResource() } }
                #endif
                guard let root = configuration.roots.first(where: { $0.id == item.rootID }) else {
                    throw EngineError.message("This receipt refers to a location outside the cache catalogue.")
                }
                try Self.validateCandidatePath(item.originalURL, root: root)
                let anchor = root.scope == .singleFile ? root.url.deletingLastPathComponent() : root.url
                try Self.validateAncestors(anchor)
                let anchorMetadata = try Self.metadata(anchor)
                guard anchorMetadata.owner == getuid(), Self.sameObject(anchorMetadata.identity, item.rootIdentity) else {
                    throw EngineError.message("The original cache folder was replaced. Restore this item manually from Trash.")
                }
                try validateRestoreParent(item)
                guard !Self.existsWithoutFollowingLinks(item.originalURL) else {
                    throw EngineError.message("A newer item already exists at the original location. It was kept; the previous item remains in Trash.")
                }
                guard let trashURL = item.trashURL, let identity = item.trashIdentity,
                      let fingerprint = item.trashFingerprint else {
                    throw EngineError.message("This item is in Trash, but automatic recovery information is incomplete. Restore it from Finder’s Trash.")
                }
                try validateTrashLocation(trashURL, originalURL: item.originalURL)
                try Self.validateAncestors(trashURL)
                let current = try Self.snapshot(trashURL, exactTrashItem: true, recordedTrashRootIdentity: identity)
                guard Self.sameRecoveryRoot(current.identity, identity), current.fingerprint == fingerprint,
                      current.issues.isEmpty, !current.measurementLimited, !current.hasSymbolicLink,
                      !current.hasForeignOwner, !current.hasMultipleLinks, !current.hasUnsupportedType,
                      Self.sameObject(identity, item.originalIdentity) else {
                    throw EngineError.message("The item in Trash changed or is unavailable. Restore it manually in Finder.")
                }
                try requireInactive(root)
                if root.contentValidation != nil {
                    try NPMContentPolicy.verify(source: trashURL, originalURL: item.originalURL,
                        root: root, identity: current.identity, budget: contentBudget, exactTrashItem: true)
                }
                // Revalidate every parent component immediately before the move.
                try validateRestoreParent(item)
                try Self.validateAncestors(trashURL)
                guard try Self.metadata(trashURL).identity == current.identity else {
                    throw EngineError.message("The item in Trash changed during recovery. Nothing moved.")
                }
                // moveItem fails if a new destination appears; it never overwrites it.
                try FileManager.default.moveItem(at: trashURL, to: item.originalURL)
                receipt.items[index].status = .restored
                receipt.items[index].message = nil
                restoredCount += 1
                try persist(receipt)
            } catch {
                receipt.items[index].message = error.localizedDescription
                issues.append(ScanIssue(url: item.originalURL, message: error.localizedDescription))
            }
        }
        receipt.issues.append(contentsOf: issues)
        upsert(receipt)
        do { try persist(receipt) }
        catch { issues.append(ScanIssue(url: activityDirectory, message: "The restore receipt could not be saved. \(error.localizedDescription)")) }
        return RestoreReport(receipt: receipt, restoredCount: restoredCount, issues: issues)
    }

    private func validateRestoreParent(_ item: ActivityItem) throws {
        let parent = item.originalURL.deletingLastPathComponent()
        try Self.validateAncestors(parent)
        if let identity = item.originalParentIdentity {
            let current = try Self.metadata(parent)
            guard current.owner == getuid(), Self.sameObject(current.identity, identity) else {
                throw EngineError.message("The original parent folder was replaced. Restore this item manually from Trash.")
            }
        }
    }

    private func eligibility(for root: CacheRoot, url: URL, snapshot: TreeSnapshot, now: Date,
                             processes: Result<[String], any Error>) -> Eligibility {
        if case .inspectOnly(let reason) = root.cleanupPolicy { return .blocked(reason) }
        if intersectsProtected(url) { return .blocked("Contains protected user work or installed resources. Inspect only.") }
        if root.contentValidation != nil,
           (snapshot.identity.mode & UInt16(S_IFMT) != UInt16(S_IFREG) ||
            NPMContentPolicy.expectedDigest(originalURL: url, root: root) == nil) {
            return .blocked("Only individual completed npm SHA512 objects match this cleanup rule. This item stays in place.")
        }
        if root.childNameRule != nil, snapshot.identity.mode & UInt16(S_IFMT) != UInt16(S_IFDIR) {
            return .blocked("Only generated cache folders match this cleanup rule. Inspect this file manually.")
        }
        if snapshot.measurementLimited { return .blocked("The size check is incomplete. Nothing in this item will move.") }
        if !snapshot.issues.isEmpty { return .blocked("Some files could not be read. Nothing in this item will move.") }
        if snapshot.hasSymbolicLink { return .blocked("Contains a symbolic link. Review this item in Finder.") }
        if snapshot.hasForeignOwner { return .blocked("Contains files owned by another user. Review this item in Finder.") }
        if snapshot.hasMultipleLinks { return .blocked("Contains shared hard links. Reclaimed space cannot be guaranteed; review in Finder.") }
        if snapshot.hasUnsupportedType { return .blocked("Contains a special filesystem item. Review this item in Finder.") }
        let minimumAge = root.contentValidation == nil ? root.minimumAge : max(root.minimumAge, NPMContentPolicy.minimumAge)
        if now.timeIntervalSince(snapshot.latestModification) < minimumAge {
            let days = max(1, Int(minimumAge / 86_400))
            if root.contentValidation != nil { return .blocked("Modified within the last \(days) days. This npm object stays in place.") }
            return .blocked("Used within the last \(days) days. Kept until every file is older.")
        }
        if !root.guardedProcesses.isEmpty {
            switch processes {
            case .failure:
                #if ROOM_APP_STORE
                return .blocked("Background-tool activity is unavailable in the App Store sandbox. This cache stays held; review it with its owning app.")
                #else
                return .blocked("Running tools could not be checked. Try scanning again.")
                #endif
            case .success(let names):
                if let process = Self.activeProcess(for: root, in: names) {
                    return .blocked("\(process) is running. Quit it and scan again.")
                }
            }
        }
        return .eligible
    }

    private func intersectsProtected(_ url: URL) -> Bool {
        configuration.protectedLocations.contains { location in
            url.path == location.url.path || url.path.hasPrefix(location.url.path + "/") || location.url.path.hasPrefix(url.path + "/")
        }
    }
    private func isBlockedByOwner(_ root: CacheRoot, processes: Result<[String], any Error>) -> Bool {
        guard !root.guardedProcesses.isEmpty else { return false }
        switch processes {
        case .failure: return true
        case .success(let names): return Self.activeProcess(for: root, in: names) != nil
        }
    }

    private func validate(_ candidate: Candidate, contentBudget: NPMContentBudget? = nil, verifyContent: Bool = true) throws {
        if case .inspectOnly = candidate.root.cleanupPolicy { throw EngineError.message("This discovered location is inspect-only. Nothing moved.") }
        guard !intersectsProtected(candidate.entry.url) else { throw EngineError.message("Protected user work intersects this item. Nothing moved.") }
        try Self.validateCandidatePath(candidate.entry.url, root: candidate.root)
        try Self.validateAncestors(candidate.entry.url)
        let anchor = candidate.root.scope == .singleFile ? candidate.root.url.deletingLastPathComponent() : candidate.root.url
        let anchorMetadata = try Self.metadata(anchor)
        guard anchorMetadata.owner == getuid(), Self.sameObject(anchorMetadata.identity, candidate.anchorIdentity) else {
            throw EngineError.message("The cache folder was replaced after scanning. Scan again.")
        }
        let parent = try Self.metadata(candidate.entry.url.deletingLastPathComponent())
        guard parent.owner == getuid(), Self.sameObject(parent.identity, candidate.parentIdentity) else {
            throw EngineError.message("The cache item's parent folder was replaced. Nothing moved.")
        }
        let current = try Self.snapshot(candidate.entry.url)
        if candidate.root.childNameRule != nil, current.identity.mode & UInt16(S_IFMT) != UInt16(S_IFDIR) {
            throw EngineError.message("This generated cache is no longer a folder. Nothing moved.")
        }
        guard current.identity == candidate.snapshot.identity,
              current.fingerprint == candidate.snapshot.fingerprint,
              current.issues.isEmpty, !current.hasSymbolicLink, !current.hasForeignOwner,
              !current.hasUnsupportedType, !current.hasMultipleLinks else {
            throw EngineError.message("The item or its contents changed after scanning. Scan again.")
        }
        let minimumAge = candidate.root.contentValidation == nil ? candidate.root.minimumAge : max(candidate.root.minimumAge, NPMContentPolicy.minimumAge)
        guard Date().timeIntervalSince(current.latestModification) >= minimumAge else {
            throw EngineError.message("The item was recently modified. It will stay in place.")
        }
        try requireInactive(candidate.root)
        if verifyContent, candidate.root.contentValidation != nil {
            try NPMContentPolicy.verify(source: candidate.entry.url, originalURL: candidate.entry.url,
                root: candidate.root, identity: candidate.snapshot.identity,
                budget: contentBudget ?? NPMContentBudget(npmContentLimits))
        }
    }

    private func requireInactive(_ root: CacheRoot) throws {
        guard !root.guardedProcesses.isEmpty else { return }
        let names: [String]
        do { names = try processProvider() }
        catch {
            #if ROOM_APP_STORE
            throw EngineError.message("Background-tool activity is unavailable in the App Store sandbox. This cache stays held; review it with its owning app.")
            #else
            throw EngineError.message("Running tools could not be checked. Nothing moved.")
            #endif
        }
        if let name = Self.activeProcess(for: root, in: names) {
            throw EngineError.message("\(name) started running. Quit it and scan again.")
        }
    }

    private static func activeProcess(for root: CacheRoot, in names: [String]) -> String? {
        let containedPrefix = root.url.path == "/" ? "/" : root.url.path + "/"
        if names.contains(where: { $0.hasPrefix("/") && $0.hasPrefix(containedPrefix) }) {
            return "A cached tool"
        }
        for guardName in root.guardedProcesses {
            if names.contains(where: { name in
                let lower = name.lowercased()
                let base = URL(fileURLWithPath: lower).lastPathComponent
                let suffix = base.hasPrefix(guardName) ? base.dropFirst(guardName.count) : ""[...]
                let versionedExecutable = suffix.first?.isNumber == true && suffix.allSatisfy { $0.isNumber || $0 == "." }
                return base == guardName || base.hasPrefix(guardName + "-") ||
                    base.hasPrefix(guardName + " ") || versionedExecutable ||
                    lower.contains("/\(guardName).app/") || lower.contains("/\(guardName)/") ||
                    (guardName == "studio" && lower.contains("android studio.app"))
            }) { return guardName.prefix(1).uppercased() + guardName.dropFirst() }
        }
        return nil
    }

    private func validateTrashLocation(_ url: URL, originalURL: URL) throws {
        let directory: URL
        if let fixtureTrashDirectory { directory = fixtureTrashDirectory }
        else {
            // The original item no longer exists after the move. Ask using its
            // existing parent; some macOS Foundation versions still report this
            // search-directory API as unsupported.
            let sourceDirectory = originalURL.deletingLastPathComponent()
            if let discovered = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                appropriateFor: sourceDirectory, create: false) {
                directory = discovered
            } else {
                let actualHome = trashHomeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
                guard try Self.metadata(sourceDirectory).identity.device == Self.metadata(actualHome).identity.device else {
                    throw EngineError.message("The Trash location on this volume could not be verified. Restore this item from Finder’s Trash.")
                }
                // Same-volume user Trash is a fixed macOS location. Never guess
                // an external volume's .Trashes path or enumerate its contents.
                directory = actualHome.appendingPathComponent(".Trash", isDirectory: true)
            }
        }
        guard url.isFileURL,
              url.roomLexicallyNormalized.deletingLastPathComponent().path == directory.roomLexicallyNormalized.path else {
            throw EngineError.message("The receipt contains an invalid Trash location. Nothing restored.")
        }
    }

    #if ROOM_APP_STORE
    private func restoreTrashAccess(_ item: ActivityItem, approvedTrashItems: [URL]) throws -> (url: URL, scoped: Bool) {
        guard let expected = item.trashURL else {
            throw EngineError.message("The exact Trash item was not recorded. Restore it through Finder's Trash.")
        }
        if let approved = approvedTrashItems.first(where: {
            $0.isFileURL && $0.roomLexicallyNormalized.path == expected.roomLexicallyNormalized.path
        }) {
            return (approved, approved.startAccessingSecurityScopedResource())
        }
        guard let bookmark = item.trashAccessBookmark else {
            throw EngineError.message("Access to this exact Trash item was not saved. Restore it through Finder's Trash.")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.roomLexicallyNormalized.path == expected.roomLexicallyNormalized.path else {
            throw EngineError.message("The saved Trash item access changed. Restore this item through Finder's Trash.")
        }
        return (url, url.startAccessingSecurityScopedResource())
    }
    #endif

    private func persist(_ receipt: ActivityReceipt) throws {
        try Self.validateAncestors(activityDirectory, allowMissing: true)
        try FileManager.default.createDirectory(at: activityDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try Self.validateAncestors(activityDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = activityDirectory.appendingPathComponent("\(receipt.id.uuidString).json")
        if Self.existsWithoutFollowingLinks(url) {
            let value = try Self.metadata(url)
            guard value.isRegular, value.owner == getuid() else { throw EngineError.message("The activity receipt is not a regular owned file.") }
        }
        try encoder.encode(receipt).write(to: url, options: [.atomic])
        _ = chmod(url.path, 0o600)
        upsert(receipt)
    }

    private func upsert(_ receipt: ActivityReceipt) {
        receipts.removeAll { $0.id == receipt.id }
        receipts.append(receipt)
        receipts.sort { $0.date > $1.date }
    }
}

private struct Candidate: Sendable {
    let entry: CacheEntry
    let root: CacheRoot
    let anchorIdentity: FileIdentity
    let parentIdentity: FileIdentity
    let snapshot: TreeSnapshot
}

private struct TreeSnapshot: Sendable {
    let identity: FileIdentity
    let fingerprint: String
    let latestModification: Date
    let byteCount: Int64
    let fileCount: Int
    let hasSymbolicLink: Bool
    let hasForeignOwner: Bool
    let hasMultipleLinks: Bool
    let hasUnsupportedType: Bool
    let issues: [ScanIssue]
    let measurementLimited: Bool
    let visitedNodes: Int
    let children: [SnapshotUnit]
    let partitionComplete: Bool
}

private struct SnapshotUnit: Sendable { let url: URL; let snapshot: TreeSnapshot }

/// Thread-confined metadata summaries let nested known cache units share one
/// descriptor walk. Each fingerprint uses the same relative-path format as a
/// standalone snapshot, preserving receipt verification and cleanup revalidation.
private final class SnapshotAccumulator {
    let url: URL
    let initial: Metadata
    var digest = Fingerprint()
    var latest: Date
    var bytes: Int64 = 0
    var files = 0
    var symlink = false
    var foreignOwner = false
    var multipleLinks = false
    var unsupported = false
    var issues: [ScanIssue] = []
    var measurementLimited = false
    var nodes = 0
    var children: [SnapshotUnit] = []
    var partitionComplete = true
    init(url: URL, initial: Metadata) { self.url = url; self.initial = initial; self.latest = initial.modifiedAt }
    func append(_ current: URL, metadata value: Metadata, countAllocation: Bool, fingerprintIdentity: FileIdentity? = nil) {
        nodes += 1
        digest.append(current.path == url.path ? "." : String(current.path.dropFirst(url.path.count + 1)))
        digest.append(current.path == url.path ? (fingerprintIdentity ?? value.identity) : value.identity)
        latest = max(latest, value.modifiedAt)
        foreignOwner = foreignOwner || value.owner != getuid()
        symlink = symlink || value.isSymbolicLink
        if value.isRegular {
            files += 1
            multipleLinks = multipleLinks || value.linkCount > 1
            if countAllocation { bytes += max(0, value.allocatedBytes) }
        } else if !value.isDirectory && !value.isSymbolicLink { unsupported = true }
    }
    func snapshot() -> TreeSnapshot {
        TreeSnapshot(identity: initial.identity, fingerprint: digest.value, latestModification: latest,
            byteCount: bytes, fileCount: files, hasSymbolicLink: symlink, hasForeignOwner: foreignOwner,
            hasMultipleLinks: multipleLinks, hasUnsupportedType: unsupported, issues: issues,
            measurementLimited: measurementLimited, visitedNodes: nodes, children: children, partitionComplete: partitionComplete)
    }
}

private struct MeasurementBudget {
    let maximumNodes: Int
    let deadline: Date
}

private struct MeasurementLimitReached: Error {}

private struct DirectoryListing {
    let names: [String]
    let limited: Bool
}

private struct Metadata {
    let identity: FileIdentity
    let owner: uid_t
    let allocatedBytes: Int64
    let linkCount: UInt16
    var type: UInt16 { identity.mode & UInt16(S_IFMT) }
    var isDirectory: Bool { type == UInt16(S_IFDIR) }
    var isRegular: Bool { type == UInt16(S_IFREG) }
    var isSymbolicLink: Bool { type == UInt16(S_IFLNK) }
    var modifiedAt: Date { Date(timeIntervalSince1970: Double(identity.modifiedSeconds) + Double(identity.modifiedNanoseconds) / 1_000_000_000) }
}

private enum EngineError: LocalizedError {
    case message(String)
    case movedWithoutURL
    var errorDescription: String? {
        switch self {
        case .message(let value): value
        case .movedWithoutURL: "macOS moved this item to Trash without returning its location. Restore it from Finder’s Trash."
        }
    }
}

extension CacheEngine {
    private static func metadata(_ url: URL) throws -> Metadata {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw EngineError.message("Could not inspect \(url.lastPathComponent): \(String(cString: strerror(errno))).")
        }
        return metadata(info)
    }

    private static func metadata(_ info: stat) -> Metadata {
        return Metadata(identity: FileIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)),
            inode: UInt64(info.st_ino), modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec), changedSeconds: Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(info.st_ctimespec.tv_nsec), byteCount: Int64(info.st_size), mode: info.st_mode),
            owner: info.st_uid, allocatedBytes: Int64(info.st_blocks) * 512, linkCount: info.st_nlink)
    }

    private static func existsWithoutFollowingLinks(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func sameObject(_ first: FileIdentity, _ second: FileIdentity) -> Bool {
        first.device == second.device && first.inode == second.inode && first.mode == second.mode
    }

    /// A moved Trash root can receive delayed Finder metadata. Only its ctime
    /// is permitted to drift from the receipt; every other root identity field
    /// and all descendant metadata remain strict. This is a metadata freshness
    /// check, not content authentication: a same-size rewrite with deliberately
    /// preserved mtime cannot be ruled out without reading file contents.
    private static func sameRecoveryRoot(_ lhs: FileIdentity, _ rhs: FileIdentity) -> Bool {
        lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.mode == rhs.mode &&
            lhs.byteCount == rhs.byteCount && lhs.modifiedSeconds == rhs.modifiedSeconds &&
            lhs.modifiedNanoseconds == rhs.modifiedNanoseconds
    }

    private static func validateAncestors(_ url: URL, allowMissing: Bool = false) throws {
        guard url.isFileURL, url.path == url.roomLexicallyNormalized.path else {
            throw EngineError.message("The filesystem path is not canonical.")
        }
        var cursor = url.roomLexicallyNormalized
        while cursor.path != "/" {
            do {
                let value = try metadata(cursor)
                guard !value.isSymbolicLink else {
                    throw EngineError.message("A symbolic link appears in this path. The location was skipped.")
                }
            } catch {
                if !allowMissing || existsWithoutFollowingLinks(cursor) { throw error }
            }
            cursor.deleteLastPathComponent()
        }
    }

    private static func validateCandidatePath(_ url: URL, root: CacheRoot) throws {
        guard root.allowsKnownLocation(url) else { throw EngineError.message("This location is outside the cleanup policy. Nothing moved.") }
        guard url.isFileURL, url.path == url.roomLexicallyNormalized.path else {
            throw EngineError.message("The item path is invalid.")
        }
        switch root.scope {
        case .children:
            let prefix = root.url.path + "/"
            let relative = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : ""
            guard !relative.isEmpty, relative.split(separator: "/").count <= root.candidateDepth else {
                throw EngineError.message("The item is outside its allowlisted cache folder.")
            }
        case .singleFile:
            guard url.path == root.url.path else { throw EngineError.message("The item is outside its allowlisted cache file.") }
        }
    }

    private static func isExcluded(_ url: URL, exclusions: [URL]) -> Bool {
        exclusions.contains { url.path == $0.path || url.path.hasPrefix($0.path + "/") }
    }

    private static func snapshot(_ url: URL, checkCancellation: Bool = true,
                                 exactTrashItem: Bool = false, recordedTrashRootIdentity: FileIdentity? = nil,
                                 measurementBudget: MeasurementBudget? = nil,
                                 partitionDepth: Int = 0, maximumPartitionUnits: Int = 20_000, excluding: [URL] = []) throws -> TreeSnapshot {
        if checkCancellation { try Task.checkCancellation() }
        // Exact Trash items are separately contained and ancestry-validated.
        let parentFD: Int32? = exactTrashItem ? nil : try openDirectoryWithoutFollowingLinks(url.deletingLastPathComponent())
        defer { if let parentFD { close(parentFD) } }
        let initial: Metadata
        if let parentFD { initial = try metadata(at: parentFD, name: url.lastPathComponent) }
        else { initial = try metadata(url) }
        if let recordedTrashRootIdentity {
            guard exactTrashItem, sameRecoveryRoot(initial.identity, recordedTrashRootIdentity) else {
                throw EngineError.message("The item in Trash changed or is unavailable. Restore it manually in Finder.")
            }
        }
        let root = SnapshotAccumulator(url: url, initial: initial)
        var countedFiles: Set<String> = []
        var visitedNodes = 0
        var retainedUnits = 0
        func issue(_ current: URL, _ error: any Error, active: [SnapshotAccumulator]) {
            for accumulator in active where accumulator.issues.count < 100 {
                accumulator.issues.append(ScanIssue(url: current, message: error.localizedDescription))
            }
        }
        func visit(_ current: URL, parentFD: Int32?, name: String, depth: Int,
                   active parents: [SnapshotAccumulator]) throws -> SnapshotUnit? {
            if checkCancellation { try Task.checkCancellation() }
            if isExcluded(current, exclusions: excluding) { return nil }
            if let measurementBudget,
               visitedNodes >= measurementBudget.maximumNodes || Date() >= measurementBudget.deadline { throw MeasurementLimitReached() }
            visitedNodes += 1
            var active = parents
            var captured: SnapshotAccumulator?
            do {
                guard depth < 512 else { throw EngineError.message("This cache has an unusually deep folder tree. Review it in Finder.") }
                let value: Metadata
                if let parentFD { value = try metadata(at: parentFD, name: name) }
                else { value = try metadata(current) }
                if depth == 0 {
                    if let recordedTrashRootIdentity, !sameRecoveryRoot(value.identity, recordedTrashRootIdentity) {
                        throw EngineError.message("The item in Trash changed while it was being inspected.")
                    }
                    captured = root
                }
                else if depth <= partitionDepth, retainedUnits < maximumPartitionUnits {
                    let accumulator = SnapshotAccumulator(url: current, initial: value)
                    retainedUnits += 1
                    active.append(accumulator)
                    captured = accumulator
                } else if depth <= partitionDepth {
                    // Keep the containing row intact when its retained children
                    // cannot account for the full measured subtree.
                    for accumulator in active { accumulator.partitionComplete = false }
                }
                let counted: Bool
                if value.isRegular { counted = countedFiles.insert("\(value.identity.device):\(value.identity.inode)").inserted }
                else { counted = false }
                for accumulator in active {
                    accumulator.append(current, metadata: value, countAllocation: counted,
                        fingerprintIdentity: depth == 0 ? recordedTrashRootIdentity : nil)
                }
                if value.isSymbolicLink { return captured.map { SnapshotUnit(url: current, snapshot: $0.snapshot()) } }
                if value.isDirectory {
                    let directoryFD: Int32
                    if let parentFD { directoryFD = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                    else { directoryFD = open(current.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                    guard directoryFD >= 0 else { throw EngineError.message("Could not safely open \(current.lastPathComponent): \(String(cString: strerror(errno))).") }
                    defer { close(directoryFD) }
                    var opened = stat()
                    guard fstat(directoryFD, &opened) == 0, metadata(opened).identity == value.identity else {
                        throw EngineError.message("The folder changed while it was being scanned.")
                    }
                    do {
                        let remaining = measurementBudget.map { max(0, $0.maximumNodes - visitedNodes) }
                        let listing = try directoryNames(directoryFD, maximumNames: remaining,
                            deadline: measurementBudget?.deadline, checkCancellation: checkCancellation)
                        for child in listing.names.sorted() {
                            if let unit = try visit(current.appendingPathComponent(child, isDirectory: false),
                                parentFD: directoryFD, name: child, depth: depth + 1, active: active) {
                                captured?.children.append(unit)
                            }
                        }
                        if listing.limited { throw MeasurementLimitReached() }
                        var finished = stat()
                        guard fstat(directoryFD, &finished) == 0, metadata(finished).identity == value.identity else {
                            throw EngineError.message("The folder changed while it was being scanned.")
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch is MeasurementLimitReached { throw MeasurementLimitReached() }
                    catch { issue(current, error, active: active) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch is MeasurementLimitReached { throw MeasurementLimitReached() }
            catch { issue(current, error, active: active) }
            return captured.map { SnapshotUnit(url: current, snapshot: $0.snapshot()) }
        }
        do { _ = try visit(url, parentFD: parentFD, name: url.lastPathComponent, depth: 0, active: [root]) }
        catch is MeasurementLimitReached { root.measurementLimited = true }
        return root.snapshot()
    }

    private static func metadata(at parentFD: Int32, name: String) throws -> Metadata {
        var info = stat()
        guard fstatat(parentFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw EngineError.message("Could not inspect \(name): \(String(cString: strerror(errno))).")
        }
        return metadata(info)
    }

    private static func openDirectoryWithoutFollowingLinks(_ url: URL) throws -> Int32 {
        let components = url.pathComponents.filter { $0 != "/" }
        var descriptor = open("/", (components.isEmpty ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw EngineError.message("Could not open the filesystem root.") }
        for (index, component) in components.enumerated() {
            let accessMode = index == components.count - 1 ? O_RDONLY : O_SEARCH
            let next = openat(descriptor, component, accessMode | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else {
                throw EngineError.message("A parent folder is unavailable or contains a symbolic link. The location was skipped.")
            }
            descriptor = next
        }
        return descriptor
    }

    private static func directoryNames(_ descriptor: Int32, maximumNames: Int? = nil,
                                       deadline: Date? = nil, checkCancellation: Bool = true) throws -> DirectoryListing {
        let copied = dup(descriptor)
        guard copied >= 0 else { throw EngineError.message("The system could not open a cache folder for reading.") }
        guard let directory = fdopendir(copied) else {
            close(copied)
            throw EngineError.message("The cache folder could not be read.")
        }
        defer { closedir(directory) }
        var names: [String] = []
        var limited = false
        while true {
            if checkCancellation { try Task.checkCancellation() }
            if let deadline, Date() >= deadline { throw MeasurementLimitReached() }
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw EngineError.message("The cache folder could not be completely read.") }
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name else { throw EngineError.message("A file has a name this app cannot safely display. Review the folder in Finder.") }
            if name != "." && name != ".." {
                if let maximumNames, names.count >= maximumNames {
                    limited = true
                    break
                }
                names.append(name)
            }
        }
        return DirectoryListing(names: names, limited: limited)
    }

    private static func volumeInfo(at url: URL) -> VolumeInfo {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return VolumeInfo(totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0))
    }

    private static func liveProcessNames() throws -> [String] {
        #if ROOM_APP_STORE
        // A successful ps exit is not proof of complete cross-process visibility
        // inside App Sandbox. Keep guarded resources inspect-only until a
        // trustworthy observation mechanism can establish the owning tools.
        throw EngineError.message("The App Store sandbox cannot verify all background tools. Guarded caches remain held; review them with their owning app.")
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw EngineError.message("The system process list was unavailable.")
        }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #endif
    }

    private static func systemTrash(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw EngineError.movedWithoutURL
        }
        return resultingURL as URL
    }
}

/// Deterministic metadata digest. This is a freshness check, not a content hash.
private struct Fingerprint {
    private var hash: UInt64 = 14_695_981_039_346_656_037
    var value: String { String(hash, radix: 16) }
    mutating func append(_ text: String) {
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        hash = (hash ^ 0xFF) &* 1_099_511_628_211
    }
    mutating func append(_ value: FileIdentity) {
        append("\(value.device):\(value.inode):\(value.modifiedSeconds):\(value.modifiedNanoseconds):\(value.changedSeconds):\(value.changedNanoseconds):\(value.byteCount):\(value.mode)")
    }
}
