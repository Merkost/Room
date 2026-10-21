import AppKit
import Foundation
import Observation
import RoomCore

@Observable
@MainActor
final class RoomInsightsModel {
    private(set) var memoryReport: MemoryReport?
    private(set) var isScanningMemory = false
    private(set) var diskReport: DiskMapReport?
    private(set) var isScanningDisk = false
    private(set) var diskProgress: DiskScanProgress?
    private(set) var diskURL: URL?
    private(set) var statusMessage: String?
    var accessFolders: [RoomAccessFolder] { fileAccess.folders }
    var accessNote: String? { fileAccess.note }
    private(set) var analysisReport: StorageAnalysisReport?
    private(set) var isAnalyzingStorage = false
    private(set) var analysisStatus: String?
    private(set) var diskAvailableBytes: Int64 = 0
    private(set) var diskCapacityBytes: Int64 = 0
    var requestedDestination: RoomInsightDestination?

    @ObservationIgnored private let memoryEngine = MemoryEngine()
    @ObservationIgnored private let diskEngine = DiskMapEngine()
    @ObservationIgnored private let storageAI = StorageAIEngine()
    @ObservationIgnored private let fileAccess: RoomFileAccess
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private var memoryTask: Task<Void, Never>?
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    @ObservationIgnored private var diskGeneration = UUID()
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    init(access: RoomFileAccess = .shared,
         folderPicker: (@MainActor (String, String, String, URL?) async -> URL?)? = nil) {
        self.fileAccess = access
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
        memoryTask = Task { [weak self, memoryEngine] in
            let result = await memoryEngine.scan()
            guard let self else { return }
            self.memoryReport = result
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
        diskTask?.cancel()
        cancelStorageAnalysis()
        analysisReport = nil
        analysisStatus = nil
        let generation = UUID()
        diskGeneration = generation
        diskURL = url
        diskReport = nil
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
            let result = await diskEngine.scan(url: url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.diskGeneration == generation, self.isScanningDisk else { return }
                    self.diskProgress = progress
                }
            }
            guard let self, self.diskGeneration == generation else { return }
            self.diskReport = result
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
            isScanningDisk = false
        }
        fileAccess.forget(id: id)
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
        if !NSWorkspace.shared.open(url) { statusMessage = "Activity Monitor could not be opened." }
    }

    func activateProcess(id: Int32) {
        if let application = NSRunningApplication(processIdentifier: id),
           !application.isTerminated, application.activate() { return }
        openActivityMonitor()
    }
}
