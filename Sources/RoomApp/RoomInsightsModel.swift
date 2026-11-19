import AppKit
import Foundation
import Observation
import RoomCore

@Observable
@MainActor
final class RoomInsightsModel {
    private(set) var memoryReport: MemoryReport?
    private(set) var pressureHistory: RoomPressureHistory
    private(set) var memorySamples = RoomMemorySampleRing()
    private(set) var isScanningMemory = false
    let diskMap = RoomDiskMapModel()
    @ObservationIgnored let treeStore: RoomTreeStore
    @ObservationIgnored private var restoredDiskMap = false
    private(set) var diskReport: DiskMapReport?
    private(set) var isScanningDisk = false
    private(set) var diskProgress: DiskScanProgress?
    private(set) var diskURL: URL?
    private(set) var homeTree: RoomStoredTree?
    private(set) var applicationsTree: RoomStoredTree?
    private(set) var isMappingHome = false
    private(set) var stoppedMappingHome = false
    private(set) var homeMappingKinds: [String: Int64] = [:]
    private(set) var statusMessage: String?
    var accessFolders: [RoomAccessFolder] { fileAccess.folders }
    var accessNote: String? { fileAccess.note }
    private(set) var analysisReport: StorageAnalysisReport?
    private(set) var isAnalyzingStorage = false
    private(set) var analysisStatus: String?
    let volumeHistory: RoomVolumeHistory
    private(set) var volumeCapacity: RoomVolumeCapacity?
    private(set) var diskCapacitySampledAt: Date?
    var diskAvailableBytes: Int64 { volumeCapacity?.freeBytes ?? 0 }
    var diskCapacityBytes: Int64 { volumeCapacity?.capacityBytes ?? 0 }
    var requestedDestination: RoomInsightDestination?
    var requestedSettings = false
    var requestedSettingsTab: RoomSettingsTab?
    var requestedWelcome = false

    @ObservationIgnored private let readMemory: @MainActor () async -> MemoryReport
    @ObservationIgnored private let waitForMemoryTick: @MainActor () async throws -> Void
    @ObservationIgnored private let pressureStore: RoomPressureHistoryStore
    @ObservationIgnored private var pressureDirty = false
    @ObservationIgnored private var monitorEnabled = false
    @ObservationIgnored private var memoryActive = false
    @ObservationIgnored private let diskEngine = DiskMapEngine()
    @ObservationIgnored private let storageAI = StorageAIEngine()
    @ObservationIgnored private let fileAccess: RoomFileAccess
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private var memoryTask: Task<Void, Never>?
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    @ObservationIgnored private var diskGeneration = UUID()
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var capacityMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var overviewActive = false
    @ObservationIgnored private var didSampleAtLaunch = false
    @ObservationIgnored private let capacityReader: @MainActor () throws -> RoomVolumeCapacity?
    @ObservationIgnored private let waitForCapacityTick: @MainActor () async throws -> Void

    private static let monitorInterval: Duration = .seconds(20)

