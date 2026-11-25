import AppKit
import Foundation
import Observation
import RoomCore

struct RoomCacheLocationGroup: Identifiable {
    struct Location: Identifiable {
        let id: String
        let title: String
        let url: URL
    }

    let id: String
    let title: String
    let isPersonal: Bool
    var locations: [Location]
}

struct RoomCleanupCandidate: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let bytes: Int64
}

@Observable
@MainActor
final class RoomViewModel {
    let cachesCheckStore: RoomCachesCheckStore
    let makeRoomStore: RoomMakeRoomStore?
    @ObservationIgnored private let mapStore: RoomTreeStore?
    let activityCenter: RoomActivityCenter?
    let ignoreStore: RoomIgnoreStore?
    private(set) var sources: [RoomSource] = []
    private(set) var protectedSources: [RoomProtectedSource] = []
    private(set) var selection: Set<String> = []
    private(set) var activity: [RoomActivity] = []
    private(set) var isAfterRestore = false
    private(set) var measuredSourceCount = 0
    private(set) var readableSourceCount = 0
    private(set) var cleanupProgress: [UUID: ActivityStatus] = [:]
    private(set) var movedReceiptID: UUID?
    private(set) var isScanning = false
    private(set) var scanScope: RoomCacheScanScope = .full
    private(set) var isPartialScan = false
    private(set) var currentScanPath = ""
    private(set) var scannedLocationCount = 0
    private(set) var scanLocationCount = 0
    /// This model's own move, restore or rule change.
    private(set) var working = false
    /// Another engine (Disk Map folder moves) is moving files: one cleanup at a time across Room.
    var externalCleanupBusy = false
    var isWorking: Bool { working || externalCleanupBusy }
    private(set) var scanProgress: Double?
    private(set) var lastScanned: Date?
    private(set) var inspectionConfiguration: CacheConfiguration?
    private(set) var configurationRevision = UUID()
    var errorMessage: String?
    var operationAlert: RoomActionAlert?
    private(set) var scanIssues: [String] = []
    private(set) var availableBytes: Int64 = 0
    private(set) var capacityBytes: Int64 = 0

    @ObservationIgnored private var engine: CacheEngine
    @ObservationIgnored private var recoveryEngine: CacheEngine
    @ObservationIgnored private let usesInjectedEngine: Bool
    @ObservationIgnored private var report: ScanReport?
    @ObservationIgnored private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = UUID()
    @ObservationIgnored private let beforeScanPublication: (@MainActor (ScanReport) async -> Void)?
    @ObservationIgnored private var sourceGroups: [String: [CacheGroup]] = [:]
    @ObservationIgnored private var movedEntryIDs: Set<UUID> = []
    @ObservationIgnored private var ignoredEntryIDs: Set<UUID> = []
    @ObservationIgnored private var mapCleanupPaths = RoomMapCleanupPathIndex([])
    @ObservationIgnored private var candidateIndex: [String: CandidateIndex] = [:] {
        didSet {
            mapCleanupPaths = RoomMapCleanupPathIndex(candidateIndex.values.flatMap { index in
                index.items.compactMap { $0.bytes > 0 ? $0.url.path : nil }
            })
        }
    }
    private var excludedEntryIDs: Set<UUID> = []

    private struct CandidateIndex {
        let items: [RoomCleanupCandidate]
        let ids: Set<UUID>
        let bytesByID: [UUID: Int64]
        let bytes: Int64
    }
    #if !ROOM_APP_STORE
    @ObservationIgnored private var checkingWeekly = false
    #endif

    #if ROOM_APP_STORE
    @ObservationIgnored private let fileAccess: RoomFileAccess
    @ObservationIgnored private let storeReview: RoomStoreFolderReview
    @ObservationIgnored private var storeReviewKey: StoreReviewKey?
    @ObservationIgnored private var storeReviewGeneration = UUID()
    @ObservationIgnored private var storeScanGrants: Set<String> = []
    private(set) var isPreparingStoreReview = false
    private(set) var lastStoreMoveCompleted = false
    private(set) var lastStoreRestoreCompleted = false

    private enum StoreReviewKey: Equatable { case cleanup(UUID, Set<UUID>), restore(UUID) }
    var approvedStoreFolderCount: Int { fileAccess.folders.count }
    var storeAccessRevision: [String] { fileAccess.folders.map { $0.id + ":" + $0.url.path }.sorted() }
    var npmBatch: NPMDiscoveryCoverage? { lastScanned != nil ? report?.npmDiscovery : nil }
    var canContinueNPM: Bool {
        npmBatch?.nextCursor != nil && !isScanning && canScan && !usesInjectedEngine
            && storeScanGrants == Set(storeAccessRevision)
    }
    var storeReviewLocations: [URL] { storeReview.locations }
    var storeGrantedPaths: Set<String> { storeReview.grantedPaths }
    var storeTrashPaths: Set<String> { storeReview.trashPaths }
    var storeAllLocationsGranted: Bool { storeReview.allGranted }
    var canRunStoreCleanup: Bool {
        canReviewCleanup && hasStoreCleanupApproval(for: selectedEntryIDs)
    }

    func hasStoreCleanupApproval(for entryIDs: Set<UUID>) -> Bool {
        guard let report else { return false }
        return storeReviewKey == .cleanup(report.id, entryIDs) && storeReview.allGranted
            && !isWorking && !isScanning && !isPreparingStoreReview
    }
    var canRunStoreRestore: Bool {
        guard let key = storeReviewKey, case .restore = key else { return false }
        return storeReview.allGranted && !isWorking && !isScanning && !isPreparingStoreReview
    }
    #endif

    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 {
        selection.reduce(0) { $0 + selectedBytes(for: $1) }
    }

