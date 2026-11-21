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
}
