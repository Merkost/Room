import Foundation
import Synchronization
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Developer: one scan fills every section") @MainActor
struct RoomDeveloperScanAllTests {
    @Test("One scan from any section reads every section that has a folder")
    func oneScanReadsEverySection() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let scopes = Mutex<[DeveloperResourcesScope]>([])
        let model = fixture.model { request, _ in
            scopes.withLock { $0.append(request.scope) }
            return ScanAllFixture.report()
        }
        for role in [RoomDeveloperFolderRole.project, .android, .gradle, .codex] { model.attach(role: role, to: fixture.folderID) }
        model.section = .aiTools

        model.scan()
        try await wait { !model.isScanning }

        #expect(scopes.withLock { $0 } == [.review, .devices, .toolStorage, .aiTools])
        #expect(model.report != nil)
        #expect(model.devicesReport != nil)
        #expect(model.storageReport != nil)
        #expect(model.aiToolsReport != nil)
        #expect(model.progress == "Review complete")
    }

    @Test("A section with no folder is skipped, and the scan is offered from every section")
    func sectionsWithoutFoldersAreSkipped() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let scopes = Mutex<[DeveloperResourcesScope]>([])
        let model = fixture.model { request, _ in
            scopes.withLock { $0.append(request.scope) }
            return ScanAllFixture.report()
        }
        #expect(!model.canScan)
        #expect(!model.hasScannableFolders)
        model.attach(role: .codex, to: fixture.folderID)
        for section in RoomDeveloperSection.allCases {
            model.section = section
            #expect(model.canScan)
        }
        model.section = .rooms

        model.scan()
        try await wait { !model.isScanning }

        #expect(scopes.withLock { $0 } == [.aiTools])
        #expect(model.report == nil)
        #expect(model.aiToolsReport != nil)
    }

    @Test("Stop ends the whole scan, not just the section being read")
    func stopSkipsTheRemainingSections() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let gate = ScanAllGate()
        let scopes = Mutex<[DeveloperResourcesScope]>([])
        let model = fixture.model { request, _ in
            scopes.withLock { $0.append(request.scope) }
            await gate.wait()
            return ScanAllFixture.report(cancelled: Task.isCancelled)
        }
        for role in [RoomDeveloperFolderRole.project, .android, .codex] { model.attach(role: role, to: fixture.folderID) }

        model.scan()
        try await wait { scopes.withLock { $0.count } == 1 }
        model.stop()
        await gate.open()
        try await wait { !model.isScanning }

        #expect(scopes.withLock { $0 } == [.review])
        #expect(model.report?.cancelled == true)
        #expect(model.devicesReport == nil)
        #expect(model.aiToolsReport == nil)
        #expect(model.progress == "Stopped · partial review")
    }

    @Test("Worktrees start and stop with the same scan")
    func worktreesJoinTheScan() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let worktrees = ScanAllWorktrees()
        let model = fixture.model { _, _ in ScanAllFixture.report() }
        model.worktrees = worktrees
        #expect(model.canScan)
        #expect(!model.hasScannableFolders)

        model.scan()

        #expect(worktrees.scans == 1)
        #expect(model.isScanning)
        #expect(model.progress == "Reading agent worktrees…")
        model.scan()
        #expect(worktrees.scans == 1)
        model.stop()
        #expect(worktrees.stops == 1)
        try await wait { !model.isScanning }
    }

    @Test("The scan, and its activity pill, last until the worktrees are read too")
    func scanOutlastsTheFolderParts() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let worktrees = ScanAllWorktrees()
        let center = RoomActivityCenter()
        let model = fixture.model(activityCenter: center) { _, _ in ScanAllFixture.report() }
        model.worktrees = worktrees
        model.attach(role: .project, to: fixture.folderID)

        model.scan()
        try await wait { model.report != nil && model.progress == "Reading agent worktrees…" }
        #expect(model.isScanning)
        #expect(showsDeveloperScan(center))

        #expect(model.scanTiles.map(\.title) == ["Projects", "Worktrees"])
        #expect(model.scanTiles.map(\.state) == [.done, .reading(fraction: nil)])

        worktrees.measuredBytes = 9_000_000_000
        worktrees.finish()
        try await wait { !model.isScanning }
        #expect(model.scanTiles.last?.value == RoomFormat.gb(9_000_000_000))
        #expect(model.progress == "Review complete")
        #expect(!showsDeveloperScan(center))
    }

    @Test("A running remote check or move holds the scan back instead of silently skipping worktrees")
    func busyWorktreesHoldTheScan() throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let worktrees = ScanAllWorktrees()
        let model = fixture.model { _, _ in ScanAllFixture.report() }
        model.worktrees = worktrees
        model.attach(role: .project, to: fixture.folderID)
        worktrees.isBusy = true

        #expect(!model.canScan)
        model.scan()
        #expect(!model.isScanning)
        #expect(worktrees.scans == 0)
    }

    @Test("Approving another folder mid-scan keeps the scan; losing a folder it reads ends it")
    func unrelatedApprovalKeepsTheScan() async throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let gate = ScanAllGate()
        let model = fixture.model { _, _ in
            await gate.wait()
            return ScanAllFixture.report()
        }
        model.attach(role: .project, to: fixture.folderID)
        model.scan()

        let other = fixture.root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try fixture.access.remember(other)
        model.accessChanged()
        #expect(model.isScanning)

        fixture.access.forget(id: fixture.folderID)
        model.accessChanged()
        #expect(!model.isScanning)
        #expect(model.scanParts.isEmpty)
        await gate.open()
    }

    @Test("Rooms has nothing to scan when the only folder is Simulator Devices")
    func simulatorsDoNotFeedRooms() throws {
        let fixture = try ScanAllFixture()
        defer { fixture.remove() }
        let model = fixture.model { _, _ in ScanAllFixture.report() }
        model.attach(role: .simulators, to: fixture.folderID)
        #expect(!model.hasFoldersForSection)
        model.section = .devices
        #expect(model.hasFoldersForSection)
    }

    private func showsDeveloperScan(_ center: RoomActivityCenter) -> Bool {
        if case .scanning(tool: .developer, _, _, _) = center.visible { return true }
        return false
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
}

@MainActor private final class ScanAllWorktrees: RoomDeveloperWorktreeScanning {
    private(set) var isScanning = false
    private(set) var scans = 0
    private(set) var stops = 0
    var isBusy = false
    var measuredBytes: Int64?
    private var waiter: CheckedContinuation<Void, Never>?
    func scan() { scans += 1; isScanning = true }
    func stop() { stops += 1; finish() }
    func finish() { isScanning = false; waiter?.resume(); waiter = nil }
    func waitForScan() async {
        guard isScanning else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor ScanAllGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume(); continuation = nil
    }
}

@MainActor private struct ScanAllFixture {
    let name = "RoomDeveloperScanAll-" + UUID().uuidString
    let root: URL
    let defaults: UserDefaults
    let access: RoomFileAccess
    let folderID: String

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/" + name, isDirectory: true)
        defaults = try #require(UserDefaults(suiteName: name))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(root)
        folderID = try #require(access.folders.first).id
    }

    func model(activityCenter: RoomActivityCenter? = nil, _ scanner: @escaping @Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport) -> RoomDeveloperModel {
        RoomDeveloperModel(access: access, defaults: defaults, unreferencedStore: .init(directory: root),
            activityCenter: activityCenter, scanner: scanner)
    }

    nonisolated static func report(cancelled: Bool = false) -> DeveloperResourcesReport {
        DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], issues: [], cancelled: cancelled, isPartial: cancelled)
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: root)
    }
}