    var isDeepScan: Bool { scanScope == .full }
    var clearableBytes: Int64 { sources.reduce(0) { $0 + $1.eligibleBytes } }
    var heldBytes: Int64 { max(0, totalBytes - clearableBytes) }
    var hasPartialMeasurements: Bool {
        isPartialScan || report?.npmDiscovery?.isBatch == true || !scanIssues.isEmpty || sources.contains(where: \.isPartial)
    }
    var hasReport: Bool { lastScanned != nil && report != nil }
    var movedReceipt: RoomActivity? { activity.first { $0.id == movedReceiptID } }
    var cachesStatus: String {
        if isScanning { return "Checking…" }
        if isAfterRestore { return "Put back · check again" }
        if movedReceipt != nil { return "Just now" }
        if isPartialScan { return "Stopped" }
        return cachesCheckStore.check?.caption(now: Date(), calendar: .current) ?? "Never checked"
    }

    var checkLocations: [RoomCacheLocationGroup] {
        #if ROOM_APP_STORE
        fileAccess.folders.map { folder in
            RoomCacheLocationGroup(id: folder.id, title: folder.name, isPersonal: true,
                locations: [.init(id: folder.id, title: folder.name, url: folder.url)])
        }
        #else
        Self.standardCheckLocations
        #endif
    }

    #if !ROOM_APP_STORE
    private static let standardCheckLocations: [RoomCacheLocationGroup] = {
        let roots = CacheConfiguration.standard.roots
        let ordered = roots.filter { $0.category != "agents" } + roots.filter { $0.category == "agents" }
        var orderedIDs: [String] = []
        var groups: [String: RoomCacheLocationGroup] = [:]
        for root in ordered {
            let id = familyID(root.id)
            if groups[id] == nil {
                orderedIDs.append(id)
                groups[id] = .init(id: id, title: familyTitle(id, fallback: root.title), isPersonal: false, locations: [])
            }
            groups[id]?.locations.append(.init(id: root.id, title: root.title, url: root.url))
        }
        return orderedIDs.compactMap { groups[$0] }
    }()
    #endif
    var canScan: Bool {
        #if ROOM_APP_STORE
        !isWorking && !isPreparingStoreReview
        #else
        !isWorking
        #endif
    }
    var canRescanFromMenu: Bool {
        #if ROOM_APP_STORE
        canScan && (usesInjectedEngine || (RoomStoreEnvironment.userHome != nil && !fileAccess.folders.isEmpty))
        #else
        canScan
        #endif
    }

    func rescanFromMenu() {
        guard canRescanFromMenu else { return }
        scan()
    }

    var canEditSelection: Bool {
        guard report != nil, !isScanning, !isPartialScan, !isWorking else { return false }
        #if ROOM_APP_STORE
        return !isPreparingStoreReview && storeScanGrants.isSubset(of: Set(storeAccessRevision))
        #else
        return true
        #endif
    }
    var canReviewCleanup: Bool { canEditSelection && selectedBytes > 0 }
    var cleanupRows: [RoomCleanupReview.Row] {
        sources.filter(\.isAvailable).map { source in
            #if ROOM_APP_STORE
            let parents = Set(cleanupCandidates(for: source.id).filter { isEntrySelected($0.id, sourceID: source.id) }
                .map { $0.url.deletingLastPathComponent().path })
            #else
            let parents = Set<String>()
            #endif
            return .init(id: source.id, name: source.name, bytes: source.eligibleBytes,
                         consequence: source.cleanupConsequences.joined(separator: "\n"),
                         entryIDs: selectedIDs(for: source.id), parentFolders: parents,
                         pickedBytes: selectedBytes(for: source.id))
        }
    }

