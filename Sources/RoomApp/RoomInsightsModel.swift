import AppKit
import Foundation
import Observation
import RoomCore

@Observable
@MainActor
final class RoomInsightsModel {
    private(set) var memoryReport: MemoryReport?
    private(set) var isScanningMemory = false
    private(set) var memoryHistory: [RoomMemorySample] = []
    private(set) var diskReport: DiskMapReport?
    private(set) var isScanningDisk = false
    private(set) var diskProgress: DiskScanProgress?
    private(set) var diskURL: URL?
    private(set) var diskStatusMessage: String?
    private(set) var memoryStatusMessage: String?
    /// Compatibility for older consumers; screen-specific messages own new presentation.
    var statusMessage: String? { memoryStatusMessage }
    var accessFolders: [RoomAccessFolder] { fileAccess.folders }
    var accessNote: String? { fileAccess.note }
    private(set) var analysisReport: StorageAnalysisReport?
    private(set) var isAnalyzingStorage = false
    private(set) var analysisStatus: String?
    private(set) var diskAvailableBytes: Int64 = 0
    private(set) var diskCapacityBytes: Int64 = 0
    var requestedDestination: RoomInsightDestination?
    var requestedCleanPath: String?
    var diskBrowserState = RoomDiskBrowserState()
    private var diskHistory: [RoomDiskSnapshot] = []
    private var diskHistoryIndex = -1
    private var cacheConfiguration: CacheConfiguration?
    @ObservationIgnored private var cacheConfigurationRevision = UUID()
    var canGoBack: Bool { diskHistoryIndex > 0 }
    var canGoForward: Bool { diskHistoryIndex >= 0 && diskHistoryIndex + 1 < diskHistory.count }
    var usesCleanClassification: Bool { cacheConfiguration != nil }

    @ObservationIgnored private let memoryScanner: @Sendable () async -> MemoryReport
    @ObservationIgnored private let diskScanner: @Sendable (URL, (@Sendable (DiskScanProgress) -> Void)?) async -> DiskMapReport
    @ObservationIgnored private let analyzer: @Sendable (DiskMapReport, CacheConfiguration) async -> StorageAnalysisReport
    @ObservationIgnored private let fallbackConfigurationProvider: (@Sendable ([URL], URL) async -> CacheConfiguration)?
    @ObservationIgnored private let fileAccess: RoomFileAccess
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private var memoryTask: Task<Void, Never>?
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    @ObservationIgnored private var pendingDiskReport: DiskMapReport?
    @ObservationIgnored private var diskGeneration = UUID()
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisGeneration = UUID()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    init(access: RoomFileAccess = .shared,
         folderPicker: (@MainActor (String, String, String, URL?) async -> URL?)? = nil,
         memoryScanner: (@Sendable () async -> MemoryReport)? = nil,
         diskScanner: (@Sendable (URL, (@Sendable (DiskScanProgress) -> Void)?) async -> DiskMapReport)? = nil,
         analyzer: (@Sendable (DiskMapReport, CacheConfiguration) async -> StorageAnalysisReport)? = nil,
         fallbackConfigurationProvider: (@Sendable ([URL], URL) async -> CacheConfiguration)? = nil) {
        self.fileAccess = access
        self.fallbackConfigurationProvider = fallbackConfigurationProvider
        let memoryEngine = MemoryEngine()
        self.memoryScanner = memoryScanner ?? { await memoryEngine.scan() }
        let diskEngine = DiskMapEngine()
        let storageAI = StorageAIEngine()
        self.diskScanner = diskScanner ?? { url, progress in await diskEngine.scan(url: url, progress: progress) }
        self.analyzer = analyzer ?? { report, configuration in await storageAI.analyze(report: report, configuration: configuration) }
        self.folderPicker = folderPicker ?? { title, message, prompt, initial in
            await RoomNativeFolderPicker.shared.choose(title: title, message: message, prompt: prompt, initialURL: initial)
        }
    }

