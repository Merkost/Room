import AppKit
import Foundation
import Observation
import RoomCore

@Observable
@MainActor
final class RoomViewModel {
    private(set) var sources: [RoomSource] = []
    private(set) var protectedSources: [RoomProtectedSource] = []
    private(set) var selection: Set<String> = []
    private(set) var activity: [RoomActivity] = []
    private(set) var isScanning = false
    private(set) var scanScope: RoomCacheScanScope = .full
    private(set) var isPartialScan = false
    private(set) var currentScanPath = ""
    private(set) var scannedLocationCount = 0
    private(set) var scanLocationCount = 0
    private(set) var isWorking = false
    private(set) var scanProgress: Double?
    private(set) var lastScanned: Date?
    var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var scanIssues: [String] = []
    private(set) var availableBytes: Int64 = 0
    private(set) var capacityBytes: Int64 = 0

    @ObservationIgnored private var engine: CacheEngine
    @ObservationIgnored private var recoveryEngine: CacheEngine
    @ObservationIgnored private let usesInjectedEngine: Bool
    @ObservationIgnored private var report: ScanReport?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = UUID()
    @ObservationIgnored private var sourceGroups: [String: [CacheGroup]] = [:]

    #if ROOM_APP_STORE
    @ObservationIgnored private let fileAccess = RoomFileAccess.shared
    @ObservationIgnored private let storeReview = RoomStoreFolderReview()
    @ObservationIgnored private var storeReviewKey: StoreReviewKey?
    @ObservationIgnored private var storeReviewGeneration = UUID()
    @ObservationIgnored private var storeScanFolders: Set<String> = []
    private(set) var isPreparingStoreReview = false
    private(set) var lastStoreMoveCompleted = false
    private(set) var lastStoreRestoreCompleted = false