    init(access: RoomFileAccess = .shared,
         treeStore: RoomTreeStore = .shared,
         folderPicker: (@MainActor (String, String, String, URL?) async -> URL?)? = nil,
         volumeHistory: RoomVolumeHistory = .init(),
         capacityReader: @escaping @MainActor () throws -> RoomVolumeCapacity? = RoomVolumeCapacity.read,
         waitForCapacityTick: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: RoomInsightsModel.monitorInterval)
         },
         pressureStore: RoomPressureHistoryStore = .init(),
         readMemory: (@MainActor () async -> MemoryReport)? = nil,
         waitForMemoryTick: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: RoomInsightsModel.monitorInterval)
         }) {
        self.pressureStore = pressureStore
        pressureHistory = pressureStore.load()
        let engine = MemoryEngine()
        self.readMemory = readMemory ?? { await engine.scan() }
        self.waitForMemoryTick = waitForMemoryTick
        self.fileAccess = access
        self.treeStore = treeStore
        self.volumeHistory = volumeHistory
        self.capacityReader = capacityReader
        self.waitForCapacityTick = waitForCapacityTick
        self.folderPicker = folderPicker ?? { title, message, prompt, initial in
            await RoomNativeFolderPicker.shared.choose(title: title, message: message, prompt: prompt, initialURL: initial)
        }
    }

    func beginMonitoring() {
        guard !monitorEnabled else { return }
        monitorEnabled = true
        updateMemoryMonitoring()
        if capacityMonitorTask == nil { restartCapacityMonitoring(sampleImmediately: true) }
    }

    func stopMonitoring() {
        monitorEnabled = false
        updateMemoryMonitoring()
        if !overviewActive { stopCapacityMonitoring() }
    }

    func setMemoryActive(_ active: Bool) {
        guard memoryActive != active else { return }
        memoryActive = active
        updateMemoryMonitoring()
    }

    private func updateMemoryMonitoring() {
        guard monitorEnabled || memoryActive else {
            monitorTask?.cancel()
            monitorTask = nil
            return
        }
        guard monitorTask == nil else { return }
        let wait = waitForMemoryTick
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.scanMemory()
                do { try await wait() } catch { return }
            }
        }
    }

    func setOverviewActive(_ active: Bool) {
        guard overviewActive != active else { return }
        overviewActive = active
        if active {
            restartCapacityMonitoring(sampleImmediately: true)
        } else if !monitorEnabled {
            stopCapacityMonitoring()
        }
    }

    func refreshDiskCapacity() {
        sampleDiskCapacity()
        if capacityMonitorTask != nil { restartCapacityMonitoring(sampleImmediately: false) }
    }

    func recordCapacityOnLaunch() {
        guard !didSampleAtLaunch else { return }
        didSampleAtLaunch = true
        sampleDiskCapacity(trigger: .launch)
    }

    func recordCapacityOnActivation() { sampleDiskCapacity(trigger: .activation) }

    func recordCapacityAfterScan() { sampleDiskCapacity(trigger: .scanCompleted) }

    private func sampleDiskCapacity(trigger: RoomVolumeTrigger = .monitorTick) {
        volumeCapacity = try? capacityReader()
        diskCapacitySampledAt = Date()
        if let capacity = volumeCapacity { volumeHistory.record(capacity, volumeID: capacity.volumeID, trigger: trigger) }
    }

    private func restartCapacityMonitoring(sampleImmediately: Bool) {
        // Both consumers share a cadence. Resetting it for activation or a retry
        // also cancels any scheduled read before starting the new interval.
        stopCapacityMonitoring()
        let wait = waitForCapacityTick
        capacityMonitorTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            if sampleImmediately { self?.sampleDiskCapacity() }
            while !Task.isCancelled {
                do { try await wait() } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.sampleDiskCapacity()
            }
        }
    }

    private func stopCapacityMonitoring() {
        capacityMonitorTask?.cancel()
        capacityMonitorTask = nil
    }

    func scanMemory() {
        guard !isScanningMemory else { return }
        isScanningMemory = true
        memoryTask = Task { [weak self, readMemory] in
            let result = await readMemory()
            guard let self else { return }
            self.memoryReport = result
            if !Task.isCancelled, result.totalBytes > 0,
               result.usedBytes > 0 || result.availableBytes > 0 {
                self.memorySamples.append(result.usedBytes, at: result.scannedAt)
            }
            if !Task.isCancelled { self.recordPressure(result) }
            self.isScanningMemory = false
            self.memoryTask = nil
        }
    }

    private func recordPressure(_ report: MemoryReport) {
        guard RoomPressureLevel(memoryPressureRaw: report.pressure.rawValue) != nil else { return }
        let previous = pressureHistory.day.buckets.last?.index
        pressureHistory.record(pressureRaw: report.pressure.rawValue, usedBytes: report.usedBytes,
                               swapBytes: RoomMonitorPresentation.measuredSwap(report), at: report.scannedAt)
        pressureDirty = true
        if let previous, pressureHistory.day.buckets.last?.index != previous { savePressureHistory() }
    }

    func savePressureHistory() {
        guard pressureDirty else { return }
        pressureStore.save(pressureHistory)
        pressureDirty = false
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

    private func scanAuthorizedDisk(url: URL, scope: URL, spliceAt: String? = nil) {
        diskTask?.cancel()
        cancelStorageAnalysis()
        analysisReport = nil
        analysisStatus = nil
        let generation = UUID()
        diskGeneration = generation
        let visibleRoot = spliceAt == nil ? url : diskURL ?? url
        let rootID = diskRootID(url: visibleRoot, scope: scope)
        let location = diskLocation(url: visibleRoot, scope: scope)
        let isHome = visibleRoot.standardizedFileURL == suggestedHome.standardizedFileURL
        let displayPath = diskDisplayPath(visibleRoot)
        let mapsHome = isHome && spliceAt == nil
        isMappingHome = mapsHome
        if mapsHome {
            stoppedMappingHome = false
            homeMappingKinds = [:]
        }
        if diskURL?.standardizedFileURL != visibleRoot.standardizedFileURL { diskReport = nil }
        diskURL = visibleRoot
        diskMap.begin(url: visibleRoot)
        diskProgress = nil
        isScanningDisk = true
        statusMessage = nil
        #if ROOM_APP_STORE
        let approved = fileAccess.folders.map(\.url)
        let home = RoomStoreEnvironment.userHome
        #endif
        diskTask = Task { [weak self, diskEngine] in
            #if ROOM_APP_STORE
            let scopes = (approved + [scope]).map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            #else
            let scopedAccess = scope.startAccessingSecurityScopedResource()
            defer { if scopedAccess { scope.stopAccessingSecurityScopedResource() } }
            #endif
            let mapped = await diskEngine.scanTree(url: url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.diskGeneration == generation, self.isScanningDisk else { return }
                    self.diskProgress = progress
                    self.diskMap.accept(progress)
                    if mapsHome {
                        for folder in progress.completedTopLevel {
                            for (kind, bytes) in folder.kindBytes {
                                self.homeMappingKinds[kind, default: 0] += bytes
                            }
                        }
                    }
                }
            }
            guard let self, self.diskGeneration == generation else { return }
            let result = mapped.report
            if let spliceAt {
                self.diskMap.replaceSubtree(at: spliceAt, with: mapped)
                self.isScanningDisk = false
                self.diskTask = nil
                return
            }
            self.diskMap.record(mapped, rootID: rootID, displayPath: displayPath, isHome: isHome)
            self.diskReport = result
            if mapsHome {
                self.homeTree = self.diskMap.current
                self.isMappingHome = false
                self.stoppedMappingHome = result.cancelled
            }
            #if !ROOM_APP_STORE
            if visibleRoot.standardizedFileURL == self.applicationsFolder { self.applicationsTree = self.diskMap.current }
            #endif
            if let location, let map = self.diskMap.current {
                await self.updateTreeApprovals()
                await self.treeStore.record(map, location: location, isHome: isHome)
                guard self.diskGeneration == generation else { return }
                self.diskMap.updateChangeDate(nil)
            }
            #if ROOM_APP_STORE
            let configuration = await Task.detached(priority: .utility) {
                home.map { CacheConfiguration.store(approvedFolders: approved + [scope], userHome: $0) }
                    ?? CacheConfiguration(roots: [], homeDirectory: scope)
            }.value
            guard self.diskGeneration == generation else { return }
            self.analysisReport = StorageAnalyzer.analyze(report: result, configuration: configuration)
            #else
            self.analysisReport = StorageAnalyzer.analyze(report: result, configuration: .deep)
            #endif
            self.isScanningDisk = false
            if !Task.isCancelled { self.recordCapacityAfterScan() }
            self.diskTask = nil
            if result.cancelled { self.statusMessage = "Scan stopped. The map shows only the files measured so far." }
        }
    }

    func cancelDiskScan() { diskTask?.cancel() }

    func analyzeStorage() {
        guard !isAnalyzingStorage, !isScanningDisk, let report = diskReport else { return }
        isAnalyzingStorage = true
        analysisStatus = nil
        let scanID = report.id
        #if ROOM_APP_STORE
        let approved = fileAccess.folders.map(\.url)
        let home = RoomStoreEnvironment.userHome
        #endif
        analysisTask = Task { [weak self, storageAI] in
            #if ROOM_APP_STORE
            let scopes = approved.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            let configuration = await Task.detached(priority: .utility) {
                home.map { CacheConfiguration.store(approvedFolders: approved, userHome: $0) }
                    ?? CacheConfiguration(roots: [], homeDirectory: report.url)
            }.value
            let result = await storageAI.analyze(report: report, configuration: configuration)
            #else
            let result = await storageAI.analyze(report: report, configuration: .deep)
            #endif
            guard let self, !Task.isCancelled, self.diskReport?.id == scanID else { return }
            self.analysisReport = result
            self.analysisStatus = result.availability.reason
            self.isAnalyzingStorage = false
            self.analysisTask = nil
        }
    }

    func cancelStorageAnalysis() {
        if isAnalyzingStorage { analysisStatus = "Analysis stopped. Current review kept." }
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzingStorage = false
    }

    func forgetAccessFolder(id: String) {
        if let folder = accessFolders.first(where: { $0.id == id }),
           let diskURL, RoomFileAccess.contains(parent: folder.url, child: diskURL) {
            cancelDiskScan()
            cancelStorageAnalysis()
            diskGeneration = UUID()
            diskReport = nil
            diskProgress = nil
            analysisReport = nil
            self.diskURL = nil
            diskMap.removeCurrent()
            isScanningDisk = false
            isMappingHome = false
        }
        fileAccess.forget(id: id)
        Task {
            await updateTreeApprovals()
            await treeStore.forget(approvalID: id)
        }
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

    func openDiskMap(rootURL: URL, relativePath: String? = nil) {
        guard fileAccess.scope(for: rootURL) != nil else { return }
        requestedDestination = .disk
        if diskMap.openRetained(rootURL) {
            if let relativePath {
                let path = [diskMap.levelPath, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
                diskMap.go(to: path)
            }
            return
        }
        let approval = fileAccess.scope(for: rootURL) ?? rootURL
        let id = diskRootID(url: rootURL, scope: approval)
        Task {
            guard !isScanningDisk else { return }
            if let map = await treeStore.current(rootID: id), let root = await treeStore.root(for: id) {
                let previous = await treeStore.previous(rootID: id)
                guard !isScanningDisk else { return }
                showStored(map, previous: previous, root: root)
                if let relativePath { diskMap.go(to: relativePath) }
                await treeStore.open(id)
            } else if !isScanningDisk {
                diskURL = rootURL
                diskReport = nil
                diskMap.showUnmapped(rootURL)
            }
        }
    }

    var homeKinds: RoomHomeKinds? {
        guard let homeTree, let volumeCapacity else { return nil }
        var roots = [(path: suggestedHome.standardizedFileURL.path, map: homeTree)]
        #if !ROOM_APP_STORE
        if let apps = applicationsTree, !apps.cancelled, fileAccess.scope(for: applicationsFolder) != nil {
            roots.append((path: applicationsFolder.path, map: apps))
        }
        #endif
        return try? RoomHomeMap.kinds(roots: roots, capacityBytes: volumeCapacity.capacityBytes,
            freeBytes: volumeCapacity.freeBytes, capacityVolumeUUID: volumeCapacity.volumeID).get()
    }

    private var applicationsFolder: URL { URL(fileURLWithPath: "/Applications", isDirectory: true) }

    #if !ROOM_APP_STORE
    func mapApplications() { scanDisk(url: applicationsFolder) }
    #endif

    func refreshHomeMap() async {
        if !isMappingHome, !stoppedMappingHome { homeTree = await treeStore.home() }
        #if !ROOM_APP_STORE
        if let scope = fileAccess.scope(for: applicationsFolder) {
            applicationsTree = await treeStore.current(rootID: diskRootID(url: applicationsFolder, scope: scope))
        }
        #endif
    }

    func restoreDiskMap() async {
        guard !restoredDiskMap else { return }
        restoredDiskMap = true
        await updateTreeApprovals()
        guard let saved = await treeStore.lastOpened(), diskURL == nil, !isScanningDisk else { return }
        showStored(saved.current, previous: saved.previous, root: saved.root)
    }

    func observeTreeChanges() async {
        let updates = await treeStore.changes
        for await id in updates {
            await refreshHomeMap()
            guard diskMap.current?.rootID == id, !isScanningDisk else { continue }
            let root = await treeStore.root(for: id)
            guard diskMap.current?.rootID == id, !isScanningDisk else { continue }
            if let root {
                diskMap.updateChangeDate(root.changedAt)
            } else {
                diskURL = nil
                diskReport = nil
                diskMap.removeCurrent()
            }
        }
    }

    private func showStored(_ map: RoomStoredTree, previous: RoomStoredTree?, root: RoomTreeStore.Root) {
        let url = accessFolders.first(where: { $0.id == root.location.approvalID })
            .flatMap { root.location.resolve(under: $0.url) }
        diskURL = url
        diskReport = nil
        analysisReport = nil
        diskMap.restore(map, previous: previous, root: root, url: url)
    }

    private func updateTreeApprovals() async {
        await treeStore.setApprovals(Dictionary(uniqueKeysWithValues: accessFolders.map { ($0.id, $0.url) }))
    }

    func rescanMappedFolder(_ relativePath: String) {
        guard !isScanningDisk, !relativePath.isEmpty, let url = diskMap.url(for: relativePath),
              let scope = fileAccess.scope(for: url) else { return }
        scanAuthorizedDisk(url: url, scope: scope, spliceAt: relativePath)
    }

    var canRescanDisk: Bool {
        guard let diskURL else { return false }
        return fileAccess.scope(for: diskURL) != nil
    }

    func rescanDisk() {
        guard !isScanningDisk, let diskURL, let scope = fileAccess.scope(for: diskURL) else { return }
        scanAuthorizedDisk(url: diskURL, scope: scope)
    }

    var canGoUpInApprovedMap: Bool { diskMap.canStepOut }

    func encloseApprovedDiskFolder() { diskMap.stepOut() }

    func diskGoUp() { diskMap.stepOut() }

    @discardableResult
    func stepInsideDisk(_ item: DiskMapItem) -> Bool { diskMap.openRetained(item.url) }

    private func diskLocation(url: URL, scope: URL) -> RoomTreeLocation? {
        guard let folder = fileAccess.folders.first(where: { $0.url == scope }) else { return nil }
        let parts = url.standardizedFileURL.pathComponents.dropFirst(scope.standardizedFileURL.pathComponents.count)
        return RoomTreeLocation(approvalID: folder.id, relativePath: parts.joined(separator: "/"))
    }

    private func diskRootID(url: URL, scope: URL) -> String {
        #if ROOM_APP_STORE
        if let location = diskLocation(url: url, scope: scope) {
            return location.approvalID + "-" + RoomTreeRootID.direct(standardizedPath: location.relativePath)
        }
        #endif
        return RoomTreeRootID.direct(standardizedPath: url.standardizedFileURL.path)
    }

    private func diskDisplayPath(_ url: URL) -> String {
        guard RoomFileAccess.contains(parent: suggestedHome, child: url) else { return url.lastPathComponent }
        let parts = url.standardizedFileURL.pathComponents.dropFirst(suggestedHome.standardizedFileURL.pathComponents.count)
        return parts.isEmpty ? "~" : "~/" + parts.joined(separator: "/")
    }

    func reveal(item: DiskMapItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func revealDiskRoot() {
        guard let diskURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([diskURL])
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app", isDirectory: true)
        if !NSWorkspace.shared.open(url) { statusMessage = "Activity Monitor could not be opened." }
    }

    func activateProcess(id: Int32) {
        if let application = NSRunningApplication(processIdentifier: id),
           !application.isTerminated, application.activate() { return }
        openActivityMonitor()
    }
}