    func beginMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scanMemory()
                self?.refreshDiskCapacity()
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refreshDiskCapacity() {
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]) else { return }
        diskAvailableBytes = Int64(values.volumeAvailableCapacity ?? 0)
        diskCapacityBytes = Int64(values.volumeTotalCapacity ?? 0)
    }

    func scanMemory() {
        guard !isScanningMemory else { return }
        isScanningMemory = true
        memoryTask = Task { [weak self, memoryScanner] in
            let result = await memoryScanner()
            guard let self else { return }
            self.memoryReport = result
            self.memoryHistory = RoomMemorySample.retaining(result, in: self.memoryHistory)
            self.isScanningMemory = false
            self.memoryTask = nil
        }
    }

    private var suggestedHome: URL {
        #if ROOM_APP_STORE
        RoomStoreEnvironment.userHome ?? FileManager.default.homeDirectoryForCurrentUser
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    func chooseDiskFolder() {
        presentFolderPicker(initialURL: diskURL ?? suggestedHome, mapAfterApproval: true)
    }

    func chooseAccessFolder() {
        presentFolderPicker(initialURL: suggestedHome, mapAfterApproval: false)
    }

    var hasRememberedHomeAccess: Bool {
        #if ROOM_APP_STORE
        guard let home = RoomStoreEnvironment.userHome else { return false }
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        #endif
        return fileAccess.scope(for: home) != nil
    }

    func chooseHomeAccess() {
        #if ROOM_APP_STORE
        guard let home = RoomStoreEnvironment.userHome else {
            fileAccess.setNote("The account home could not be identified. Choose a folder explicitly.")
            return
        }
        #else
        let home = suggestedHome
        #endif
        presentFolderPicker(initialURL: home, mapAfterApproval: false, homeApproval: true)
    }

    private func presentFolderPicker(initialURL: URL, mapAfterApproval: Bool, homeApproval: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let title = homeApproval ? "Remember home folder access" : "Allow Room to inspect a folder"
            let message = homeApproval
                ? "Choose your home folder to remember read-only access to accessible files and hidden folders inside it. macOS may still protect some locations. Other volumes need their own folder approval. Changes always require a separate reviewed write approval."
                : "Choose a folder to inspect. Room remembers read-only access, including accessible descendants. Supported changes require a separate review and approval."
            guard let url = await self.folderPicker(title, message,
                mapAfterApproval ? "Allow & Map" : "Remember Folder", initialURL) else { return }
            do {
                let approved = try self.fileAccess.remember(url)
                if mapAfterApproval { self.scanDisk(url: approved) }
            } catch {
                self.fileAccess.setNote("Access could not be remembered. Choose this folder again next time.")
                if mapAfterApproval { self.scanAuthorizedDisk(url: url, scope: url) }
            }
        }
    }

    func scanHome() {
        let home = suggestedHome
        if fileAccess.scope(for: home) != nil { scanDisk(url: home) }
        else { presentFolderPicker(initialURL: home, mapAfterApproval: true) }
    }

    func scanDisk(url: URL) {
        guard let scope = fileAccess.scope(for: url) else {
            presentFolderPicker(initialURL: url, mapAfterApproval: true)
            return
        }
        scanAuthorizedDisk(url: url, scope: scope)
    }

    private func scanAuthorizedDisk(url: URL, scope: URL) {
        saveCurrentDiskSnapshot()
        diskTask?.cancel()
        cancelStorageAnalysis()
        let sameDestination = diskURL?.path == url.path
        if !sameDestination || diskHistoryIndex < 0 {
            if diskHistoryIndex + 1 < diskHistory.count { diskHistory.removeSubrange((diskHistoryIndex + 1)..<diskHistory.count) }
            diskHistory.append(RoomDiskSnapshot(url: url))
            if diskHistory.count > 20 { diskHistory.removeFirst(diskHistory.count - 20) }
            diskHistoryIndex = diskHistory.count - 1
            diskBrowserState = RoomDiskBrowserState()
        }
        let generation = UUID()
        diskGeneration = generation
        diskURL = url
        diskReport = nil
        pendingDiskReport = nil
        diskProgress = nil
        analysisReport = nil
        analysisStatus = nil
        isScanningDisk = true
        diskStatusMessage = nil
        let approved = fileAccess.folders.map(\.url)
        let scanner = diskScanner
        diskTask = Task { [weak self] in
            let scopes = (approved + [scope]).map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            let result = await scanner(url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.diskGeneration == generation, self.isScanningDisk else { return }
                    self.diskProgress = progress
                }
            }
            guard let self, self.diskGeneration == generation else { return }
            self.pendingDiskReport = result
            if Task.isCancelled {
                self.finishDiskScan(result, configuration: self.cacheConfiguration ?? self.baselineConfiguration, stopped: true)
                return
            }
            let configuration = await self.configurationForDisk(approved: approved + [scope], fallbackRoot: scope)
            guard self.diskGeneration == generation else { return }
            self.finishDiskScan(result, configuration: configuration, stopped: Task.isCancelled)
        }
    }

    private func finishDiskScan(_ result: DiskMapReport, configuration: CacheConfiguration, stopped: Bool = false) {
        pendingDiskReport = nil
        diskReport = result
        analysisReport = StorageAnalyzer.analyze(report: result, configuration: configuration)
        isScanningDisk = false
        diskTask = nil
        diskStatusMessage = result.cancelled ? "Scan stopped. Only measured files appear in this map."
            : stopped ? "Source review stopped. The completed disk measurement is kept." : nil
        saveCurrentDiskSnapshot()
    }

    func rescanDisk() {
        guard let diskURL else { scanHome(); return }
        scanDisk(url: diskURL)
    }

    func cancelDiskScan() {
        guard isScanningDisk else { return }
        diskStatusMessage = "Stopping scan…"
        diskTask?.cancel()
        if let measured = pendingDiskReport {
            // Metadata is already complete. Stop the remaining source review
            // immediately and fence its late result without inventing a partial
            // measurement or discarding the files already measured.
            diskGeneration = UUID()
            finishDiskScan(measured, configuration: cacheConfiguration ?? baselineConfiguration, stopped: true)
        }
    }

    func diskGoBack() { restoreDiskSnapshot(at: diskHistoryIndex - 1) }
    func diskGoForward() { restoreDiskSnapshot(at: diskHistoryIndex + 1) }

    private func saveCurrentDiskSnapshot() {
        guard diskHistory.indices.contains(diskHistoryIndex), let diskURL else { return }
        diskHistory[diskHistoryIndex] = RoomDiskSnapshot(url: diskURL, report: diskReport,
            analysis: analysisReport, status: diskStatusMessage, analysisStatus: analysisStatus, browser: diskBrowserState)
    }

    private func restoreDiskSnapshot(at index: Int) {
        guard diskHistory.indices.contains(index), index != diskHistoryIndex else { return }
        saveCurrentDiskSnapshot()
        diskTask?.cancel(); diskTask = nil
        pendingDiskReport = nil
        diskGeneration = UUID()
        cancelStorageAnalysis()
        diskHistoryIndex = index
        let snapshot = diskHistory[index]
        diskURL = snapshot.url
        diskReport = snapshot.report
        analysisReport = snapshot.analysis
        analysisStatus = snapshot.analysisStatus
        diskBrowserState = snapshot.browser
        diskProgress = nil
        isScanningDisk = false
        diskStatusMessage = snapshot.report == nil ? "This scan was interrupted. Rescan to measure this folder." : snapshot.status
    }

    /// Accepts an already-resolved Clean catalogue. This method never discovers paths.
    func updateCacheConfiguration(_ configuration: CacheConfiguration?) {
        cacheConfiguration = configuration
        cacheConfigurationRevision = UUID()
        cancelStorageAnalysis()
        let resolved = configuration ?? baselineConfiguration
        let message = configuration == nil
            ? "Base source rules. Scan Clean to include its current source catalogue."
            : "Uses the same reviewed source rules as Clean. Labels do not authorize cleanup."
        // Reclassify history even while a new map is being measured. Back must
        // never revive labels from a superseded catalogue snapshot.
        for index in diskHistory.indices {
            guard let cached = diskHistory[index].report else { continue }
            diskHistory[index].analysis = StorageAnalyzer.analyze(report: cached, configuration: resolved)
            diskHistory[index].analysisStatus = message
        }
        guard let report = diskReport else { return }
        analysisReport = StorageAnalyzer.analyze(report: report, configuration: resolved)
        analysisStatus = message
        saveCurrentDiskSnapshot()
    }

    private var baselineConfiguration: CacheConfiguration {
        #if ROOM_APP_STORE
        CacheConfiguration(roots: [], homeDirectory: RoomStoreEnvironment.userHome ?? FileManager.default.homeDirectoryForCurrentUser)
        #else
        .standard
        #endif
    }

    private func configurationForDisk(approved: [URL], fallbackRoot: URL) async -> CacheConfiguration {
        if let cacheConfiguration { return cacheConfiguration }
        let revision = cacheConfigurationRevision
        let fallback: CacheConfiguration
        if let fallbackConfigurationProvider {
            fallback = await fallbackConfigurationProvider(approved, fallbackRoot)
        } else {
            #if ROOM_APP_STORE
            let home = RoomStoreEnvironment.userHome
            let discovery = Task.detached(priority: .utility) {
                home.map { CacheConfiguration.store(approvedFolders: approved, userHome: $0) }
                    ?? CacheConfiguration(roots: [], homeDirectory: fallbackRoot)
            }
            fallback = await withTaskCancellationHandler {
                await discovery.value
            } onCancel: {
                discovery.cancel()
            }
            #else
            // The base catalogue is pure. Full discovery is supplied by the actual
            // Clean scan instead of probing unrelated folders while viewing a map.
            fallback = .standard
            #endif
        }
        // Clean may publish a resolved catalogue while Store fallback discovery
        // is suspended. Re-read current policy on this actor before publishing
        // classifications or saving them into navigation history.
        if let cacheConfiguration { return cacheConfiguration }
        // A newer explicit reset must also win over the suspended fallback.
        if cacheConfigurationRevision != revision { return baselineConfiguration }
        return fallback
    }

    func requestCleanReview(path: String) {
        requestedCleanPath = path
        requestedDestination = .clean
    }

    func analyzeStorage() {
        guard !isAnalyzingStorage, !isScanningDisk, let report = diskReport else { return }
        isAnalyzingStorage = true
        analysisStatus = nil
        let token = UUID(); analysisGeneration = token
        let scanID = report.id
        let diskToken = diskGeneration
        let approved = fileAccess.folders.map(\.url)
        let analyzer = analyzer
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let scopes = approved.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            let configuration = await self.configurationForDisk(approved: approved, fallbackRoot: report.url)
            guard !Task.isCancelled, self.analysisGeneration == token, self.diskGeneration == diskToken else { return }
            let result = await analyzer(report, configuration)
            guard !Task.isCancelled, self.analysisGeneration == token, self.diskGeneration == diskToken,
                  self.diskReport?.id == scanID else { return }
            self.analysisReport = result
            self.analysisStatus = result.availability.reason
            self.isAnalyzingStorage = false
            self.analysisTask = nil
            self.saveCurrentDiskSnapshot()
        }
    }

    func cancelStorageAnalysis() {
        if isAnalyzingStorage { analysisStatus = "Analysis stopped. Current review kept." }
        analysisGeneration = UUID()
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzingStorage = false
    }

    func forgetAccessFolder(id: String) {
        guard let folder = accessFolders.first(where: { $0.id == id }) else { return }
        let affectsCurrent = diskURL.map { RoomFileAccess.contains(parent: folder.url, child: $0) } ?? false
        if affectsCurrent {
            diskTask?.cancel(); diskTask = nil
            pendingDiskReport = nil
            cancelStorageAnalysis()
            diskGeneration = UUID()
            diskReport = nil; diskProgress = nil; analysisReport = nil
            analysisStatus = nil; diskURL = nil; isScanningDisk = false
            diskStatusMessage = "Folder access removed. Choose a folder to inspect again."
        }
        // Conservative invalidation also removes cached paths below this grant;
        // they must be explicitly measured again, even if another grant overlaps.
        let retainedCurrentURL = diskURL
        diskHistory.removeAll { RoomFileAccess.contains(parent: folder.url, child: $0.url) }
        diskHistoryIndex = retainedCurrentURL.flatMap { url in diskHistory.lastIndex { $0.url.path == url.path } } ?? -1
        fileAccess.forget(id: id)
        updateCacheConfiguration(nil)
        fileAccess.setNote("Folder removed from Room. System access can be changed in Privacy & Security.")
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openAppleIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func diskGoUp() {
        guard let diskURL else { return }
        let parent = diskURL.deletingLastPathComponent()
        guard parent.path != diskURL.path else { return }
        scanDisk(url: parent)
    }

    func reveal(item: DiskMapItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func revealDiskRoot() {
        guard let diskURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([diskURL])
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app", isDirectory: true)
        if !NSWorkspace.shared.open(url) { memoryStatusMessage = "Activity Monitor could not be opened." }
    }

    func activateProcess(id: Int32) {
        if let application = NSRunningApplication(processIdentifier: id),
           !application.isTerminated, application.activate() { return }
        openActivityMonitor()
    }
}


private struct RoomDiskSnapshot {
    let url: URL
    var report: DiskMapReport?
    var analysis: StorageAnalysisReport?
    var status: String?
    var analysisStatus: String?
    var browser = RoomDiskBrowserState()
}

enum RoomDiskScope: String, CaseIterable, Identifiable, Hashable {
    case all = "All", hidden = "Hidden", large = "Large"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .hidden: "eye.slash"; case .large: "arrow.up.right.square" }
    }
}
enum RoomDiskListMode: String, CaseIterable, Identifiable, Hashable {
    case contents = "Folder contents", largest = "Largest files"
    var id: String { rawValue }
}
enum RoomDiskSort: String, CaseIterable, Identifiable, Hashable {
    case size = "Size", name = "Name", modified = "Modified"
    var id: String { rawValue }
}
struct RoomDiskBrowserState: Equatable {
    var scope = RoomDiskScope.all
    var category: StorageCategory?
    var query = ""
    var listMode = RoomDiskListMode.contents
    var sort = RoomDiskSort.size

