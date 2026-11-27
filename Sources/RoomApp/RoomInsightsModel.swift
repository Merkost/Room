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
    #if DEBUG
    /// Screenshot fixture only: earlier samples, 20 s apart, so the curve has a shape on first sight.
    func debugSeedMemory(_ values: [Int64]) {
        let now = Date()
        for (index, value) in values.enumerated() {
            memorySamples.append(value, at: now.addingTimeInterval(Double(index - values.count) * 20), level: .normal)
        }
    }
    #endif
    private(set) var isScanningMemory = false
    let diskMap = RoomDiskMapModel()
    @ObservationIgnored let treeStore: RoomTreeStore
    @ObservationIgnored private var restoredDiskMap = false
    private(set) var diskReport: DiskMapReport?
    private(set) var isChoosingDiskFolder = false
    private(set) var isScanningDisk = false
    private(set) var diskProgress: DiskScanProgress?
    private(set) var diskURL: URL?
    private(set) var diskInspectorRequest = 0
    private(set) var diskInspectorVisible = false
    private(set) var diskComparisonRequest = 0

    func toggleDiskInspector() { diskInspectorRequest += 1 }
    func setDiskInspectorVisible(_ visible: Bool) { diskInspectorVisible = visible }
    func compareDiskMap() { diskComparisonRequest += 1 }
    private(set) var homeTree: RoomStoredTree?
    private(set) var applicationsTree: RoomStoredTree?
    private(set) var isMappingHome = false
    private(set) var stoppedMappingHome = false
    private(set) var homeMappingKinds: [String: Int64] = [:]
    private(set) var statusMessage: String?
    var accessFolders: [RoomAccessFolder] { fileAccess.folders }
    var unavailableAccessFolders: [RoomUnavailableAccessFolder] { fileAccess.unavailableFolders }
    var accessNote: String? { fileAccess.note }
    private(set) var analysisReport: StorageAnalysisReport?
    private(set) var isAnalyzingStorage = false
    private(set) var analysisStatus: String?
    var canAnalyzeStorage: Bool {
        guard !isAnalyzingStorage, !isScanningDisk, diskMap.current != nil,
              let root = diskMap.rootURL else { return false }
        return fileAccess.scope(for: root) != nil
    }
    let volumeHistory: RoomVolumeHistory
    private(set) var volumeCapacity: RoomVolumeCapacity?
    private(set) var diskCapacitySampledAt: Date?
    var diskAvailableBytes: Int64 { volumeCapacity?.freeBytes ?? 0 }
    var diskCapacityBytes: Int64 { volumeCapacity?.capacityBytes ?? 0 }
    var requestedDestination: RoomInsightDestination?
    var requestedPinnedRoom: UUID?
    var requestedSettings = false
    var requestedSettingsTab: RoomSettingsTab?
    var requestedWelcome = false

    @ObservationIgnored private let readMemory: @MainActor () async -> MemoryReport
    @ObservationIgnored private let waitForMemoryTick: @MainActor () async throws -> Void
    @ObservationIgnored private let pressureStore: RoomPressureHistoryStore
    @ObservationIgnored private let pressureWriter: RoomStateWriter?
    @ObservationIgnored private var pressureLoad: Task<Void, Never>?
    @ObservationIgnored private var bufferedPressure: [MemoryReport] = []
    @ObservationIgnored private var pressureReadOnly = false
    @ObservationIgnored private var savedHistorySuspended = false
    @ObservationIgnored private let activityCenter: RoomActivityCenter?
    @ObservationIgnored private var pressureDirty = false
    @ObservationIgnored private var monitorEnabled = false
    @ObservationIgnored private var memoryActive = false
    @ObservationIgnored private let diskEngine = DiskMapEngine()
    @ObservationIgnored private let storageAI = StorageAIEngine()
    @ObservationIgnored private let fileAccess: RoomFileAccess
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private let confirmHomeMap: @MainActor () async -> Bool
    @ObservationIgnored private let diskFallbackConfiguration: (@MainActor ([URL], URL) async -> CacheConfiguration)?
    @ObservationIgnored private var memoryTask: Task<Void, Never>?
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    @ObservationIgnored private var isReviewingCompletedDiskScan = false
    @ObservationIgnored private var diskGeneration = UUID()
    @ObservationIgnored private var diskOpenGeneration = UUID()
    @ObservationIgnored private var cacheConfiguration: CacheConfiguration?
    @ObservationIgnored private var cacheConfigurationRevision = UUID()
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisRequest: UUID?
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
         confirmHomeMap: (@MainActor () async -> Bool)? = nil,
         volumeHistory: RoomVolumeHistory = .init(),
         capacityReader: @escaping @MainActor () throws -> RoomVolumeCapacity? = RoomVolumeCapacity.read,
         waitForCapacityTick: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: RoomInsightsModel.monitorInterval)
         },
         pressureStore: RoomPressureHistoryStore = .init(),
         pressureWriter: RoomStateWriter? = nil,
         activityCenter: RoomActivityCenter? = nil,
         readMemory: (@MainActor () async -> MemoryReport)? = nil,
         waitForMemoryTick: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: RoomInsightsModel.monitorInterval)
         },
         diskFallbackConfiguration: (@MainActor ([URL], URL) async -> CacheConfiguration)? = nil) {
        self.pressureStore = pressureStore
        self.pressureWriter = pressureWriter
        self.activityCenter = activityCenter
        pressureHistory = pressureWriter == nil ? pressureStore.load() : RoomPressureHistory()
        let engine = MemoryEngine()
        self.readMemory = readMemory ?? { await engine.scan() }
        self.waitForMemoryTick = waitForMemoryTick
        self.fileAccess = access
        self.treeStore = treeStore
        self.volumeHistory = volumeHistory
        self.capacityReader = capacityReader
        self.waitForCapacityTick = waitForCapacityTick
        self.folderPicker = folderPicker ?? { title, message, prompt, initial in
            await RoomNativeFolderPicker.shared.choose(title: title, message: message, prompt: prompt,
                initialURL: initial, treatsFilePackagesAsDirectories: true)
        }
        self.confirmHomeMap = confirmHomeMap ?? Self.askToMapHome
        self.diskFallbackConfiguration = diskFallbackConfiguration
        if let pressureWriter {
            pressureLoad = Task { [weak self] in
                let saved = await pressureWriter.store.load(RoomPressureHistory.self, from: .pressure,
                    legacy: { data in try JSONDecoder().decode(RoomPressureHistory.self, from: data) })
                guard let self, self.pressureLoad != nil, !Task.isCancelled else { return }
                self.pressureLoad = nil
                self.pressureReadOnly = saved.isReadOnly
                if let saved = saved.value, RoomPressureHistoryStore.isValid(saved) {
                    self.pressureHistory = saved
                }
                let buffered = self.bufferedPressure
                self.bufferedPressure.removeAll()
                for report in buffered { self.recordPressure(report) }
            }
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
                self.memorySamples.append(result.usedBytes, at: result.scannedAt,
                                          level: RoomPressureLevel(memoryPressureRaw: result.pressure.rawValue))
            }
            if !Task.isCancelled { self.recordPressure(result) }
            self.isScanningMemory = false
            self.memoryTask = nil
        }
    }

    private func recordPressure(_ report: MemoryReport) {
        guard !savedHistorySuspended, RoomPressureLevel(memoryPressureRaw: report.pressure.rawValue) != nil else { return }
        if pressureLoad != nil {
            bufferedPressure.append(report)
            if bufferedPressure.count > RoomPressureHistory.dayCount { bufferedPressure.removeFirst() }
            return
        }
        let previous = pressureHistory.day.buckets.last?.index
        pressureHistory.record(pressureRaw: report.pressure.rawValue, usedBytes: report.usedBytes,
                               swapBytes: RoomMonitorPresentation.measuredSwap(report), at: report.scannedAt)
        pressureDirty = true
        if let previous, pressureHistory.day.buckets.last?.index != previous { savePressureHistory() }
    }

    func savePressureHistory() {
        guard pressureDirty, !pressureReadOnly else { return }
        if let pressureWriter { pressureWriter.submit(pressureHistory, to: .pressure) }
        else { pressureStore.save(pressureHistory) }
        pressureDirty = false
    }

    func suspendSavedHistory(_ value: Bool) {
        savedHistorySuspended = value
        if value { diskOpenGeneration = UUID() }
        if value, isScanningDisk {
            diskTask?.cancel()
            diskGeneration = UUID()
            diskTask = nil
            isReviewingCompletedDiskScan = false
            isScanningDisk = false
            isMappingHome = false
            activityCenter?.clear(.diskMap)
        }
    }

    func clearDiskHistory() async {
        await treeStore.clearMemory()
        homeTree = nil
        applicationsTree = nil
        diskURL = nil
        diskReport = nil
        diskMap.removeCurrent()
        stoppedMappingHome = false
    }

    func clearPressureHistory() {
        pressureLoad?.cancel()
        pressureLoad = nil
        bufferedPressure = []
        pressureHistory = RoomPressureHistory()
        pressureDirty = false
        pressureWriter?.discardPending(for: .pressure)
    }

    private var suggestedHome: URL {
        #if ROOM_APP_STORE
        RoomStoreEnvironment.userHome ?? FileManager.default.homeDirectoryForCurrentUser
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    var canChooseDiskLocation: Bool { !isScanningDisk && !isChoosingDiskFolder && !savedHistorySuspended }

    func chooseDiskFolder() {
        presentFolderPicker(initialURL: diskURL ?? suggestedHome, mapAfterApproval: true)
    }

    func chooseDiskFolderAndOpenMap() {
        presentFolderPicker(initialURL: diskURL ?? suggestedHome, mapAfterApproval: true, navigation: .diskMap)
    }

    func chooseAccessFolder() {
        presentFolderPicker(initialURL: suggestedHome, mapAfterApproval: false)
    }

    func renewAccess(to folder: RoomUnavailableAccessFolder) {
        guard canChooseDiskLocation, let expected = folder.url else { return }
        isChoosingDiskFolder = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingDiskFolder = false }
            guard let approved = await self.folderPicker("Renew folder access",
                "Choose the original folder to reconnect its Room and saved maps.", "Renew Access", expected) else { return }
            do {
                try self.fileAccess.renew(id: folder.id, approvedURL: approved)
                await self.updateTreeApprovals()
                await self.refreshHomeMap()
                if self.diskMap.hasLostAccess, let map = self.diskMap.current,
                   let root = await self.treeStore.root(for: map.rootID), root.location.approvalID == folder.id {
                    let previous = await self.treeStore.previous(rootID: map.rootID)
                    if self.diskMap.current?.rootID == map.rootID, self.diskMap.hasLostAccess {
                        self.showStored(map, previous: previous, root: root)
                    }
                }
                self.fileAccess.setNote("Folder access renewed.")
            } catch {
                self.fileAccess.setNote("Choose the original folder to renew access, or add a different folder separately.")
            }
        }
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

    private enum DiskPickerNavigation { case unchanged, diskMap, diskMapForNonHome }

    /// `homeConfirmed`: the person already chose to map their home folder (onboarding), so the
    /// "Map your Home folder?" alert is not asked a second time (D-ONV-8).
    private func presentFolderPicker(initialURL: URL, mapAfterApproval: Bool, homeApproval: Bool = false,
                                     homeConfirmed: Bool = false, navigation: DiskPickerNavigation = .unchanged) {
        guard !isChoosingDiskFolder, !mapAfterApproval || canChooseDiskLocation else { return }
        isChoosingDiskFolder = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingDiskFolder = false }
            let title = homeApproval ? "Remember home folder access" : "Allow Room to inspect a folder"
            let message = homeApproval
                ? "Choose your home folder to remember read-only access to accessible files and hidden folders inside it. macOS may still protect some locations. Other volumes need their own folder approval. Changes always require a separate reviewed write approval."
                : "Choose a folder to inspect. Room remembers read-only access, including accessible descendants. Supported changes require a separate review and approval."
            guard let url = await self.folderPicker(title, message,
                mapAfterApproval ? "Allow & Map" : "Remember Folder", initialURL) else { return }
            if mapAfterApproval, self.isHomeFolder(url), !homeConfirmed, !(await self.confirmHomeMap()) { return }
            let approved: URL
            do {
                approved = try self.fileAccess.remember(url)
            } catch {
                self.fileAccess.setNote("Access could not be remembered. Choose this folder again next time.")
                approved = url
            }
            guard mapAfterApproval else { return }
            self.scanAuthorizedDisk(url: approved, scope: approved)
            if self.isScanningDisk,
               navigation == .diskMap || (navigation == .diskMapForNonHome &&
                   approved.standardizedFileURL != self.suggestedHome.standardizedFileURL) {
                self.requestedDestination = .disk
            }
        }
    }

    func scanHome() { scanHome(confirmed: false) }

    /// `confirmed`: chosen as "Map my home folder" in onboarding; every other route still asks "Map your Home folder?".
    func scanHome(confirmed: Bool) {
        guard canChooseDiskLocation else { return }
        let home = suggestedHome
        if fileAccess.scope(for: home) != nil { scanDisk(url: home, homeConfirmed: confirmed) }
        else {
            presentFolderPicker(initialURL: home, mapAfterApproval: true, homeConfirmed: confirmed,
                                navigation: .diskMapForNonHome)
        }
    }

    func scanDisk(url: URL) { scanDisk(url: url, homeConfirmed: false) }

    private func scanDisk(url: URL, homeConfirmed: Bool) {
        guard canChooseDiskLocation else { return }
        guard let scope = mappingScope(for: url) else {
            presentFolderPicker(initialURL: url, mapAfterApproval: true, homeConfirmed: homeConfirmed)
            return
        }
        startApprovedDiskScan(url: url, scope: scope, homeConfirmed: homeConfirmed)
    }

    private var homeMediaFolders: [URL] {
        ["Pictures", "Music"].map { suggestedHome.appendingPathComponent($0, isDirectory: true) }
    }

    func isHomeFolder(_ url: URL) -> Bool {
        url.standardizedFileURL.path == suggestedHome.standardizedFileURL.path
    }

    private func mappingScope(for url: URL) -> URL? {
        guard let scope = fileAccess.scope(for: url) else { return nil }
        if let folder = homeMediaFolders.first(where: { RoomFileAccess.contains(parent: $0, child: url) }),
           !RoomFileAccess.contains(parent: folder, child: scope) { return nil }
        if DiskScanPolicy.isMediaLibrary(url), scope.standardizedFileURL.path != url.standardizedFileURL.path { return nil }
        return scope
    }

    private func startApprovedDiskScan(url: URL, scope: URL, homeConfirmed: Bool = false) {
        guard isHomeFolder(url), !homeConfirmed else {
            scanAuthorizedDisk(url: url, scope: scope)
            return
        }
        isChoosingDiskFolder = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingDiskFolder = false }
            guard await self.confirmHomeMap(), self.mappingScope(for: url) == scope else { return }
            self.scanAuthorizedDisk(url: url, scope: scope)
        }
    }

    private static func askToMapHome() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Map your Home folder?"
        alert.informativeText = "Room leaves Pictures, Music and media libraries out of a Home map. Choose those folders separately to measure them. macOS may ask about other protected locations."
        alert.addButton(withTitle: "Map Home")
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "RoomPrimaryWindow" && $0.isVisible })
                ?? NSApp.keyWindow else { return alert.runModal() == .alertFirstButtonReturn }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) {
                continuation.resume(returning: $0 == .alertFirstButtonReturn)
            }
        }
    }

    private func scanAuthorizedDisk(url: URL, scope: URL, spliceAt: String? = nil) {
        guard !savedHistorySuspended else { return }
        diskTask?.cancel()
        isReviewingCompletedDiskScan = false
        cancelStorageAnalysis()
        analysisReport = nil
        analysisStatus = nil
        let generation = UUID()
        diskGeneration = generation
        diskOpenGeneration = UUID()
        let visibleRoot = spliceAt == nil ? url : diskURL ?? url
        let rootID = diskRootID(url: visibleRoot, scope: scope)
        let location = diskLocation(url: visibleRoot, scope: scope)
        let isHome = isHomeFolder(visibleRoot)
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
        activityCenter?.reportScanLabel(.diskMap, label: displayPath, files: 0, bytes: 0)
        let approved = fileAccess.folders.map(\.url)
        let policy = DiskScanPolicy(skipApplicationContainers: true, separatelyMappedFolders: homeMediaFolders)
        diskTask = Task { [weak self, diskEngine] in
            #if ROOM_APP_STORE
            let scopes = (approved + [scope]).map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            #else
            let scopedAccess = scope.startAccessingSecurityScopedResource()
            defer { if scopedAccess { scope.stopAccessingSecurityScopedResource() } }
            #endif
            let mapped = await diskEngine.scanTree(url: url, policy: policy) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.diskGeneration == generation, self.isScanningDisk else { return }
                    self.diskProgress = progress
                    self.diskMap.accept(progress)
                    self.activityCenter?.reportScanLabel(.diskMap, label: displayPath,
                        files: progress.visitedFiles, bytes: progress.allocatedBytes)
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
            self.activityCenter?.clear(.diskMap)
            if let spliceAt {
                self.diskMap.replaceSubtree(at: spliceAt, with: mapped)
                self.isScanningDisk = false
                self.diskTask = nil
                return
            }
            self.diskMap.record(mapped, rootID: rootID, displayPath: displayPath, isHome: isHome)
            self.diskReport = result
            self.isReviewingCompletedDiskScan = !result.cancelled
            if mapsHome {
                self.homeTree = self.diskMap.current
                self.isMappingHome = false
                self.stoppedMappingHome = result.cancelled
                self.volumeHistory.recordKinds(mapped.tree.kindBytes, at: mapped.report.scannedAt,
                    complete: !mapped.report.cancelled && !mapped.tree.isPartial, volumeID: mapped.volumeID)
            }
            #if !ROOM_APP_STORE
            if visibleRoot.standardizedFileURL == self.applicationsFolder { self.applicationsTree = self.diskMap.current }
            #endif
            if location != nil, !result.cancelled,
               let changedAt = self.diskMap.changedAt, changedAt <= result.scannedAt {
                self.diskMap.updateChangeDate(nil)
            }
            if Task.isCancelled, !result.cancelled { self.cancelDiskScan() }
            if let location, let map = self.diskMap.current {
                await self.updateTreeApprovals()
                guard self.diskGeneration == generation else { return }
                await self.treeStore.record(map, location: location, isHome: isHome)
            }
            guard self.diskGeneration == generation else { return }
            // A stopped walk still publishes measured items. Once a completed
            // map has been stopped during source review, its UI has settled.
            guard result.cancelled || self.isReviewingCompletedDiskScan else { return }
            let configuration = result.cancelled
                ? self.cacheConfiguration ?? self.baseDiskConfiguration
                : await self.configurationForDisk(approved: approved + [scope], fallbackRoot: visibleRoot)
            guard self.diskGeneration == generation,
                  result.cancelled || (self.isReviewingCompletedDiskScan && !Task.isCancelled) else { return }
            self.analysisReport = StorageAnalyzer.analyze(report: result, configuration: configuration)
            self.finishDiskScan()
            if !Task.isCancelled { self.recordCapacityAfterScan() }
            if result.cancelled { self.statusMessage = "Scan stopped. The map shows only the files measured so far." }
        }
    }

    func cancelDiskScan() {
        diskTask?.cancel()
        guard isReviewingCompletedDiskScan, let diskReport else { return }
        finishDiskScan()
        let message = diskReport.isPartial
            ? "Source review stopped. The map keeps the items measured so far."
            : "Source review stopped. The map is complete."
        analysisStatus = message
        analysisReport = StorageAnalyzer.analyze(report: diskReport,
            configuration: cacheConfiguration ?? baseDiskConfiguration)
    }

    private func finishDiskScan() {
        isReviewingCompletedDiskScan = false
        isScanningDisk = false
        diskTask = nil
    }

    func updateCacheConfiguration(_ configuration: CacheConfiguration?) {
        cacheConfiguration = configuration
        cacheConfigurationRevision = UUID()
        cancelStorageAnalysis()
        analysisStatus = nil
        guard let map = diskMap.current, let root = diskMap.rootURL,
              let measured = measuredDiskReport(for: map, root: root) else {
            analysisReport = nil
            return
        }
        analysisReport = StorageAnalyzer.analyze(report: measured,
            configuration: configuration ?? baseDiskConfiguration)
    }

    private var baseDiskConfiguration: CacheConfiguration {
        #if ROOM_APP_STORE
        CacheConfiguration(roots: [], homeDirectory: suggestedHome)
        #else
        .standard
        #endif
    }

    private func configurationForDisk(approved: [URL], fallbackRoot: URL) async -> CacheConfiguration {
        if let cacheConfiguration { return cacheConfiguration }
        let revision = cacheConfigurationRevision
        let fallback: CacheConfiguration
        if let diskFallbackConfiguration {
            fallback = await diskFallbackConfiguration(approved, fallbackRoot)
        } else {
            #if ROOM_APP_STORE
            let home = RoomStoreEnvironment.userHome
            let lookup = Task.detached(priority: .utility) {
                home.map { CacheConfiguration.store(approvedFolders: approved, userHome: $0) }
                    ?? CacheConfiguration(roots: [], homeDirectory: fallbackRoot)
            }
            fallback = await withTaskCancellationHandler { await lookup.value } onCancel: { lookup.cancel() }
            #else
            // Expanded Direct discovery belongs to the explicit Caches check.
            fallback = baseDiskConfiguration
            #endif
        }
        if let cacheConfiguration { return cacheConfiguration }
        return cacheConfigurationRevision == revision ? fallback : baseDiskConfiguration
    }

    private func measuredDiskReport(for map: RoomStoredTree, root: URL) -> DiskMapReport? {
        diskReport.flatMap { report in
            report.url.roomLexicallyNormalized.path == root.roomLexicallyNormalized.path && report.scannedAt == map.scannedAt
                && report.allocatedBytes == map.tree.allocatedBytes && report.fileCount == map.tree.fileCount ? report : nil
        }
    }

    func analyzeStorage() {
        guard canAnalyzeStorage, let map = diskMap.current, let root = diskMap.rootURL else { return }
        let scanned = measuredDiskReport(for: map, root: root)
        let request = UUID()
        let generation = diskGeneration
        analysisRequest = request
        isAnalyzingStorage = true
        analysisStatus = nil
        let approved = fileAccess.folders.map(\.url)
        analysisTask = Task { [weak self, storageAI] in
            defer { self?.finishStorageAnalysis(request: request) }
            #if ROOM_APP_STORE
            let scopes = approved.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, active) in scopes where active { url.stopAccessingSecurityScopedResource() } }
            #endif
            guard let configuration = await self?.configurationForDisk(approved: approved, fallbackRoot: root),
                  !Task.isCancelled else { return }
            let report: DiskMapReport
            if let scanned { report = scanned }
            else { report = await Task.detached(priority: .utility) { map.metadataReport(for: root) }.value }
            guard !Task.isCancelled else { return }
            let result = await storageAI.analyze(report: report, configuration: configuration,
                includesLogicalBytes: scanned != nil)
            guard let self, !Task.isCancelled, self.analysisRequest == request, self.diskGeneration == generation,
                  self.diskMap.rootURL == root, self.diskMap.current == map,
                  self.fileAccess.scope(for: root) != nil else { return }
            self.analysisReport = result
            let status = result.findings.isEmpty
                ? "No measured items were available to analyse."
                : result.availability.reason
            self.analysisStatus = scanned == nil ? "Reviewed the saved map. \(status)" : status
        }
    }

    private func finishStorageAnalysis(request: UUID) {
        guard analysisRequest == request else { return }
        analysisRequest = nil
        isAnalyzingStorage = false
        analysisTask = nil
    }

    func cancelStorageAnalysis() {
        if isAnalyzingStorage { analysisStatus = "Analysis stopped. Current review kept." }
        analysisRequest = nil
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzingStorage = false
    }

    func stageAccessRemoval(id: String) {
        stopReadingAccessFolder(id: id)
        fileAccess.stageRemoval(id: id)
    }

    func undoAccessRemoval(id: String) { fileAccess.undoRemoval(id: id) }

    func forgetAccessFolder(id: String) {
        stopReadingAccessFolder(id: id)
        fileAccess.forget(id: id)
        Task {
            await updateTreeApprovals()
            await treeStore.forget(approvalID: id)
            await refreshHomeMap()
        }
        fileAccess.setNote("Folder removed from Room. System access can be changed in Privacy & Security.")
    }

    private func stopReadingAccessFolder(id: String) {
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
            finishDiskScan()
            isMappingHome = false
            activityCenter?.clear(.diskMap)
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openAppleIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func openDiskMap(rootURL: URL, relativePath: String? = nil, requestNavigation: Bool = true) {
        guard canChooseDiskLocation, let approval = fileAccess.scope(for: rootURL) else { return }
        let generation = UUID()
        diskOpenGeneration = generation
        if requestNavigation { requestedDestination = .disk }
        if diskMap.openRetained(rootURL) {
            if let relativePath {
                let path = [diskMap.levelPath, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
                diskMap.go(to: path)
            }
            return
        }
        let id = diskRootID(url: rootURL, scope: approval)
        Task {
            let map = await treeStore.current(rootID: id)
            let root = await treeStore.root(for: id)
            let previous = await treeStore.previous(rootID: id)
            guard diskOpenGeneration == generation, canChooseDiskLocation,
                  fileAccess.scope(for: rootURL) == approval else { return }
            if let map, let root {
                showStored(map, previous: previous, root: root)
                if let relativePath { diskMap.go(to: relativePath) }
                await treeStore.open(id)
            } else {
                cancelStorageAnalysis()
                analysisReport = nil
                analysisStatus = nil
                diskURL = rootURL
                diskReport = nil
                statusMessage = nil
                diskMap.showUnmapped(rootURL)
            }
        }
    }

    func savedViewLocation() -> RoomTreeLocation? {
        guard canChooseDiskLocation, let current = diskMap.current, !current.cancelled,
              let root = diskMap.rootURL, let scope = mappingScope(for: root) else { return nil }
        return diskLocation(url: root, scope: scope)
    }

    func openSavedDiskView(_ view: RoomSavedView) async -> RoomSavedViewOpenResult {
        guard canChooseDiskLocation else { return .unavailable }
        guard view.isValid, let folder = accessFolders.first(where: { $0.id == view.root.approvalID }),
              let rootURL = view.root.resolve(under: folder.url),
              let scope = mappingScope(for: rootURL) else { return .needsAccess }
        let generation = UUID()
        diskOpenGeneration = generation
        let rootID = diskRootID(url: rootURL, scope: scope)

        func navigateToSavedNode() -> RoomSavedViewOpenResult {
            if diskMap.go(to: view.nodePath) { return .opened }
            diskMap.go(to: "")
            return .rootOnly
        }

        if diskMap.rootURL?.standardizedFileURL == rootURL.standardizedFileURL,
           diskMap.current?.rootID == rootID, diskMap.current?.cancelled == false {
            return navigateToSavedNode()
        }

        let map = await treeStore.current(rootID: rootID)
        let root = await treeStore.root(for: rootID)
        let previous = await treeStore.previous(rootID: rootID)
        guard !Task.isCancelled, diskOpenGeneration == generation, canChooseDiskLocation else { return .unavailable }
        guard accessFolders.contains(where: { $0.id == folder.id && $0.url == folder.url }),
              mappingScope(for: rootURL) == scope else { return .needsAccess }
        if let map, let root, root.location == diskLocation(url: rootURL, scope: scope), !map.cancelled {
            showStored(map, previous: previous, root: root)
            let result = navigateToSavedNode()
            await treeStore.open(rootID)
            return result
        }

        if isHomeFolder(rootURL) {
            isChoosingDiskFolder = true
            let approved = await confirmHomeMap()
            isChoosingDiskFolder = false
            guard approved, !Task.isCancelled, diskOpenGeneration == generation else { return .unavailable }
        }
        guard accessFolders.contains(where: { $0.id == folder.id && $0.url == folder.url }),
              mappingScope(for: rootURL) == scope else { return .needsAccess }

        scanAuthorizedDisk(url: rootURL, scope: scope)
        let scan = diskTask
        let scanGeneration = diskGeneration
        await scan?.value
        guard !Task.isCancelled, diskGeneration == scanGeneration, diskMap.current?.rootID == rootID,
              diskMap.current?.cancelled == false, !isScanningDisk else { return .unavailable }
        return navigateToSavedNode()
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

    func previousHomeTreeForHistory() async -> RoomStoredTree? {
        guard !savedHistorySuspended, let homeTree, !homeTree.isPartial,
              let volume = homeTree.volumeUUID, volume == volumeCapacity?.volumeID,
              let previous = await treeStore.previous(rootID: homeTree.rootID),
              self.homeTree == homeTree, previous.rootID == homeTree.rootID, !previous.isPartial,
              previous.scannedAt < homeTree.scannedAt, previous.volumeUUID == volume else { return nil }
        return previous
    }

    func restoreDiskMap() async {
        guard !restoredDiskMap else { return }
        restoredDiskMap = true
        let generation = diskOpenGeneration
        await updateTreeApprovals()
        guard let saved = await treeStore.launchMap(), diskOpenGeneration == generation,
              diskURL == nil, canChooseDiskLocation else { return }
        showStored(saved.current, previous: saved.previous, root: saved.root)
    }

    /// True when Disk Map shows something other than the top of the home map, and a home map exists to go back to.
    var canGoBackToHomeMap: Bool {
        guard let home = diskMap.catalog.homeRootID, !isScanningDisk else { return false }
        return diskMap.current?.rootID != home || !diskMap.levelPath.isEmpty
    }

    /// "Back to home folder": the top of the saved home map. Reads nothing new.
    func showHomeMap() async {
        if let home = diskMap.catalog.homeRootID, diskMap.current?.rootID == home {
            diskMap.go(to: "")
            return
        }
        let generation = diskOpenGeneration
        guard let saved = await treeStore.homeEntry(), diskOpenGeneration == generation, !isScanningDisk else { return }
        showStored(saved.current, previous: saved.previous, root: saved.root)
        await treeStore.open(saved.current.rootID)
    }

    func observeTreeChanges() async {
        let updates = await treeStore.changes
        for await id in updates {
            await refreshHomeMap()
            guard let map = diskMap.current, map.rootID == id,
                  !isScanningDisk || isReviewingCompletedDiskScan else { continue }
            let root = await treeStore.root(for: id)
            guard diskMap.current?.rootID == id, diskMap.current?.scannedAt == map.scannedAt,
                  !isScanningDisk || isReviewingCompletedDiskScan else { continue }
            if let root {
                diskMap.updateChangeDate(root.changedAt)
            } else if !isReviewingCompletedDiskScan {
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
        diskProgress = nil
        statusMessage = nil
        cancelStorageAnalysis()
        analysisReport = nil
        analysisStatus = nil
        diskMap.restore(map, previous: previous, root: root, url: url)
    }

    func updateTreeApprovals() async {
        await treeStore.setApprovals(Dictionary(uniqueKeysWithValues: accessFolders.map { ($0.id, $0.url) }))
    }

    func rescanMappedFolder(_ relativePath: String) {
        guard canChooseDiskLocation, !relativePath.isEmpty, let url = diskMap.url(for: relativePath) else { return }
        guard let scope = mappingScope(for: url) else {
            presentFolderPicker(initialURL: url, mapAfterApproval: true)
            return
        }
        scanAuthorizedDisk(url: url, scope: scope, spliceAt: relativePath)
    }

    var canRescanDisk: Bool {
        guard canChooseDiskLocation, diskMap.current != nil, let diskURL else { return false }
        return fileAccess.scope(for: diskURL) != nil
    }

    func rescanDisk() {
        guard canRescanDisk, let diskURL else { return }
        scanDisk(url: diskURL)
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

    func approvedMapScope(for url: URL) -> URL? { fileAccess.scope(for: url) }
    func approvedMapFolder(for url: URL) -> RoomAccessFolder? { fileAccess.approval(for: url) }

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
