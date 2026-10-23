import Foundation
@testable import RoomCore
import Synchronization
import Testing
@testable import RoomApp

@Suite("Disk browser navigation and evidence") @MainActor
struct RoomDiskNavigationTests {
    @Test("Back and Forward restore measured maps, analysis and browser context without new scans")
    func snapshotsRestoreWithoutTraversal() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let calls = Mutex(0)
        let engine = DiskMapEngine()
        let model = RoomInsightsModel(access: f.access, diskScanner: { url, progress in
            calls.withLock { $0 += 1 }
            return await engine.scan(url: url, progress: progress)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        let parent = try #require(model.diskReport)
        let parentAnalysis = try #require(model.analysisReport)
        model.diskBrowserState.scope = .hidden
        model.diskBrowserState.category = .archives
        model.diskBrowserState.query = "download"
        model.diskBrowserState.listMode = .largest
        model.diskBrowserState.sort = .name
        let context = model.diskBrowserState
        model.scanDisk(url: f.child)
        try await settle(model)
        let child = try #require(model.diskReport)
        #expect(model.canGoBack && !model.canGoForward)
        model.diskGoBack()
        #expect(model.diskReport?.id == parent.id)
        #expect(model.analysisReport?.id == parentAnalysis.id)
        #expect(model.diskBrowserState == context)
        #expect(calls.withLock { $0 } == 2)
        model.diskGoForward()
        #expect(model.diskReport?.id == child.id)
        #expect(calls.withLock { $0 } == 2)
        model.rescanDisk()
        try await settle(model)
        #expect(calls.withLock { $0 } == 3)
        #expect(model.diskReport?.id != child.id)
    }

    @Test("A late cancelled scan cannot replace a restored snapshot or its analysis")
    func lateScanCannotOverwriteBack() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let gate = DeferredDiskNavigationScan()
        let engine = DiskMapEngine()
        let model = RoomInsightsModel(access: f.access, diskScanner: { url, progress in
            if url.path == f.child.path { return await gate.scan(url) }
            return await engine.scan(url: url, progress: progress)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        let original = try #require(model.diskReport)
        model.scanDisk(url: f.child)
        for _ in 0..<1000 { if await gate.started { break }; await Task.yield() }
        #expect(await gate.started)
        model.updateCacheConfiguration(CacheConfiguration(roots: [CacheRoot(id: "history-policy-fixture", title: "Fixture cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: f.root, consequence: "Owned fixture")], homeDirectory: f.root))
        model.diskGoBack()
        #expect(model.analysisReport?.findings.first?.disposition == .cache)
        #expect(!model.isScanningDisk)
        #expect(model.diskReport?.id == original.id)
        await gate.finish()
        for _ in 0..<100 { await Task.yield() }
        #expect(model.diskReport?.id == original.id)
        #expect(model.analysisReport?.scanID == original.id)
        #expect(!model.isScanningDisk)
    }

    @Test("Clean's resolved catalogue updates Disk classification without another filesystem scan")
    func actualCleanRulesRemainConsistent() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let calls = Mutex(0)
        let engine = DiskMapEngine()
        let model = RoomInsightsModel(access: f.access, diskScanner: { url, progress in
            calls.withLock { $0 += 1 }
            return await engine.scan(url: url, progress: progress)
        })
        model.scanDisk(url: f.child)
        try await settle(model)
        let report = try #require(model.diskReport)
        let configuration = CacheConfiguration(roots: [CacheRoot(id: "full-only-fixture", title: "Exact cache", subtitle: "Fixture", symbol: "shippingbox",
            category: "developer", url: f.child, consequence: "Owned fixture")], homeDirectory: f.root)
        let expected = StorageAnalyzer.analyze(report: report, configuration: configuration)
        model.updateCacheConfiguration(configuration)
        #expect(model.diskReport?.id == report.id)
        #expect(model.analysisReport?.findings == expected.findings)
        #expect(model.analysisReport?.findings.contains { $0.disposition == .cache } == true)
        #expect(calls.withLock { $0 } == 1)
        model.requestCleanReview(path: f.child.path)
        #expect(model.requestedCleanPath == f.child.path)
        #expect(model.requestedDestination == .clean)
    }

    @Test("A Clean catalogue arriving during fallback resolution owns current and cached classifications")
    func cleanSnapshotWinsSuspendedFallback() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let gate = DeferredDiskFallback(home: f.root)
        let model = RoomInsightsModel(access: f.access, fallbackConfigurationProvider: { _, root in
            await gate.configuration(for: root)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        model.scanDisk(url: f.child)
        try await gate.waitUntilStarted()
        #expect(model.isScanningDisk && model.diskReport == nil)
        let clean = CacheConfiguration(roots: [CacheRoot(id: "new-clean-fixture", title: "Resolved cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: f.root,
            consequence: "Owned fixture")], homeDirectory: f.root)
        model.updateCacheConfiguration(clean)
        await gate.finish()
        try await settle(model)
        let childID = try #require(model.diskReport?.id)
        #expect(model.analysisReport?.findings.allSatisfy { $0.disposition == .cache } == true)
        #expect(model.analysisReport?.findings.isEmpty == false)
        model.diskGoBack()
        #expect(model.analysisReport?.findings.first?.disposition == .cache)
        model.diskGoForward()
        #expect(model.diskReport?.id == childID)
        #expect(model.analysisReport?.findings.allSatisfy { $0.disposition == .cache } == true)
        #expect(await gate.calls == 2)
    }

    @Test("An explicit catalogue reset during fallback cannot revive older policy")
    func catalogueResetWinsSuspendedFallback() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let gate = DeferredDiskFallback(home: f.root)
        let model = RoomInsightsModel(access: f.access, fallbackConfigurationProvider: { _, root in
            await gate.configuration(for: root)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        model.scanDisk(url: f.child)
        try await gate.waitUntilStarted()
        let obsolete = CacheConfiguration(roots: [CacheRoot(id: "obsolete-cache-fixture", title: "Obsolete cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: f.root,
            consequence: "Owned fixture")], homeDirectory: f.root)
        model.updateCacheConfiguration(obsolete)
        model.updateCacheConfiguration(nil)
        await gate.finish(configuration: obsolete)
        try await settle(model)
        #expect(!model.usesCleanClassification)
        #expect(model.analysisReport?.findings.isEmpty == false)
        #expect(model.analysisReport?.findings.allSatisfy { $0.disposition == .review } == true)
    }

    @Test("Stop during source fallback keeps completed measurements and rejects the late classification")
    func stopDuringFallbackKeepsMeasurement() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let gate = DeferredDiskFallback(home: f.root)
        let model = RoomInsightsModel(access: f.access, fallbackConfigurationProvider: { _, root in
            await gate.configuration(for: root)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        let parentID = try #require(model.diskReport?.id)
        model.scanDisk(url: f.child)
        try await gate.waitUntilStarted()
        #expect(model.isScanningDisk && model.diskReport == nil)

        model.cancelDiskScan()
        #expect(!model.isScanningDisk)
        let measured = try #require(model.diskReport)
        #expect(measured.url.path == f.child.path)
        #expect(measured.fileCount == 1 && measured.allocatedBytes > 0)
        #expect(!measured.cancelled && !measured.isPartial)
        #expect(model.diskStatusMessage?.contains("stopped") == true)
        #expect(model.analysisReport?.findings.allSatisfy { $0.disposition == .review } == true)

        // Leave the old cancelled provider suspended while restoring both maps.
        model.diskGoBack()
        #expect(model.diskReport?.id == parentID)
        model.diskGoForward()
        #expect(model.diskReport?.id == measured.id)
        let stoppedStatus = model.diskStatusMessage
        let obsolete = CacheConfiguration(roots: [CacheRoot(id: "cancelled-cache-fixture", title: "Obsolete cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: f.root,
            consequence: "Owned fixture")], homeDirectory: f.root)
        await gate.finish(configuration: obsolete)
        try await gate.waitUntilResumed()
        #expect(await gate.resumedAfterCancellation)
        #expect(model.diskReport?.id == measured.id)
        #expect(model.diskStatusMessage == stoppedStatus)
        #expect(model.analysisReport?.findings.allSatisfy { $0.disposition == .review } == true)
        model.rescanDisk()
        try await settle(model)
        #expect(model.diskReport?.id != measured.id)
        #expect(model.diskStatusMessage == nil)
        #expect(await gate.calls == 3)
        #expect(FileManager.default.fileExists(atPath: f.child.appendingPathComponent(".download.zip").path))
    }

    @Test("Stopped analysis cannot replace a newer Analyze result on the same map")
    func stoppedAnalysisCannotReplaceNewResult() async throws {
        let f = try DiskNavigationFixture()
        defer { f.remove() }
        let gate = DeferredDiskAnalysis()
        let model = RoomInsightsModel(access: f.access, analyzer: { report, configuration in
            await gate.analyze(report, configuration: configuration)
        })
        model.scanDisk(url: f.root)
        try await settle(model)
        model.analyzeStorage()
        for _ in 0..<1000 { if await gate.count == 1 { break }; await Task.yield() }
        #expect(await gate.count == 1)
        model.cancelStorageAnalysis()
        #expect(!model.isAnalyzingStorage)
        model.analyzeStorage()
        for _ in 0..<1000 { if await gate.count == 2 { break }; await Task.yield() }
        #expect(await gate.count == 2)
        await gate.finish(index: 1, reason: "New fixture result")
        for _ in 0..<1000 where model.isAnalyzingStorage { await Task.yield() }
        #expect(model.analysisStatus == "New fixture result")
        let accepted = model.analysisReport?.id
        await gate.finish(index: 0, reason: "Old stopped result")
        for _ in 0..<100 { await Task.yield() }
        #expect(model.analysisStatus == "New fixture result")
        #expect(model.analysisReport?.id == accepted)
        #expect(!model.isAnalyzingStorage)
    }

    @Test("Category, hidden scope, query, sorting and list source are independent and preserve honest empties")
    func independentFilters() {
        let root = URL(fileURLWithPath: "/private/tmp/Room-DiskFilter-Fixture")
        let mixed = DiskMapItem(url: root.appendingPathComponent("mixed"), name: "mixed", isDirectory: true,
            allocatedBytes: 1000, logicalBytes: 1000, fileCount: 3,
            categoryAllocatedBytes: [.documents: 200, .archives: 800], hiddenAllocatedBytes: 300,
            hiddenCategoryAllocatedBytes: [.documents: 100, .archives: 200])
        let hidden = DiskMapItem(url: root.appendingPathComponent(".download.zip"), name: ".download.zip", isDirectory: false,
            allocatedBytes: 50, logicalBytes: 50, fileCount: 1, isHidden: true,
            categoryAllocatedBytes: [.archives: 50], hiddenAllocatedBytes: 50, hiddenCategoryAllocatedBytes: [.archives: 50])
        let report = DiskMapReport(id: UUID(), url: root, scannedAt: Date(), children: [mixed, hidden], largestFiles: [hidden],
            allocatedBytes: 1050, logicalBytes: 1050, fileCount: 4, issues: [], cancelled: false, isPartial: false)
        var browser = RoomDiskBrowserState()
        browser.scope = .hidden; browser.category = .archives
        #expect(browser.total(in: report) == 250)
        #expect(browser.items(in: report).count == 2)
        browser.query = "download"
        #expect(browser.total(in: report) == 50)
        #expect(browser.items(in: report).map(\.name) == [".download.zip"])
        browser.query = "missing"; browser.listMode = .largest
        #expect(browser.items(in: report).isEmpty)
        browser.query = ""; browser.listMode = .contents; browser.sort = .name
        #expect(browser.items(in: report).map(\.name) == [".download.zip", "mixed"])
        #expect(browser.scope == .hidden && browser.category == .archives)
    }

    private func settle(_ model: RoomInsightsModel) async throws {
        for _ in 0..<1000 where model.isScanningDisk { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isScanningDisk)
    }
}

private struct DiskNavigationFixture: Sendable {
    let root: URL
    let child: URL
    let suite: String
    @MainActor let access: RoomFileAccess
    @MainActor init() throws {
        suite = "RoomDiskNavigation-" + UUID().uuidString
        root = URL(fileURLWithPath: "/private/tmp/" + suite, isDirectory: true)
        child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 4096).write(to: child.appendingPathComponent(".download.zip"))
        access = RoomFileAccess(defaults: UserDefaults(suiteName: suite)!)
        _ = try access.remember(root)
    }
    @MainActor func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
private actor DeferredDiskNavigationScan {
    private var continuation: CheckedContinuation<DiskMapReport, Never>?
    private var url: URL?
    private(set) var started = false
    func scan(_ url: URL) async -> DiskMapReport {
        self.url = url; started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        guard let url else { return }
        continuation?.resume(returning: DiskMapReport(id: UUID(), url: url, scannedAt: Date(), children: [], largestFiles: [],
            allocatedBytes: 0, logicalBytes: 0, fileCount: 0, issues: [], cancelled: true, isPartial: true))
        continuation = nil
    }
}

private actor DeferredDiskAnalysis {
    struct Pending {
        let baseline: StorageAnalysisReport
        let continuation: CheckedContinuation<StorageAnalysisReport, Never>
    }
    private var pending: [Pending?] = []
    var count: Int { pending.count }
    func analyze(_ report: DiskMapReport, configuration: CacheConfiguration) async -> StorageAnalysisReport {
        let baseline = StorageAnalyzer.analyze(report: report, configuration: configuration)
        return await withCheckedContinuation { pending.append(Pending(baseline: baseline, continuation: $0)) }
    }
    func finish(index: Int, reason: String) {
        guard pending.indices.contains(index), let item = pending[index] else { return }
        let baseline = item.baseline
        item.continuation.resume(returning: StorageAnalysisReport(id: UUID(), scanID: baseline.scanID,
            generatedAt: Date(), findings: baseline.findings, source: .ruleBased,
            availability: StorageAIAvailability(isAvailable: false, reason: reason), summary: baseline.summary))
        pending[index] = nil
    }
}

private actor DeferredDiskFallback {
    let home: URL
    let suspendedCall: Int
    private var continuation: CheckedContinuation<CacheConfiguration, Never>?
    private(set) var started = false
    private(set) var calls = 0
    private(set) var resumedAfterCancellation = false
    private var resumed = false
    private var released = false
    private var releasedConfiguration: CacheConfiguration?
    private var waiters: [UUID: (resumption: Bool, continuation: CheckedContinuation<Bool, Never>)] = [:]

    init(home: URL, suspendedCall: Int = 2) { self.home = home; self.suspendedCall = suspendedCall }

    func configuration(for root: URL) async -> CacheConfiguration {
        calls += 1
        // The model passes its approved ancestor as the fallback root. Gate the
        // intended second request rather than assuming the target equals scope.
        if calls != suspendedCall { return CacheConfiguration(roots: [], homeDirectory: home) }
        started = true
        signal(resumption: false)
        let configuration = await withCheckedContinuation { (continuation: CheckedContinuation<CacheConfiguration, Never>) in
            if released { continuation.resume(returning: releasedConfiguration ?? CacheConfiguration(roots: [], homeDirectory: home)) }
            else { self.continuation = continuation }
        }
        resumedAfterCancellation = Task.isCancelled
        resumed = true
        signal(resumption: true)
        return configuration
    }

    func finish(configuration: CacheConfiguration? = nil) {
        released = true
        releasedConfiguration = configuration
        continuation?.resume(returning: configuration ?? CacheConfiguration(roots: [], homeDirectory: home))
        continuation = nil
    }

    func waitUntilStarted() async throws { try await wait(resumption: false) }
    func waitUntilResumed() async throws { try await wait(resumption: true) }

    private func wait(resumption: Bool) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    guard await self.waitForSignal(resumption: resumption) else { throw CancellationError() }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw DiskFallbackGateError.timedOut
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            // A failed test must not leave the fixture task's checked
            // continuation suspended for the rest of the aggregate suite.
            finish()
            throw error
        }
    }

    private func waitForSignal(resumption: Bool) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if (resumption ? resumed : started) { continuation.resume(returning: true) }
                else if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters[id] = (resumption, continuation) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.continuation.resume(returning: false) }

    private func signal(resumption: Bool) {
        for id in waiters.keys.filter({ waiters[$0]?.resumption == resumption }) {
            waiters.removeValue(forKey: id)?.continuation.resume(returning: true)
        }
    }
}

private enum DiskFallbackGateError: Error { case timedOut }