    private enum StoreReviewKey: Equatable { case cleanup(UUID, Set<UUID>), restore(UUID) }
    var approvedStoreFolderCount: Int { fileAccess.folders.count }
    var storeAccessRevision: [String] { fileAccess.folders.map { $0.id + ":" + $0.url.path }.sorted() }
    var storeReviewLocations: [URL] { storeReview.locations }
    var storeGrantedPaths: Set<String> { storeReview.grantedPaths }
    var storeTrashPaths: Set<String> { storeReview.trashPaths }
    var storeAllLocationsGranted: Bool { storeReview.allGranted }
    var canRunStoreCleanup: Bool {
        guard let report else { return false }
        return storeReviewKey == .cleanup(report.id, selectedEntryIDs) && storeReview.allGranted
            && !isWorking && !isScanning && !isPreparingStoreReview
    }
    var canRunStoreRestore: Bool {
        guard let key = storeReviewKey, case .restore = key else { return false }
        return storeReview.allGranted && !isWorking && !isScanning && !isPreparingStoreReview
    }
    #endif

    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 {
        sources.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.eligibleBytes }
    }

    var isDeepScan: Bool { scanScope == .full }
    var clearableBytes: Int64 { sources.reduce(0) { $0 + $1.eligibleBytes } }
    var heldBytes: Int64 { max(0, totalBytes - clearableBytes) }
    var hasPartialMeasurements: Bool { isPartialScan || !scanIssues.isEmpty || sources.contains(where: \.isPartial) }
    var canScan: Bool {
        #if ROOM_APP_STORE
        !isWorking && !isPreparingStoreReview
        #else
        !isWorking
        #endif
    }
    var canReviewCleanup: Bool { report != nil && !isScanning && !isPartialScan && !isWorking && selectedBytes > 0 }

    init(engine: CacheEngine? = nil) {
        #if ROOM_APP_STORE
        let initialEngine = engine ?? Self.makeStoreEngine(approvedFolders: RoomFileAccess.shared.folders.map(\.url))
        #else
        let initialEngine = engine ?? CacheEngine(configurationProvider: { .full })
        #endif
        self.engine = initialEngine
        recoveryEngine = initialEngine
        usesInjectedEngine = engine != nil
    }

    func setScanScope(_ scope: RoomCacheScanScope) {
        guard !isWorking, !isScanning, scope != scanScope else { return }
        scanScope = scope
        #if ROOM_APP_STORE
        if !usesInjectedEngine { engine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url)) }
        discardStoreReview()
        #else
        let full = scope == .full
        engine = CacheEngine(configurationProvider: { full ? .full : .standard })
        #endif
        report = nil
        sources = []
        sourceGroups = [:]
        protectedSources = []
        selection = []
        lastScanned = nil
        isPartialScan = false
        statusMessage = nil
        scanIssues = []
        scanProgress = nil
        currentScanPath = ""
    }

    func scanDeep() {
        guard !isWorking, !isScanning else { return }
        setScanScope(.full)
        scan()
    }

    func scanStandard() {
        guard !isWorking, !isScanning else { return }
        setScanScope(.quick)
        scan()
    }

    func scan(completionMessage: String? = nil) {
        guard !isWorking, !isScanning else { return }
        #if ROOM_APP_STORE
        guard !isPreparingStoreReview else { return }
        if !usesInjectedEngine {
            guard RoomStoreEnvironment.userHome != nil else { errorMessage = RoomStoreAccessError.homeUnavailable.localizedDescription; return }
            guard !fileAccess.folders.isEmpty else { chooseStoreFolder(scanAfterApproval: true); return }
            engine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url))
        }
        discardStoreReview()
        let approvedFolders = fileAccess.folders.map(\.url)
        storeScanFolders = Set(approvedFolders.map(\.path))
        #else
        if !usesInjectedEngine {
            let full = scanScope == .full
            engine = CacheEngine(configurationProvider: { full ? .full : .standard })
        }
        #endif
        let generation = UUID()
        scanGeneration = generation
        isScanning = true
        isPartialScan = true
        lastScanned = nil
        if let previous = report { apply(previous, selectInitially: false, allowsCleanup: false) }
        report = nil
        selection = []
        statusMessage = nil
        scanIssues = []
        scanProgress = 0
        scannedLocationCount = 0
        scanLocationCount = 0
        currentScanPath = "Preparing cache and temporary locations…"
        scanTask = Task { [weak self, engine] in
            #if ROOM_APP_STORE
            let scopes = approvedFolders.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { Self.endStoreReadAccess(scopes) }
            #endif
            let result = await engine.scan { [weak self] progress in
                await self?.receiveProgress(progress, generation: generation)
            }
            guard let self, self.scanGeneration == generation else { return }
            self.isScanning = false
            self.scanTask = nil
            if result.cancelled {
                if !result.groups.isEmpty { self.apply(result, selectInitially: false, allowsCleanup: false) }
                self.statusMessage = "Scan stopped. Partial measurements are kept; finish a scan before cleanup."
                self.selection = []
                self.report = nil
                self.lastScanned = nil
                self.isPartialScan = true
                self.scanIssues.append("The scan was stopped. These measurements are partial and cannot be cleaned.")
                return
            }
            self.isPartialScan = false
            self.scanProgress = 1
            self.apply(result, selectInitially: true)
            self.statusMessage = completionMessage
            await self.refreshHistory()
        }
    }

    private func receiveProgress(_ progress: CacheScanProgress, generation: UUID) {
        guard scanGeneration == generation, isScanning else { return }
        currentScanPath = progress.currentPath
        scannedLocationCount = progress.completedRoots
        scanLocationCount = progress.totalRoots
        scanProgress = progress.totalRoots > 0 ? Double(progress.completedRoots) / Double(progress.totalRoots) : nil
        if !progress.partialReport.groups.isEmpty {
            apply(progress.partialReport, selectInitially: false, allowsCleanup: false)
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        selection = []
    }

    func toggleSelection(id: String) {
        guard report != nil, !isScanning, !isPartialScan, !isWorking, sources.contains(where: { $0.id == id && $0.isAvailable }) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func selectRecommended() {
        guard report != nil, !isScanning, !isWorking else { return }
        selection = Set(sources.filter(\.isAvailable).map(\.id))
    }

    func clearSelection() {
        guard !isWorking else { return }
        selection = []
    }

    private var selectedEntryIDs: Set<UUID> {
        Set(selection.flatMap { sourceGroups[$0, default: []].flatMap(\.eligibleEntries).map(\.id) })
    }

    func cleanSelected() async {
        guard !isScanning, !isWorking, report != nil else { return }
        let ids = selectedEntryIDs
        guard !ids.isEmpty else { return }
        #if ROOM_APP_STORE
        lastStoreMoveCompleted = false
        guard canRunStoreCleanup else { errorMessage = RoomStoreAccessError.approvalRequired.localizedDescription; return }
        let scopes = beginStoreReadAccess()
        #endif
        isWorking = true
        defer {
            isWorking = false
            #if ROOM_APP_STORE
            Self.endStoreReadAccess(scopes)
            discardStoreReview()
            #endif
        }
        #if ROOM_APP_STORE
        do {
            let required = try await engine.authorizationLocations(entryIDs: Array(ids))
            try storeReview.validate(exactly: required)
        } catch { errorMessage = error.localizedDescription; return }
        #endif
        let receipt = await engine.clean(entryIDs: ids)
        selection = []
        #if ROOM_APP_STORE
        lastStoreMoveCompleted = receipt.trashedCount > 0
        #endif
        if receipt.trashedCount > 0 {
            statusMessage = "Moved \(ByteCountFormatter.string(fromByteCount: receipt.trashedBytes, countStyle: .file)) to Trash. Disk space is released when Trash is emptied."
        } else {
            statusMessage = "Nothing was moved. Review the activity notes and scan again."
        }
        if !receipt.issues.isEmpty { errorMessage = receipt.issues.prefix(4).map(\.message).joined(separator: "\n\n") }
        await refreshHistory()
        isWorking = false
        #if ROOM_APP_STORE
        if !fileAccess.folders.isEmpty || usesInjectedEngine { scan(completionMessage: statusMessage) }
        #else
        scan(completionMessage: statusMessage)
        #endif
    }

    func restore(record: RoomActivity) async {
        guard !isWorking, !isScanning, record.canRestore else { return }
        #if ROOM_APP_STORE
        lastStoreRestoreCompleted = false
        guard storeReviewKey == .restore(record.id), canRunStoreRestore else {
            errorMessage = RoomStoreAccessError.approvalRequired.localizedDescription
            return
        }
        let scopes = beginStoreReadAccess()
        if !usesInjectedEngine {
            let parents = storeReview.locations.filter { !storeReview.trashPaths.contains($0.path) }
            recoveryEngine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url) + parents)
        }
        #endif
        isWorking = true
        defer {
            isWorking = false
            #if ROOM_APP_STORE
            Self.endStoreReadAccess(scopes)
            discardStoreReview()
            #endif
        }
        #if ROOM_APP_STORE
        do {
            let parents = try await recoveryEngine.restoreAuthorizationLocations(receiptID: record.id)
            let fallbackItems = try await recoveryEngine.restoreTrashAuthorizationLocations(receiptID: record.id)
            guard Set(fallbackItems.map(\.path)).isSubset(of: storeReview.trashPaths) else { throw RoomStoreAccessError.reviewChanged }
            let reviewedTrash = storeReview.locations.filter { storeReview.trashPaths.contains($0.path) }
            try storeReview.validate(exactly: parents + reviewedTrash)
        } catch { errorMessage = error.localizedDescription; return }
        let result = await recoveryEngine.restore(receiptID: record.id, approvedTrashItems: storeReview.approvedTrashItems)
        lastStoreRestoreCompleted = result.restoredCount > 0
        #else
        let result = await recoveryEngine.restore(receiptID: record.id)
        #endif
        statusMessage = result.restoredCount > 0
            ? "Restored \(result.restoredCount) \(result.restoredCount == 1 ? "item" : "items") to their original locations."
            : "Nothing was restored. Existing files were kept."
        if !result.issues.isEmpty { errorMessage = result.issues.prefix(4).map(\.message).joined(separator: "\n\n") }
        await refreshHistory()
        isWorking = false
        #if ROOM_APP_STORE
        if !fileAccess.folders.isEmpty || usesInjectedEngine { scan(completionMessage: statusMessage) }
        #else
        scan(completionMessage: statusMessage)
        #endif
    }

    func reveal(source: RoomSource) {
        let roots = sourceGroups[source.id, default: []].map(\.rootURL)
        guard !roots.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(roots)
    }

    func revealProtected(source: RoomProtectedSource) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.path)])
    }

    func openTrash() {
        #if ROOM_APP_STORE
        guard let home = RoomStoreEnvironment.userHome else { return }
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        #else
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        #endif
        NSWorkspace.shared.open(trash)
    }

    private func apply(_ result: ScanReport, selectInitially: Bool, allowsCleanup: Bool = true) {
        report = allowsCleanup ? result : nil
        if allowsCleanup { lastScanned = result.scannedAt }
        availableBytes = result.volume.availableBytes
        capacityBytes = result.volume.totalBytes
        scanIssues = result.issues.map { "\($0.url.path): \($0.message)" }
        let groups = result.groups.filter { !$0.entries.isEmpty || !$0.issues.isEmpty }
        sourceGroups = Dictionary(grouping: groups) { familyID($0.id) }
        sources = sourceGroups.map { key, groups in
            let entries = groups.flatMap(\.entries)
            let eligible = allowsCleanup ? groups.flatMap(\.eligibleEntries) : []
            let reasons = Array(Set(entries.compactMap(\.eligibility.reason))).sorted()
            let title = familyTitle(key, fallback: groups.first?.title ?? key)
            let paths = groups.map { $0.rootURL.path }.sorted().joined(separator: "\n")
            let consequences = Array(Set(groups.map(\.consequence))).sorted().joined(separator: "\n\n")
            let issues = groups.flatMap(\.issues).map(\.message)
            let held = Dictionary(grouping: entries.filter { !allowsCleanup || !$0.eligibility.isEligible }) {
                allowsCleanup ? ($0.eligibility.reason ?? "Held for review") : "Scan incomplete. Finish measuring before cleanup."
            }
                .map { RoomHeldReason(reason: $0.key, bytes: $0.value.reduce(0) { $0 + $1.byteCount }, count: $0.value.count) }
                .sorted { $0.bytes > $1.bytes }
            let inspectionOnly = groups.allSatisfy { $0.isInspectionOnly == true }
            let eligibilityNote = inspectionOnly
                ? "These resources stay in place. Manage them with their owning application or tool."
                : "Only unchanged cache items older than seven days are eligible. Diagnostic logs must be older than 30 days. Running tools and recent files are excluded."
            return RoomSource(
                id: key,
                name: title,
                subtitle: familySubtitle(key),
                path: paths,
                notes: ([consequences, eligibilityNote] + reasons + issues).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                symbol: groups.first?.symbol ?? "shippingbox",
                category: RoomCategory(rawValue: groups.first?.category ?? "developer") ?? .developer,
                bytes: groups.reduce(0) { $0 + $1.totalBytes },
                eligibleBytes: eligible.reduce(0) { $0 + $1.byteCount },
                entryCount: entries.count,
                selectableCount: eligible.count,
                blockedReason: !allowsCleanup ? "Measurement only until the scan completes." : eligible.isEmpty ? (held.first?.reason ?? reasons.first ?? issues.first ?? "No old, unchanged cache items are available.") : nil,
                isPartial: !allowsCleanup || groups.contains(where: \.isPartial),
                heldReasons: held,
                largestEntries: entries.sorted { $0.byteCount > $1.byteCount }.prefix(20).map {
                    RoomSourceEntry(name: $0.name, path: $0.url.path, bytes: $0.byteCount, reason: $0.eligibility.reason)
                },
                isInspectionOnly: inspectionOnly
            )
        }.sorted {
            if ($0.category == .agents) != ($1.category == .agents) { return $0.category == .agents }
            return $0.eligibleBytes > $1.eligibleBytes
        }
        protectedSources = result.protectedData.map {
            RoomProtectedSource(id: $0.id, name: $0.title, path: $0.url.path,
                reason: $0.reason, bytes: $0.byteCount)
        }
        let available = Set(sources.filter(\.isAvailable).map(\.id))
        selection = selectInitially ? available : selection.intersection(available)
    }

    func refreshHistory() async {
        #if ROOM_APP_STORE
        if !usesInjectedEngine { recoveryEngine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url)) }
        #endif
        let receipts = await recoveryEngine.history()
        activity = receipts.map { receipt in
            let restored = receipt.items.filter { $0.status == .restored }.count
            let failed = receipt.items.filter { $0.status == .failed || $0.status == .pending }.count
            return RoomActivity(
                id: receipt.id, date: receipt.date,
                bytes: receipt.items.filter { $0.status == .trashed || $0.status == .restored }.reduce(0) { $0 + $1.byteCount },
                itemCount: receipt.items.count, restoredCount: restored,
                errorCount: max(failed, receipt.issues.count), canRestore: receipt.canRestore,
                title: restored == receipt.items.count && restored > 0 ? "Restored" : receipt.trashedCount > 0 ? "Moved to Trash" : "Cleanup needs review",
                details: receipt.items.map {
                    RoomActivityItem(id: $0.id, name: $0.originalURL.lastPathComponent, path: $0.originalURL.path,
                        message: $0.message ?? ($0.status == .trashed ? "In Trash" : $0.status == .restored ? "Restored" : "Not moved"),
                        isRestored: $0.status == .restored, canRestore: $0.status == .trashed)
                }
            )
        }
    }

    #if ROOM_APP_STORE
    func chooseStoreFolder(scanAfterApproval: Bool = false) {
        guard !isWorking, !isScanning, !isPreparingStoreReview else { return }
        isWorking = true
        Task { [weak self] in
            let selected = await RoomNativeFolderPicker.shared.choose(title: "Allow Room to inspect storage",
                message: "Choose a cache folder or another folder to inspect. Room remembers read-only access. Supported changes require a separate review and folder approval.",
                prompt: scanAfterApproval ? "Allow & Scan" : "Allow Folder", initialURL: RoomStoreEnvironment.userHome)
            guard let self else { return }
            self.isWorking = false
            guard let selected else { return }
            do {
                _ = try self.fileAccess.remember(selected)
                if scanAfterApproval { self.scan() }
            } catch { self.errorMessage = "Folder access could not be saved. \(error.localizedDescription)" }
        }
    }

    func storeAccessChanged() {
        guard !isWorking else { return }
        let current = Set(fileAccess.folders.map { $0.url.path })
        guard !storeScanFolders.isSubset(of: current) else { return }
        cancelScan()
        selection = []
        report = nil
        isPartialScan = true
        lastScanned = nil
        discardStoreReview()
        statusMessage = "Folder access changed. Scan the approved folders again before cleanup."
    }

    func prepareStoreCleanupReview() async {
        guard canReviewCleanup, !isPreparingStoreReview, let report else { return }
        discardStoreReview()
        errorMessage = nil
        lastStoreMoveCompleted = false
        let token = storeReviewGeneration
        let ids = selectedEntryIDs
        let scopes = beginStoreReadAccess()
        isPreparingStoreReview = true
        defer { Self.endStoreReadAccess(scopes); if token == storeReviewGeneration { isPreparingStoreReview = false } }
        do {
            let locations = try await engine.authorizationLocations(entryIDs: Array(ids))
            guard token == storeReviewGeneration, self.report?.id == report.id, selectedEntryIDs == ids else { return }
            try storeReview.prepare(locations)
            storeReviewKey = .cleanup(report.id, ids)
        } catch { if token == storeReviewGeneration { errorMessage = error.localizedDescription } }
    }

    func prepareStoreRestoreReview(_ record: RoomActivity) async {
        guard !isWorking, !isScanning, !isPreparingStoreReview, record.canRestore else { return }
        discardStoreReview()
        errorMessage = nil
        lastStoreRestoreCompleted = false
        let token = storeReviewGeneration
        let scopes = beginStoreReadAccess()
        isPreparingStoreReview = true
        defer { Self.endStoreReadAccess(scopes); if token == storeReviewGeneration { isPreparingStoreReview = false } }
        if !usesInjectedEngine { recoveryEngine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url)) }
        do {
            guard let receipt = await recoveryEngine.history().first(where: { $0.id == record.id }) else { throw RoomStoreAccessError.reviewChanged }
            let items = receipt.items.filter { $0.status == .trashed }
            let recordedParents = items.compactMap { item -> (url: URL, identity: FileIdentity)? in
                guard let identity = item.originalParentIdentity else { return nil }
                return (item.originalURL.deletingLastPathComponent(), identity)
            }
            let parentsWithoutIdentity = items.filter { $0.originalParentIdentity == nil }.map { $0.originalURL.deletingLastPathComponent() }
            let fallbackURLs = try await recoveryEngine.restoreTrashAuthorizationLocations(receiptID: record.id)
            var fallback: [(url: URL, identity: FileIdentity)] = []
            for url in fallbackURLs {
                guard let item = items.first(where: { $0.trashURL?.path == url.path }), let identity = item.trashIdentity else {
                    throw RoomStoreAccessError.reviewChanged
                }
                fallback.append((url, identity))
            }
            guard token == storeReviewGeneration else { return }
            try storeReview.prepare(parentsWithoutIdentity, recordedDirectories: recordedParents, trashItems: fallback)
            storeReviewKey = .restore(record.id)
        } catch { if token == storeReviewGeneration { errorMessage = error.localizedDescription } }
    }

    func allowStoreReviewLocation(_ url: URL) async {
        guard !isWorking, !isScanning, !isPreparingStoreReview, storeReviewKey != nil else { return }
        isWorking = true
        defer { isWorking = false }
        do { try await storeReview.allow(url) }
        catch { errorMessage = error.localizedDescription }
    }

    func discardStoreReview() {
        guard !isWorking else { return }
        storeReviewGeneration = UUID()
        storeReviewKey = nil
        isPreparingStoreReview = false
        storeReview.discard()
    }

    private func beginStoreReadAccess() -> [(URL, Bool)] {
        fileAccess.folders.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
    }
    private static func endStoreReadAccess(_ scopes: [(URL, Bool)]) {
        for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() }
    }
    private static func makeStoreEngine(approvedFolders: [URL]) -> CacheEngine {
        let activity = RoomStoreEnvironment.activityDirectory
        guard let home = RoomStoreEnvironment.userHome else {
            return CacheEngine(configuration: CacheConfiguration(roots: [], homeDirectory: FileManager.default.homeDirectoryForCurrentUser), activityDirectory: activity)
        }
        return CacheEngine(configurationProvider: { CacheConfiguration.store(approvedFolders: approvedFolders, userHome: home) },
            activityDirectory: activity, trashHomeDirectory: home)
    }
    #endif

    private func familyID(_ id: String) -> String {
        if id.hasPrefix("lmstudio-models") { return "lmstudio-models" }
        if id.hasPrefix("pnpm-store") { return "pnpm-store" }
        if id.hasPrefix("docker-disk") { return "docker-disk" }
        if Self.managedFamilies[id] != nil { return id }
        if id.hasPrefix("codex") { return "codex" }
        if id.hasPrefix("claude") { return "claude" }
        if id.hasPrefix("xcode") { return "xcode" }
        for prefix in ["cursor", "vscode", "antigravity", "swiftpm", "androidstudio", "jetbrains", "deno",
                       "cargo", "slack", "discord", "notion", "figma", "obsidian", "postman", "insomnia", "lmstudio-render"] {
            if id.hasPrefix(prefix) { return prefix }
        }
        for prefix in ["npm", "yarn", "pip"] {
            if id == prefix || id.hasPrefix(prefix + "-") { return prefix }
        }
        if id.hasPrefix("go-") { return "go" }
        return id
    }

    private func familyTitle(_ id: String, fallback: String) -> String {
        if let managed = Self.managedFamilies[id] { return managed.title }
        return ["codex": "Codex", "claude": "Claude", "xcode": "Xcode", "gradle": "Gradle", "npm": "npm", "yarn": "Yarn", "pip": "Python packages", "homebrew": "Homebrew",
         "cursor": "Cursor", "vscode": "VS Code", "antigravity": "Antigravity", "swiftpm": "Swift packages", "androidstudio": "Android Studio",
         "jetbrains": "JetBrains", "deno": "Deno", "go": "Go", "cargo": "Rust packages", "slack": "Slack", "discord": "Discord",
         "notion": "Notion", "figma": "Figma", "obsidian": "Obsidian", "postman": "Postman", "insomnia": "Insomnia",
         "lmstudio-render": "LM Studio interface"][id] ?? fallback
    }

    private func familySubtitle(_ id: String) -> String {
        if id.hasPrefix("store-selected-") { return "Approved folder · inspect only" }
        if let managed = Self.managedFamilies[id] { return managed.subtitle }
        if id.hasPrefix("sandbox-cache-") { return "Sandboxed app cache · inspect only" }
        if id.hasPrefix("custom-") { return "Custom tool location · inspect only" }
        return ["codex": "Interface caches and old diagnostics", "claude": "Rendering caches and old diagnostics",
         "xcode": "Derived build data and indexes", "gradle": "Dependencies and build transforms",
         "npm": "Package downloads and execution cache", "yarn": "Package download cache", "pip": "Downloads and built wheels", "homebrew": "Downloaded package archives",
         "cursor": "Rendering and compiled extension caches", "vscode": "Rendering and compiled extension caches", "antigravity": "Rendering caches",
         "swiftpm": "Package metadata and downloaded artifacts", "androidstudio": "Indexes and compiler caches", "jetbrains": "Indexes and compiler caches",
         "deno": "Generated code and remote modules", "go": "Build cache and module downloads", "cargo": "Package archives and registry metadata",
         "slack": "Downloaded interface and rendering caches", "discord": "Downloaded interface and rendering caches",
         "notion": "Downloaded interface and rendering caches", "figma": "Downloaded interface and rendering caches",
         "obsidian": "Interface caches; vaults stay in place", "postman": "HTTP and compiled rendering caches",
         "insomnia": "HTTP and compiled rendering caches", "lmstudio-render": "Interface caches; model files stay in place",
         "temporary-karma": "Generated webpack test bundles",
         "discovered-app-caches": "Other app cache folders · inspect only",
         "discovered-hidden-caches": "Hidden caches, models, and tools · inspect only",
         "discovered-temporary": "Other temporary items · inspect only",
         "discovered-logs": "App diagnostics · inspect only",
         "discovered-user-cache": "Per-user macOS caches · inspect only"][id] ?? "Measured cache data"
    }

    private static let managedFamilies: [String: (title: String, subtitle: String)] = [
        "pnpm-store": ("pnpm store", "Managed package store · inspect only"),
        "cargo-sources": ("Rust package sources", "Unpacked dependencies · inspect only"),
        "cargo-checkouts": ("Rust Git checkouts", "Dependency working trees · inspect only"),
        "bun-store": ("Bun store", "Managed package store · inspect only"),
        "uv-managed": ("uv cache", "Managed Python cache · inspect only"),
        "maven-repository": ("Maven repository", "Local packages · inspect only"),
        "nuget-packages": ("NuGet packages", "Installed package store · inspect only"),
        "ivy-cache": ("Ivy cache", "Managed package store · inspect only"),
        "gradle-distributions": ("Gradle distributions", "Downloaded Gradle runtimes · inspect only"),
        "konan-toolchains": ("Kotlin/Native toolchains", "Compiler dependencies · inspect only"),
        "android-sdk": ("Android SDK", "Installed developer tools · inspect only"),
        "apple-simulators": ("iOS simulators", "Simulator devices and data · inspect only"),
        "playwright-runtime": ("Playwright browsers", "Installed browser runtimes · inspect only"),
        "puppeteer-runtime": ("Puppeteer browsers", "Installed browser runtimes · inspect only"),
        "firebase-emulators": ("Firebase emulators", "Downloaded emulator runtimes · inspect only"),
        "claude-installations": ("Claude installations", "Installed agent versions · inspect only"),
        "claude-staging": ("Claude runtime staging", "Installation and staging data · inspect only"),
        "codex-runtimes": ("Codex runtimes", "Installed execution tools · inspect only"),
        "codex-runtime-packages": ("Codex runtime packages", "Installed tool packages · inspect only"),
        "android-devices": ("Android virtual devices", "Virtual devices and user data · inspect only"),
        "copilot-indexes": ("Copilot indexes", "Agent project context · inspect only"),
        "lmstudio-models": ("LM Studio models", "Local model weights · inspect only"),
        "lmstudio-models-legacy": ("LM Studio models", "Local model weights · inspect only"),
        "ollama-models": ("Ollama models", "Local model weights · inspect only"),
        "huggingface-models": ("Hugging Face models", "Downloaded models and data · inspect only"),
        "docker-disk": ("Docker storage", "Container images and volumes · inspect only")
    ]
}
