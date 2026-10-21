#if !ROOM_APP_STORE
import AppKit
import Darwin
import Foundation
import Observation
import RoomCore

@Observable @MainActor
final class AgentWorkModel {
    private(set) var report: AgentWorkReport?
    private(set) var receipts: [AgentWorkReceipt] = []
    private(set) var isScanning = false
    private(set) var isWorking = false
    private(set) var verifyingID: String?
    private(set) var progress: AgentWorkProgress?
    private(set) var statusMessage: String?
    var errorMessage: String?
    private(set) var reviewLocations: [URL] = []
    private(set) var grantedLocations: Set<String> = []

    @ObservationIgnored private let engine: AgentWorkEngine
    @ObservationIgnored private let fileAccess = RoomFileAccess.shared
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var verifyTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var panel: NSOpenPanel?
    @ObservationIgnored private var grants: [(url: URL, scoped: Bool)] = []
    @ObservationIgnored private var reviewKey: String?
    @ObservationIgnored private var reviewGeneration = UUID()

    var items: [AgentWorkItem] {
        (report?.items ?? []).sorted {
            if $0.canReviewForCleanup != $1.canReviewForCleanup { return $0.canReviewForCleanup }
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            return $0.url.path < $1.url.path
        }
    }
    var allLocationsGranted: Bool {
        !reviewLocations.isEmpty && reviewLocations.allSatisfy { grantedLocations.contains($0.path) }
    }

    init(engine: AgentWorkEngine? = nil) { self.engine = engine ?? AgentWorkEngine() }