    init(engine: CacheEngine? = nil, cachesCheckStore: RoomCachesCheckStore = RoomCachesCheckStore(),
         makeRoomStore: RoomMakeRoomStore? = nil, activityCenter: RoomActivityCenter? = nil,
         ignoreStore: RoomIgnoreStore? = nil, mapStore: RoomTreeStore? = nil,
         access: RoomFileAccess? = nil, beforeScanPublication: (@MainActor (ScanReport) async -> Void)? = nil,
         storePicker: (@MainActor (URL, Bool) async -> URL?)? = nil) {
        self.cachesCheckStore = cachesCheckStore
        self.makeRoomStore = makeRoomStore
        self.activityCenter = activityCenter
        self.ignoreStore = ignoreStore
        self.mapStore = mapStore
        self.beforeScanPublication = beforeScanPublication
        #if ROOM_APP_STORE
        let access = access ?? .shared
        self.fileAccess = access
        self.storeReview = RoomStoreFolderReview(picker: storePicker)
        let initialEngine = engine ?? Self.makeStoreEngine(approvedFolders: access.folders.map(\.url))
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
        inspectionConfiguration = nil
        configurationRevision = UUID()
        sources = []
        sourceGroups = [:]
        candidateIndex = [:]
        excludedEntryIDs = []
        protectedSources = []
        selection = []
        lastScanned = nil
        isPartialScan = false
        activityCenter?.clear(.caches)
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

    func scan() {
        scan(npmContinuation: nil)
    }

    #if ROOM_APP_STORE
    func continueNPM() {
        guard canContinueNPM, let nextCursor = npmBatch?.nextCursor else { return }
        scan(npmContinuation: nextCursor)
    }
    #endif

    private func scan(npmContinuation: String?) {
        guard !isWorking, !isScanning else { return }
        #if ROOM_APP_STORE
        guard !isPreparingStoreReview else { return }
        if !usesInjectedEngine {
            guard RoomStoreEnvironment.userHome != nil else { errorMessage = RoomStoreAccessError.homeUnavailable.localizedDescription; return }
            guard !fileAccess.folders.isEmpty else { chooseStoreFolder(scanAfterApproval: true); return }
            engine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url), npmContinuation: npmContinuation)
        }
        discardStoreReview()
        let approvedFolders = fileAccess.folders.map(\.url)
        storeScanGrants = Set(storeAccessRevision)
        #else
        if !usesInjectedEngine {
            let full = scanScope == .full
            engine = CacheEngine(configurationProvider: { full ? .full : .standard })
        }
        #endif
        let generation = UUID()
        scanGeneration = generation
        movedReceiptID = nil
        movedEntryIDs = []
        isAfterRestore = false
        isScanning = true
        isPartialScan = true
        lastScanned = nil
        if let previous = report { apply(previous, selectInitially: false, allowsCleanup: false) }
        report = nil
        selection = []
        excludedEntryIDs = []
        candidateIndex = [:]
        activityCenter?.reportScanLabel(.caches, label: "Checking caches…", files: 0, bytes: 0)
        scanIssues = []
        scanProgress = 0
        scannedLocationCount = 0
        scanLocationCount = 0
        currentScanPath = "Preparing cache and temporary locations…"
        scanTask = Task { [weak self, engine] in
            await self?.ignoreStore?.load()
            guard self?.scanGeneration == generation else { return }
            #if ROOM_APP_STORE
            let scopes = approvedFolders.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { Self.endStoreReadAccess(scopes) }
            #endif
            let result = await engine.scan { [weak self] progress in
                await self?.receiveProgress(progress, generation: generation)
            }
            let measuredConfiguration = result.cancelled || Task.isCancelled ? nil : await engine.resolvedInspectionConfiguration()
            await self?.beforeScanPublication?(result)
            guard let self, self.scanGeneration == generation else { return }
            self.isScanning = false
            self.scanTask = nil
            if result.cancelled || Task.isCancelled {
                if !result.groups.isEmpty { self.apply(result, selectInitially: false, allowsCleanup: false) }
                self.activityCenter?.post(.stopped(measured: self.scannedLocationCount, of: self.scanLocationCount), from: .caches)
                self.selection = []
                self.report = nil
                self.lastScanned = nil
                self.isPartialScan = true
                self.scanIssues.append("The scan was stopped. These measurements are partial and cannot be cleaned.")
                return
            }
            self.isPartialScan = false
            self.scanProgress = 1
            self.inspectionConfiguration = measuredConfiguration
            self.configurationRevision = UUID()
            self.apply(result, selectInitially: npmContinuation == nil)
            if let at = self.lastScanned {
                self.cachesCheckStore.save(RoomCachesCheck(at: at, bytes: self.clearableBytes,
                                                           partial: self.hasPartialMeasurements))
            }
            let checked: RoomActivityPillState = self.measuredSourceCount > 0 && self.readableSourceCount == 0
                ? .failed(action: "Room couldn't read any caches.") : .ok(sentence: "Caches checked")
            self.activityCenter?.post(checked, from: .caches)
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
        if !progress.currentPath.isEmpty {
            let name = progress.partialReport.groups.last(where: { $0.rootURL.path == progress.currentPath })?.title
                ?? URL(fileURLWithPath: progress.currentPath).lastPathComponent
            let label = "\(name) · \(progress.completedRoots) of \(progress.totalRoots) places"
            let files = progress.partialReport.groups.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.fileCount } }
            activityCenter?.reportScanLabel(.caches, label: label, files: files, bytes: progress.partialReport.totalBytes)
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        selection = []
    }

    func toggleSelection(id: String) {
        setSelection(id: id, selected: !selection.contains(id) || partiallySelectedSource(id))
    }

    func setSelection(id: String, selected: Bool) {
        guard canEditSelection, let index = candidateIndex[id] else { return }
        if selected {
            selection.insert(id)
            excludedEntryIDs.subtract(index.ids)
        } else {
            selection.remove(id)
        }
        selectionChanged()
    }

    func selectRecommended() {
        guard canEditSelection else { return }
        selection = Set(candidateIndex.keys)
        excludedEntryIDs = []
        selectionChanged()
    }

    func clearSelection() {
        guard canEditSelection else { return }
        selection = []
        excludedEntryIDs = []
        selectionChanged()
    }

    var selectedEntryIDs: Set<UUID> {
        selection.reduce(into: []) { $0.formUnion(selectedIDs(for: $1)) }
    }

    private func selectedIDs(for sourceID: String) -> Set<UUID> {
        guard selection.contains(sourceID), let index = candidateIndex[sourceID] else { return [] }
        return index.ids.subtracting(excludedEntryIDs)
    }

    func cleanupCandidates(for sourceID: String) -> [RoomCleanupCandidate] {
        candidateIndex[sourceID]?.items ?? []
    }

    func mapCleanupAction(at url: URL, includesContents: Bool = true) -> RoomMapCleanupAction? {
        if isScanning { return .checking }
        guard !isWorking else { return nil }
        guard hasReport else { return .check }
        guard canEditSelection else { return nil }
        let path = url.roomLexicallyNormalized.path
        if mapCleanupPaths.contains(path: path, includesContents: includesContents) { return .review }
        #if ROOM_APP_STORE
        if let folder = fileAccess.approval(for: url), !storeScanGrants.contains(folder.id + ":" + folder.url.path) {
            return .check
        }
        #endif
        return includesContents ? .empty : nil
    }

    func makeMapCleanup(at url: URL, includesContents: Bool = true) -> RoomMapCleanup? {
        guard canEditSelection, let report else { return nil }
        let path = url.roomLexicallyNormalized.path
        var seen: Set<UUID> = []
        var rows: [RoomCleanupReview.Row] = []
        for source in sources where source.isAvailable {
            for item in cleanupCandidates(for: source.id)
                where item.bytes > 0 && RoomMapCleanup.matches(item.url, path: path, includesContents: includesContents)
                    && seen.insert(item.id).inserted {
                #if ROOM_APP_STORE
                let parents = Set([item.url.deletingLastPathComponent().path])
                #else
                let parents = Set<String>()
                #endif
                rows.append(.init(id: item.id.uuidString, name: item.name, bytes: item.bytes,
                    consequence: source.cleanupConsequences.joined(separator: "\n"), entryIDs: [item.id],
                    parentFolders: parents, location: item.url.path))
            }
        }
        guard !rows.isEmpty else { return nil }
        rows.sort { $0.bytes == $1.bytes ? ($0.location ?? "") < ($1.location ?? "") : $0.bytes > $1.bytes }
        return RoomMapCleanup(location: url, reportID: report.id, rows: rows, includesContents: includesContents)
    }

    func canCleanMapSelection(_ request: RoomMapCleanup, entryIDs: Set<UUID>) -> Bool {
        canEditSelection && !entryIDs.isEmpty && isCurrentMapSelection(request, entryIDs: entryIDs)
    }

    func isCurrentMapSelection(_ request: RoomMapCleanup, entryIDs: Set<UUID>) -> Bool {
        guard hasReport, report?.id == request.reportID else { return false }
        guard !entryIDs.isEmpty else { return true }
        guard request.includes(entryIDs) else { return false }
        let path = request.location.roomLexicallyNormalized.path
        var remaining = entryIDs
        for index in candidateIndex.values {
            for item in index.items where remaining.contains(item.id) && item.bytes > 0 && request.matches(item.url, path: path) {
                remaining.remove(item.id)
            }
            if remaining.isEmpty { return true }
        }
        return false
    }

    func source(containing path: String) -> RoomSource? {
        guard path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path)
        let matches = sourceGroups.flatMap { sourceID, groups in
            groups.filter { RoomFileAccess.contains(parent: $0.rootURL, child: url) }
                .map { (sourceID, $0.rootURL.path.count) }
        }
        guard let match = matches.max(by: { $0.1 < $1.1 }) else { return nil }
        return sources.first { $0.id == match.0 }
    }

    func isEntrySelected(_ id: UUID, sourceID: String) -> Bool {
        selection.contains(sourceID) && !excludedEntryIDs.contains(id) && candidateIndex[sourceID]?.ids.contains(id) == true
    }

    func selectedBytes(for sourceID: String) -> Int64 {
        guard selection.contains(sourceID), let index = candidateIndex[sourceID] else { return 0 }
        return index.bytes - excludedEntryIDs.intersection(index.ids).reduce(0) { $0 + (index.bytesByID[$1] ?? 0) }
    }

    func partiallySelectedSource(_ sourceID: String) -> Bool {
        selection.contains(sourceID) && candidateIndex[sourceID].map { !$0.ids.isDisjoint(with: excludedEntryIDs) } == true
    }

    func toggleEntrySelection(id: UUID, sourceID: String) {
        guard canEditSelection, let index = candidateIndex[sourceID], index.ids.contains(id) else { return }
        if !selection.contains(sourceID) {
            selection.insert(sourceID)
            excludedEntryIDs.formUnion(index.ids)
            excludedEntryIDs.remove(id)
        } else if excludedEntryIDs.remove(id) == nil {
            excludedEntryIDs.insert(id)
        }
        if index.ids.isSubset(of: excludedEntryIDs) { selection.remove(sourceID) }
        selectionChanged()
    }

    private func selectionChanged() {
        #if ROOM_APP_STORE
        if case .cleanup(_, let previousIDs) = storeReviewKey {
            do { try reconcileCleanupReview(previousIDs: previousIDs) }
            catch { discardStoreReview(); errorMessage = error.localizedDescription }
        }
        #endif
    }

    func cleanSelected() async {
        guard canReviewCleanup else { return }
        await performCleanup(selectedEntryIDs, keepsCacheSelection: false)
    }

    func cleanMapSelection(_ request: RoomMapCleanup, entryIDs: Set<UUID>) async {
        guard canCleanMapSelection(request, entryIDs: entryIDs) else { return }
        await performCleanup(entryIDs, keepsCacheSelection: true)
    }

    private func performCleanup(_ ids: Set<UUID>, keepsCacheSelection: Bool) async {
        guard !ids.isEmpty, !isWorking else { return }
        operationAlert = nil
        #if ROOM_APP_STORE
        lastStoreMoveCompleted = false
        guard hasStoreCleanupApproval(for: ids) else { errorMessage = RoomStoreAccessError.approvalRequired.localizedDescription; return }
        let scopes = beginStoreReadAccess()
        #endif
        working = true
        defer {
            working = false
            #if ROOM_APP_STORE
            Self.endStoreReadAccess(scopes)
            discardStoreReview()
            #endif
        }
        #if ROOM_APP_STORE
        do {
            let required = try await engine.authorizationLocations(entryIDs: Array(ids))
            guard storeScanGrants.isSubset(of: Set(storeAccessRevision)) else { throw RoomStoreAccessError.reviewChanged }
            try storeReview.validate(exactly: required)
        } catch { errorMessage = error.localizedDescription; return }
        #endif
        await cachesCheckStore.invalidateBeforeFileChange(at: Date())
        cleanupProgress = [:]
        let receipt = await engine.clean(entryIDs: ids) { [weak self] id, status in
            await self?.reportCleanupProgress(id: id, status: status)
        }
        await makeRoomStore?.recordMove(receipt: receipt)
        let movedPaths = receipt.items.filter { $0.status == .trashed }.map(\.originalURL)
        for url in movedPaths { await mapStore?.markChanged(under: url, at: receipt.date) }
        if !keepsCacheSelection {
            selection = []
            excludedEntryIDs = []
        }
        #if ROOM_APP_STORE
        lastStoreMoveCompleted = receipt.trashedCount > 0
        #endif
        if receipt.trashedCount > 0 {
            movedReceiptID = receipt.id
            movedEntryIDs.formUnion(receipt.items.filter { $0.status == .trashed }.map(\.id))
            if let report { apply(report, selectInitially: false) }
        }
        var reasons: [RoomMoveFailure: Int] = [:]
        for item in receipt.items where item.status == .failed { reasons[item.failure ?? .other, default: 0] += 1 }
        if receipt.items.count < ids.count { reasons[.staleScan] = ids.count - receipt.items.count }
        let outcome = RoomMoveOutcome(movedCount: receipt.trashedCount, movedBytes: receipt.trashedBytes, failures: reasons,
            withoutRecoveryInfo: receipt.items.filter { $0.status == .trashed && $0.trashIdentity == nil }.count)
        activityCenter?.clear(.caches)
        activityCenter?.post(outcome.pill(receiptID: receipt.id, format: RoomFormat.gb), from: .makeRoom)
        operationAlert = outcome.alert(format: RoomFormat.gb)
        if !receipt.issues.isEmpty { errorMessage = receipt.issues.prefix(4).map(\.message).joined(separator: "\n\n") }
        await refreshHistory()
    }

    private func reportCleanupProgress(id: UUID, status: ActivityStatus) {
        cleanupProgress[id] = status
    }

    func restore(record: RoomActivity) async {
        guard !isWorking, !isScanning, record.canRestore else { return }
        operationAlert = nil
        #if ROOM_APP_STORE
        lastStoreRestoreCompleted = false
        guard storeReviewKey == .restore(record.id), canRunStoreRestore else {
            errorMessage = RoomStoreAccessError.approvalRequired.localizedDescription
            return
        }
        let scopes = beginStoreReadAccess()
        #endif
        working = true
        defer {
            working = false
            #if ROOM_APP_STORE
            Self.endStoreReadAccess(scopes)
            discardStoreReview()
            #endif
        }
        #if ROOM_APP_STORE
        let operationEngine: CacheEngine
        do {
            try storeReview.validate(exactly: storeReview.locations)
            let originalParents = storeReview.locations.filter { !storeReview.trashPaths.contains($0.path) }
            operationEngine = usesInjectedEngine ? recoveryEngine : Self.makeStoreEngine(
                approvedFolders: fileAccess.folders.map(\.url), restoreParents: originalParents)
            let parents = try await operationEngine.restoreAuthorizationLocations(receiptID: record.id)
            let fallbackItems = try await operationEngine.restoreTrashAuthorizationLocations(receiptID: record.id)
            guard Set(fallbackItems.map(\.path)).isSubset(of: storeReview.trashPaths) else { throw RoomStoreAccessError.reviewChanged }
            let reviewedTrash = storeReview.locations.filter { storeReview.trashPaths.contains($0.path) }
            try storeReview.validate(exactly: parents + reviewedTrash)
        } catch { errorMessage = error.localizedDescription; return }
        await cachesCheckStore.invalidateBeforeFileChange(at: Date())
        let result = await operationEngine.restore(receiptID: record.id, approvedTrashItems: storeReview.approvedTrashItems)
        lastStoreRestoreCompleted = result.restoredCount > 0
        #else
        await cachesCheckStore.invalidateBeforeFileChange(at: Date())
        let result = await recoveryEngine.restore(receiptID: record.id)
        #endif
        let outcome = RoomRestoreOutcome(restored: result.restoredCount, skipped: result.skips)
        if let toast = outcome.toast {
            activityCenter?.clear(.makeRoom)
            activityCenter?.post(.ok(sentence: toast), from: .restore)
        }
        operationAlert = outcome.alert
        if result.restoredCount == 0 && !result.issues.isEmpty {
            errorMessage = result.issues.prefix(4).map(\.message).joined(separator: "\n\n")
        }
        if result.restoredCount > 0 {
            report = nil
            selection = []
            excludedEntryIDs = []
            candidateIndex = [:]
            movedReceiptID = nil
            isAfterRestore = true
        }
        await refreshHistory()
        let previouslyRestored = Set(record.details.filter(\.isRestored).map(\.id))
        let restoredAt = Date.now
        for item in result.receipt.items where item.status == .restored && !previouslyRestored.contains(item.id) {
            await mapStore?.markChanged(under: item.originalURL, at: restoredAt)
        }
        await makeRoomStore?.checkNow()
    }

    func reveal(source: RoomSource) {
        let roots = sourceGroups[source.id, default: []].map(\.rootURL)
        guard !roots.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(roots)
    }

    func neverSuggest(_ source: RoomSource) async -> Set<UUID> {
        guard !isScanning, !isWorking else { return [] }
        working = true
        defer { working = false }
        return await addIgnoreLocations(sourceGroups[source.id, default: []].map(\.rootURL))
    }

    func chooseIgnoreLocation() async {
        guard !isScanning, !isWorking else { return }
        working = true
        defer { working = false }
        let folder = await RoomNativeFolderPicker.shared.choose(title: "Never Suggest",
            message: "Choose a folder whose caches Room should keep.", prompt: "Add Folder", initialURL: nil)
        if let folder { _ = await addIgnoreLocations([folder]) }
    }

    func removeIgnoreRules(_ ids: Set<UUID>) async {
        guard !isScanning, !isWorking, let ignoreStore else { return }
        working = true
        defer { working = false }
        do {
            try await ignoreStore.remove(ids)
            applyIgnoreChanges()
        } catch { errorMessage = error.localizedDescription }
    }

    private func addIgnoreLocations(_ locations: [URL]) async -> Set<UUID> {
        guard !isScanning, let ignoreStore else { return [] }
        do {
            #if ROOM_APP_STORE
            let approved = try locations.map { url -> (url: URL, accessFolderID: String?) in
                let folder = fileAccess.folders.filter { RoomFileAccess.contains(parent: $0.url, child: url) }
                    .max { $0.url.path.count < $1.url.path.count }
                guard let folder else { throw RoomIgnoreError.outsideApprovedFolder }
                return (url, folder.id)
            }
            #else
            let approved = locations.map { (url: $0, accessFolderID: nil as String?) }
            #endif
            let added = try await ignoreStore.add(approved)
            if !added.isEmpty { applyIgnoreChanges() }
            return added
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func applyIgnoreChanges() {
        guard let report, !isScanning else { return }
        apply(report, selectInitially: false)
        if let at = lastScanned {
            cachesCheckStore.save(.init(at: at, bytes: clearableBytes, partial: hasPartialMeasurements))
        }
    }

    #if !ROOM_APP_STORE
    func weeklyQuickCheck() async -> RoomWeeklyCheckRecord? {
        guard !isWorking, !isScanning, !checkingWeekly else { return nil }
        checkingWeekly = true
        defer { checkingWeekly = false }
        await ignoreStore?.load()
        let report = await CacheEngine(configurationProvider: { .standard }).scan()
        guard !report.cancelled else { return nil }
        let rules = ignoreStore?.rules ?? []
        let bytes = report.groups.filter { !RoomIgnoreFilter.isIgnored(rootPath: $0.rootURL.path, rules: rules) }
            .reduce(Int64(0)) { $0 + $1.eligibleBytes }
        return RoomWeeklyCheckRecord(at: report.scannedAt, eligibleBytes: bytes, partial: report.isPartial, scope: "quick")
    }
    #endif

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
        measuredSourceCount = result.groups.count
        readableSourceCount = result.groups.filter { !$0.entries.isEmpty || $0.issues.isEmpty }.count
        let groups = result.groups.filter { !$0.entries.isEmpty || !$0.issues.isEmpty }
        let ignoreRules = ignoreStore?.rules ?? []
        ignoredEntryIDs = Set(groups.filter { RoomIgnoreFilter.isIgnored(rootPath: $0.rootURL.path, rules: ignoreRules) }
            .flatMap(\.entries).map(\.id))
        sourceGroups = Dictionary(grouping: groups) { Self.familyID($0.id) }
        sources = sourceGroups.map { key, groups in
            let entries = groups.flatMap(\.entries).filter { !movedEntryIDs.contains($0.id) }
            let eligible = allowsCleanup ? entries.filter { $0.eligibility.isEligible && !ignoredEntryIDs.contains($0.id) } : []
            let reasons = Array(Set(entries.compactMap(\.eligibility.reason))).sorted()
            let title = Self.familyTitle(key, fallback: groups.first?.title ?? key)
            let paths = groups.map { $0.rootURL.path }.sorted().joined(separator: "\n")
            let consequences = Array(Set(groups.map(\.consequence))).sorted().joined(separator: "\n\n")
            let cleanupConsequences = Array(Set(groups.filter { group in
                group.eligibleEntries.contains { !ignoredEntryIDs.contains($0.id) && !movedEntryIDs.contains($0.id) }
            }
                .map(\.consequence).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
            let issues = groups.flatMap(\.issues).map(\.message)
            let held = Dictionary(grouping: entries.filter { !allowsCleanup || !$0.eligibility.isEligible || ignoredEntryIDs.contains($0.id) }) {
                if ignoredEntryIDs.contains($0.id) { return "You asked Room not to suggest this" }
                return allowsCleanup ? ($0.eligibility.reason ?? "Held for review") : "Scan incomplete. Finish measuring before cleanup."
            }
                .map { RoomHeldReason(reason: $0.key, bytes: $0.value.reduce(0) { $0 + $1.byteCount }, count: $0.value.count) }
                .sorted { $0.bytes > $1.bytes }
            let inspectionOnly = groups.allSatisfy { $0.isInspectionOnly == true }
            let eligibilityNote = inspectionOnly
                ? "These resources stay in place. Manage them with their owning application or tool."
                : "Each source sets its own age and validation rules. Recent, changed, or unsupported items stay held."
            return RoomSource(
                id: key,
                name: title,
                subtitle: familySubtitle(key),
                path: paths,
                notes: ([consequences, eligibilityNote] + reasons + issues).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                symbol: groups.first?.symbol ?? "shippingbox",
                category: RoomCategory(rawValue: groups.first?.category ?? "developer") ?? .developer,
                bytes: entries.reduce(0) { $0 + $1.byteCount },
                eligibleBytes: eligible.reduce(0) { $0 + $1.byteCount },
                entryCount: entries.count,
                selectableCount: eligible.count,
                blockedReason: !allowsCleanup ? "Measurement only until the scan completes." : eligible.isEmpty ? (held.first?.reason ?? reasons.first ?? issues.first ?? "No old, unchanged cache items are available.") : nil,
                isPartial: !allowsCleanup || groups.contains(where: \.isPartial),
                heldReasons: held,
                largestEntries: entries.sorted { $0.byteCount > $1.byteCount }.prefix(20).map {
                    RoomSourceEntry(name: $0.name, path: $0.url.path, bytes: $0.byteCount,
                        reason: ignoredEntryIDs.contains($0.id) ? "You asked Room not to suggest this" : $0.eligibility.reason)
                },
                isInspectionOnly: inspectionOnly,
                cleanupConsequences: cleanupConsequences
            )
        }.filter { $0.entryCount > 0 || $0.isPartial || $0.blockedReason != nil && movedEntryIDs.isEmpty }.sorted {
            if ($0.category == .agents) != ($1.category == .agents) { return $0.category == .agents }
            return $0.eligibleBytes > $1.eligibleBytes
        }
        protectedSources = result.protectedData.map {
            RoomProtectedSource(id: $0.id, name: $0.title, path: $0.url.path,
                reason: $0.reason, bytes: $0.byteCount)
        }
        if allowsCleanup {
            candidateIndex = sourceGroups.compactMapValues { groups in
                let entries = groups.flatMap(\.eligibleEntries)
                    .filter { !movedEntryIDs.contains($0.id) && !ignoredEntryIDs.contains($0.id) }
                guard entries.contains(where: { $0.byteCount > 0 }) else { return nil }
                let items = entries.sorted { $0.byteCount == $1.byteCount ? $0.url.path < $1.url.path : $0.byteCount > $1.byteCount }
                    .map { RoomCleanupCandidate(id: $0.id, name: $0.name, url: $0.url, bytes: $0.byteCount) }
                let sizes = Dictionary(items.map { ($0.id, $0.bytes) }, uniquingKeysWith: { first, _ in first })
                return CandidateIndex(items: items, ids: Set(sizes.keys), bytesByID: sizes, bytes: sizes.values.reduce(0, +))
            }
        } else {
            candidateIndex = [:]
        }
        let available = Set(candidateIndex.keys)
        selection = selectInitially ? available : selection.intersection(available)
        excludedEntryIDs.formIntersection(candidateIndex.values.reduce(into: Set<UUID>()) { $0.formUnion($1.ids) })
        selection = selection.filter { !selectedIDs(for: $0).isEmpty }
    }

    func refreshHistory() async {
        #if ROOM_APP_STORE
        if !usesInjectedEngine { recoveryEngine = Self.makeStoreEngine(approvedFolders: fileAccess.folders.map(\.url)) }
        #endif
        let receipts = await recoveryEngine.history()
        await makeRoomStore?.updateReceipts(receipts)
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
                        isRestored: $0.status == .restored, canRestore: $0.status == .trashed, bytes: $0.byteCount,
                        source: Self.familyTitle(Self.familyID($0.rootID), fallback: $0.originalURL.deletingLastPathComponent().lastPathComponent))
                }
            )
        }
    }

    #if ROOM_APP_STORE
    func chooseStoreFolder(scanAfterApproval: Bool = false) {
        guard !isWorking, !isScanning, !isPreparingStoreReview else { return }
        working = true
        Task { [weak self] in
            let selected = await RoomNativeFolderPicker.shared.choose(title: "Allow Room to inspect storage",
                message: "Choose a cache folder or another folder to inspect. Room remembers read-only access. Supported changes require a separate review and folder approval.",
                prompt: scanAfterApproval ? "Allow & Scan" : "Allow Folder", initialURL: RoomStoreEnvironment.userHome)
            guard let self else { return }
            self.working = false
            guard let selected else { return }
            do {
                _ = try self.fileAccess.remember(selected)
                if scanAfterApproval { self.scan() }
            } catch { self.errorMessage = "Folder access could not be saved. \(error.localizedDescription)" }
        }
    }

    func storeAccessChanged() {
        guard !isWorking else { return }
        let current = Set(storeAccessRevision)
        guard !storeScanGrants.isSubset(of: current) else { return }
        storeScanGrants = []
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        selection = []
        excludedEntryIDs = []
        candidateIndex = [:]
        report = nil
        inspectionConfiguration = nil
        configurationRevision = UUID()
        sources = []
        sourceGroups = [:]
        protectedSources = []
        measuredSourceCount = 0
        readableSourceCount = 0
        scannedLocationCount = 0
        scanLocationCount = 0
        scanProgress = nil
        currentScanPath = ""
        scanIssues = []
        isPartialScan = true
        lastScanned = nil
        discardStoreReview()
        activityCenter?.post(.failed(action: "Folder access changed. Check caches again."), from: .caches)
    }

    func prepareStoreCleanupReview() async {
        guard canReviewCleanup else { return }
        let ids = selectedEntryIDs
        await prepareStoreCleanupReview(for: ids) { self.selectedEntryIDs == ids }
    }

    func prepareStoreMapCleanupReview(_ request: RoomMapCleanup, entryIDs: Set<UUID>, mapIsCurrent: () -> Bool = { true }) async {
        guard mapIsCurrent(), canCleanMapSelection(request, entryIDs: entryIDs) else { return }
        await prepareStoreCleanupReview(for: entryIDs) { mapIsCurrent() && self.isCurrentMapSelection(request, entryIDs: entryIDs) }
    }

    private func prepareStoreCleanupReview(for ids: Set<UUID>, isCurrent: () -> Bool) async {
        guard !isPreparingStoreReview, let report else { return }
        discardStoreReview()
        errorMessage = nil
        lastStoreMoveCompleted = false
        let token = storeReviewGeneration
        let scopes = beginStoreReadAccess()
        isPreparingStoreReview = true
        defer { Self.endStoreReadAccess(scopes); if token == storeReviewGeneration { isPreparingStoreReview = false } }
        do {
            let locations = try await engine.authorizationLocations(entryIDs: Array(ids))
            guard token == storeReviewGeneration, self.report?.id == report.id, isCurrent(),
                  storeScanGrants.isSubset(of: Set(storeAccessRevision)) else { return }
            try storeReview.add(locations)
            storeReviewKey = .cleanup(report.id, ids)
            postStoreApprovalNeeds()
        } catch { if token == storeReviewGeneration { errorMessage = error.localizedDescription } }
    }

    private func reconcileCleanupReview(previousIDs: Set<UUID>) throws {
        guard let report else { throw RoomStoreAccessError.reviewChanged }
        let selected = selection.flatMap { sourceID in
            cleanupCandidates(for: sourceID).filter { isEntrySelected($0.id, sourceID: sourceID) }
        }
        let locations = Set(selected.map { $0.url.deletingLastPathComponent().path })
        let expandedParents = Set(selected.filter { !previousIDs.contains($0.id) }
            .map { $0.url.deletingLastPathComponent().path })
        try reconcileCleanupReview(reportID: report.id, entryIDs: Set(selected.map(\.id)),
                                   locations: locations, expandedParents: expandedParents)
    }

    func updateStoreMapCleanupReview(_ request: RoomMapCleanup, entryIDs: Set<UUID>) {
        guard case .cleanup(let reportID, let previousIDs) = storeReviewKey, reportID == request.reportID,
              entryIDs.isEmpty || canCleanMapSelection(request, entryIDs: entryIDs) else { return }
        let rows = request.rows.filter { !$0.entryIDs.isDisjoint(with: entryIDs) }
        let locations = Set(rows.flatMap(\.parentFolders))
        let expandedParents = Set(rows.filter { !$0.entryIDs.isSubset(of: previousIDs) }.flatMap(\.parentFolders))
        do {
            try reconcileCleanupReview(reportID: reportID, entryIDs: entryIDs,
                                       locations: locations, expandedParents: expandedParents)
        } catch {
            discardStoreReview()
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileCleanupReview(reportID: UUID, entryIDs: Set<UUID>,
                                        locations: Set<String>, expandedParents: Set<String>) throws {
        let scopes = beginStoreReadAccess()
        defer { Self.endStoreReadAccess(scopes) }
        storeReview.narrow(to: locations.subtracting(expandedParents))
        try storeReview.add(locations.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) })
        storeReviewKey = .cleanup(reportID, entryIDs)
        postStoreApprovalNeeds()
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
        errorMessage = nil
        working = true
        defer { working = false }
        do { try await storeReview.allow(url) }
        catch { errorMessage = error.localizedDescription }
        postStoreApprovalNeeds()
    }

    private func postStoreApprovalNeeds() {
        let missing = Set(storeReview.locations.map(\.path)).subtracting(storeReview.grantedPaths).count
        if missing > 0 { activityCenter?.post(.needsAccess(folders: missing), from: .access) }
        else { activityCenter?.clear(.access) }
    }

    func discardStoreReview() {
        guard !isWorking else { return }
        storeReviewGeneration = UUID()
        storeReviewKey = nil
        isPreparingStoreReview = false
        storeReview.discard()
        activityCenter?.clear(.access)
    }

    private func beginStoreReadAccess() -> [(URL, Bool)] {
        fileAccess.folders.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
    }
    private static func endStoreReadAccess(_ scopes: [(URL, Bool)]) {
        for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() }
    }
    private static func makeStoreEngine(approvedFolders: [URL], npmContinuation: String? = nil,
                                        restoreParents: [URL]? = nil) -> CacheEngine {
        let activity = RoomStoreEnvironment.activityDirectory
        guard let home = RoomStoreEnvironment.userHome else {
            return CacheEngine(configuration: CacheConfiguration(roots: [], homeDirectory: FileManager.default.homeDirectoryForCurrentUser), activityDirectory: activity)
        }
        return CacheEngine(configurationProvider: {
            if let restoreParents {
                return CacheConfiguration.storeRecovery(approvedFolders: approvedFolders,
                    approvedOriginalParents: restoreParents, userHome: home)
            }
            return CacheConfiguration.store(approvedFolders: approvedFolders, userHome: home, npmContinuation: npmContinuation)
        },
            activityDirectory: activity, trashHomeDirectory: home)
    }
    #endif

    private static func familyID(_ id: String) -> String {
        if id.hasPrefix("store-npm-sha512-") { return "npm-downloads" }
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

    private static func familyTitle(_ id: String, fallback: String) -> String {
        if id == "npm-downloads" { return "Verified npm downloads" }
        if let managed = Self.managedFamilies[id] { return managed.title }
        return ["codex": "Codex", "claude": "Claude", "xcode": "Xcode", "gradle": "Gradle", "npm": "npm", "yarn": "Yarn", "pip": "Python packages", "homebrew": "Homebrew",
         "cursor": "Cursor", "vscode": "VS Code", "antigravity": "Antigravity", "swiftpm": "Swift packages", "androidstudio": "Android Studio",
         "jetbrains": "JetBrains", "deno": "Deno", "go": "Go", "cargo": "Rust packages", "slack": "Slack", "discord": "Discord",
         "notion": "Notion", "figma": "Figma", "obsidian": "Obsidian", "postman": "Postman", "insomnia": "Insomnia",
         "lmstudio-render": "LM Studio interface"][id] ?? fallback
    }

    private func familySubtitle(_ id: String) -> String {
        if id == "npm-downloads" { return "Verified objects in the current batch" }
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