    func bytes(in item: DiskMapItem) -> Int64 {
        if scope == .large && item.allocatedBytes < 1_000_000_000 { return 0 }
        if scope == .hidden {
            return category.map { item.hiddenCategoryAllocatedBytes[$0] ?? 0 } ?? item.hiddenAllocatedBytes
        }
        return category.map { item.categoryAllocatedBytes[$0] ?? (!item.isDirectory && item.category == $0 ? item.allocatedBytes : 0) } ?? item.allocatedBytes
    }

    func matches(_ item: DiskMapItem) -> Bool {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.name.localizedCaseInsensitiveContains(term) || item.url.path.localizedCaseInsensitiveContains(term) else { return false }
        }
        if scope == .large && item.allocatedBytes < 1_000_000_000 { return false }
        if scope == .hidden && !item.isHidden && item.hiddenAllocatedBytes == 0 { return false }
        if let category {
            if scope == .hidden {
                return item.hiddenCategoryAllocatedBytes[category] != nil
            }
            return item.categoryAllocatedBytes[category] != nil || (!item.isDirectory && item.category == category)
        }
        return true
    }

    func items(in report: DiskMapReport, mode: RoomDiskListMode? = nil) -> [DiskMapItem] {
        let candidates = (mode ?? listMode) == .contents ? report.children : report.largestFiles
        return candidates.filter(matches).sorted { lhs, rhs in
            switch sort {
            case .name:
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt { return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast) }
            case .size:
                if bytes(in: lhs) != bytes(in: rhs) { return bytes(in: lhs) > bytes(in: rhs) }
                if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
            }
            return lhs.id < rhs.id
        }
    }

    func total(in report: DiskMapReport) -> Int64 {
        items(in: report, mode: .contents).reduce(0) { $0 + bytes(in: $1) }
    }
}


struct RoomMemorySample: Identifiable, Sendable {
    let id: UUID
    let scannedAt: Date
    let usedBytes: Int64
    let totalBytes: Int64
    let pressure: MemoryPressure

    /// Only completed, available counters enter history; no synthetic values or
    /// extra sampling timer is created to fill a graph.
    static func retaining(_ report: MemoryReport, in history: [RoomMemorySample]) -> [RoomMemorySample] {
        guard report.totalBytes > 0, report.usedBytes > 0 || report.availableBytes > 0,
              report.scannedAt.timeIntervalSince1970.isFinite else { return history }
        var result = history.filter { $0.id != report.id }
        result.append(Self(id: report.id, scannedAt: report.scannedAt,
            usedBytes: report.usedBytes, totalBytes: report.totalBytes, pressure: report.pressure))
        return Array(result.suffix(90))
    }
}