    func scan() {
        guard !isScanning, !isWorking, verifyingID == nil else { return }
        discardReview()
        let token = UUID()
        generation = token
        isScanning = true
        progress = nil
        statusMessage = nil
        let folders = fileAccess.folders.map(\.url)
        scanTask = Task { [weak self, engine] in
            let scopes = folders.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, scoped) in scopes where scoped { url.stopAccessingSecurityScopedResource() } }
            let result = await engine.scan(approvedProjectRoots: folders) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.isScanning else { return }
                    self.progress = progress
                }
            }
            guard let self, self.generation == token else { return }
            self.report = result
            self.isScanning = false
            self.scanTask = nil
            self.statusMessage = result.cancelled ? "Scan stopped. Partial results stay available for inspection." : nil
            await self.refreshHistory()
        }
    }

    func stop() { scanTask?.cancel(); verifyTask?.cancel() }

    func shutdown() {
        generation = UUID()
        scanTask?.cancel()
        verifyTask?.cancel()
        AgentWorkEngine.shutdownOwnedCommands()
        discardReview()
    }

    func verify(_ item: AgentWorkItem) {
        guard !isWorking, !isScanning, verifyingID == nil else { return }
        verifyingID = item.id
        let token = generation
        let scopes = beginReadAccess()
        verifyTask = Task { [weak self, engine] in
            defer { Self.endReadAccess(scopes) }
            let result = await engine.verifyRemote(worktreeID: item.id)
            guard let self, self.generation == token else { return }
            if let index = self.report?.items.firstIndex(where: { $0.id == item.id }),
               self.report?.items[index].head == result.head || result.head == nil {
                self.report?.items[index].pushVerification = result
            }
            self.verifyingID = nil
            self.verifyTask = nil
        }
    }

    func refreshHistory() async { receipts = await engine.history() }

    func addProject() {
        guard panel == nil, !isWorking, !isScanning, verifyingID == nil else { return }
        let chooser = NSOpenPanel()
        panel = chooser
        chooser.title = "Allow Room to inspect a repository"
        chooser.message = "Choose a Git repository. Room checks its worktrees and observed process use. Scanning never contacts remotes or removes work."
        chooser.prompt = "Allow & Scan"
        configure(chooser)
        present(chooser) { [weak self, weak chooser] response in
            guard let self else { return }
            self.panel = nil
            guard response == .OK, let url = chooser?.url else { return }
            do {
                _ = try self.fileAccess.remember(url)
                self.scan()
            } catch { self.errorMessage = "Folder access could not be saved. \(error.localizedDescription)" }
        }
    }

    func prepareReview(_ item: AgentWorkItem) async {
        guard !isWorking, !isScanning else { return }
        discardReview()
        errorMessage = nil
        let token = reviewGeneration
        let scopes = beginReadAccess()
        defer { Self.endReadAccess(scopes) }
        do {
            let locations = try await engine.authorizationLocations(worktreeID: item.id)
            guard reviewGeneration == token else { return }
            reviewLocations = locations
            reviewKey = "clean:\(item.id)"
        } catch { if reviewGeneration == token { errorMessage = error.localizedDescription } }
    }

    func prepareRestore(_ receipt: AgentWorkReceipt) async {
        guard !isWorking, !isScanning else { return }
        discardReview()
        errorMessage = nil
        reviewLocations = [receipt.originalURL.deletingLastPathComponent(), receipt.adminURL]
        reviewKey = "restore:\(receipt.id.uuidString)"
    }

    func allow(_ expected: URL) async {
        guard !isWorking, panel == nil, reviewLocations.contains(where: { $0.path == expected.path }) else { return }
        isWorking = true
        defer { isWorking = false }
        let selected = await chooseWritableFolder(expected)
        guard let selected else { return }
        guard Self.samePhysicalDirectory(selected, expected) else {
            errorMessage = "Choose the exact folder shown in this review. Nothing has moved."
            return
        }
        // This grant lives only through this review; no writable bookmark is saved.
        let scoped = selected.startAccessingSecurityScopedResource()
        grants.append((selected, scoped))
        grantedLocations.insert(expected.path)
    }

    func moveToTrash(_ item: AgentWorkItem, confirmsFinished: Bool) async -> Bool {
        guard !isWorking, !isScanning, confirmsFinished, allLocationsGranted,
              reviewKey == "clean:\(item.id)" else { return false }
        isWorking = true
        let scopes = beginReadAccess()
        defer { Self.endReadAccess(scopes); isWorking = false; discardReview() }
        do {
            let receipt = try await engine.clean(worktreeID: item.id, confirmsFinished: confirmsFinished)
            await refreshHistory()
            statusMessage = receipt.detail
            guard receipt.status == .trashed else { return false }
            report?.items.removeAll { $0.id == item.id }
            return true
        } catch { errorMessage = error.localizedDescription; await refreshHistory(); return false }
    }

    func restoreReviewed(_ receipt: AgentWorkReceipt) async -> Bool {
        guard !isWorking, !isScanning, allLocationsGranted,
              reviewKey == "restore:\(receipt.id.uuidString)" else { return false }
        isWorking = true
        let scopes = beginReadAccess()
        defer { Self.endReadAccess(scopes); isWorking = false; discardReview() }
        do {
            let restored = try await engine.restore(receiptID: receipt.id)
            await refreshHistory()
            statusMessage = restored.detail
            return restored.status == .restored
        } catch { errorMessage = error.localizedDescription; await refreshHistory(); return false }
    }

    func discardReview() {
        guard !isWorking else { return }
        reviewGeneration = UUID()
        for grant in grants where grant.scoped { grant.url.stopAccessingSecurityScopedResource() }
        grants = []
        grantedLocations = []
        reviewLocations = []
        reviewKey = nil
    }

    private func chooseWritableFolder(_ expected: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let chooser = NSOpenPanel()
            panel = chooser
            chooser.title = "Allow this worktree operation"
            chooser.message = "Choose exactly \(expected.path). This is temporary write access for the reviewed operation. Allowing access does not move files."
            chooser.prompt = "Allow This Folder"
            configure(chooser)
            chooser.directoryURL = expected
            present(chooser) { [weak self, weak chooser] response in
                self?.panel = nil
                continuation.resume(returning: response == .OK ? chooser?.url : nil)
            }
        }
    }

    private func beginReadAccess() -> [(URL, Bool)] {
        fileAccess.folders.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
    }

    private static func endReadAccess(_ scopes: [(URL, Bool)]) {
        for (url, scoped) in scopes where scoped { url.stopAccessingSecurityScopedResource() }
    }

    private func configure(_ chooser: NSOpenPanel) {
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false
        chooser.canCreateDirectories = false
        chooser.showsHiddenFiles = true
    }

    private func present(_ chooser: NSOpenPanel, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if var presenter = NSApp.windows.first(where: { $0.identifier?.rawValue == "RoomPrimaryWindow" && $0.isVisible }) {
            while let attached = presenter.attachedSheet { presenter = attached }
            chooser.beginSheetModal(for: presenter, completionHandler: completion)
        } else { chooser.begin(completionHandler: completion) }
    }

    private static func samePhysicalDirectory(_ first: URL, _ second: URL) -> Bool {
        var a = stat(), b = stat()
        guard lstat(first.path, &a) == 0, lstat(second.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == getuid() && b.st_uid == getuid()
            && a.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) && b.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR)
    }
}

#endif
