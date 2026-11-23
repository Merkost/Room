import Foundation
import RoomCore
import Testing
@testable import RoomApp

@Suite("Saved Disk Map analysis") @MainActor
struct RoomSavedMapAnalysisTests {
    @Test func analysisUsesSavedMeasurementsWithoutMappingAgain() async throws {
        let suite = "RoomSavedMapAnalysis-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(suite, isDirectory: true)
        let root = directory.appendingPathComponent("Mapped", isDirectory: true)
        let state = directory.appendingPathComponent("State", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(root)
        let approval = try #require(access.folders.first)
        let rootID = "saved-map"
        // The retained item is enough for analysis, even when it no longer exists live.
        let file = RoomTreeNode(name: "Project notes.pdf", relativePath: "Project notes.pdf",
            allocatedBytes: 4096, fileCount: 1, kindBytes: ["documents": 4096], isPartial: false,
            isDirectory: false, children: [], other: nil)
        let tree = RoomTreeNode(name: "Mapped", relativePath: "", allocatedBytes: 4096, fileCount: 1,
            kindBytes: ["documents": 4096], isPartial: false, isDirectory: true, children: [file], other: nil)
        let store = RoomTreeStore(state: RoomStateStore(directory: state))
        let map = RoomStoredTree(rootID: rootID, displayPath: "Mapped",
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000), cancelled: false,
            volumeUUID: nil, issueCount: 0, tree: tree)
        await store.record(map, location: RoomTreeLocation(approvalID: approval.id, relativePath: ""), isHome: false)
        await store.flush()

        let restoredStore = RoomTreeStore(state: RoomStateStore(directory: state))
        let insights = RoomInsightsModel(access: access, treeStore: restoredStore, folderPicker: { _, _, _, _ in
            Issue.record("Analysis must not show a folder picker.")
            return nil
        })
        await insights.restoreDiskMap()
        try #require(insights.diskMap.current != nil)
        #expect(insights.diskReport == nil)
        #expect(insights.canAnalyzeStorage)

        insights.analyzeStorage()
        #expect(insights.isAnalyzingStorage)
        let deadline = ContinuousClock.now + .seconds(10)
        while insights.isAnalyzingStorage && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }

        let result = try #require(insights.analysisReport)
        #expect(result.findings.map(\.item.name) == ["Project notes.pdf"])
        #expect(result.findings.first?.item.allocatedBytes == 4096)
        #expect(result.findings.first?.disposition == .protected)
        #expect(insights.analysisStatus?.contains("saved map") == true)
        #expect(!insights.isAnalyzingStorage && !insights.isScanningDisk && insights.diskReport == nil)
    }

    @Test func stoppingSourceLookupKeepsTheCompletedMap() async throws {
        let fixture = try DiskClassificationFixture()
        defer { fixture.remove() }
        let sourceLookup = DiskClassificationLookup(configuration: fixture.configuration)
        defer { sourceLookup.finish() }
        let insights = fixture.model(lookup: sourceLookup)
        let observer = Task { await insights.observeTreeChanges() }
        defer { observer.cancel() }
        insights.scanDisk(url: fixture.root)
        try #require(insights.isScanningDisk)
        try await waitForDiskState { sourceLookup.isWaiting }
        let measured = try #require(insights.diskReport)
        #expect(insights.isScanningDisk)
        let changedAt = measured.scannedAt.addingTimeInterval(1)
        await insights.treeStore.markChanged(under: fixture.root, at: changedAt)
        try await waitForDiskState { insights.diskMap.changedAt == changedAt }

        insights.cancelDiskScan()
        #expect(!insights.isScanningDisk)
        #expect(insights.diskReport?.id == measured.id)
        #expect(insights.diskMap.current?.cancelled == false)
        #expect(insights.analysisStatus?.contains("complete") == true)
        sourceLookup.finish()
        try await waitForDiskState { sourceLookup.hasReturned }

        #expect(insights.diskReport?.id == measured.id)
        #expect(insights.analysisReport?.findings.first?.disposition == .review)
        #expect(insights.diskMap.changedAt == changedAt)
        await insights.treeStore.flush()
    }

    @Test func resettingResolvedCacheSourcesRejectsThePendingFallback() async throws {
        let fixture = try DiskClassificationFixture()
        defer { fixture.remove() }
        let sourceLookup = DiskClassificationLookup(configuration: fixture.configuration)
        defer { sourceLookup.finish() }
        let insights = fixture.model(lookup: sourceLookup)
        insights.scanDisk(url: fixture.root)
        try #require(insights.isScanningDisk)
        try await waitForDiskState { sourceLookup.isWaiting }
        let measured = try #require(insights.diskReport)

        insights.updateCacheConfiguration(fixture.configuration)
        #expect(insights.analysisReport?.findings.first?.disposition == .cache)
        insights.updateCacheConfiguration(nil)
        sourceLookup.finish()
        try await waitForDiskState { !insights.isScanningDisk }

        #expect(insights.diskReport?.id == measured.id)
        #expect(insights.analysisReport?.findings.first?.disposition == .review)
        await insights.treeStore.flush()
    }

    private func waitForDiskState(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(ready())
    }
}

@MainActor
private struct DiskClassificationFixture {
    let directory: URL
    let root: URL
    let access: RoomFileAccess
    let configuration: CacheConfiguration
    private let suite: String
    private let defaults: UserDefaults

    init() throws {
        let suite = "RoomDiskClassification-\(UUID())"
        self.suite = suite
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(suite, isDirectory: true)
        let candidate = directory.appendingPathComponent("Mapped", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: candidate.appendingPathComponent("download.zip"))
        access = RoomFileAccess(defaults: defaults)
        root = try access.remember(candidate)
        configuration = CacheConfiguration(roots: [
            CacheRoot(id: "fixture", title: "Fixture cache", subtitle: "Fixture", symbol: "folder",
                category: "developer", url: root, consequence: "Fixture")
        ], homeDirectory: root)
    }

    func model(lookup: DiskClassificationLookup) -> RoomInsightsModel {
        RoomInsightsModel(access: access,
            treeStore: RoomTreeStore(state: RoomStateStore(directory: directory.appendingPathComponent("State"))),
            folderPicker: { _, _, _, _ in
                Issue.record("A previously approved test folder must not need another approval.")
                return nil
            },
            capacityReader: { nil }, diskFallbackConfiguration: { _, _ in await lookup.resolve() })
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class DiskClassificationLookup {
    let configuration: CacheConfiguration
    private var pending: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { pending != nil }
    private(set) var hasReturned = false

    init(configuration: CacheConfiguration) { self.configuration = configuration }

    func resolve() async -> CacheConfiguration {
        await withCheckedContinuation { pending = $0 }
        hasReturned = true
        return configuration
    }

    func finish() {
        pending?.resume()
        pending = nil
    }
}
