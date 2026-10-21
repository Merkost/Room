import Foundation
import Testing
@testable import RoomApp

@Suite("Disk Map remembered access") @MainActor
struct RoomInsightsAccessTests {
    @Test func persistedAncestorApprovalCoversDescendantScanAndRescanWithoutAnotherPicker() async throws {
        let suite = "RoomInsightsAccess-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite, isDirectory: true)
        let child = root.appendingPathComponent(".hidden/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 4096).write(to: child.appendingPathComponent("fixture.bin"))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(root)
        let persisted = RoomFileAccess(defaults: defaults)
        let scope = try #require(persisted.folders.first?.url)
        let target = scope.appendingPathComponent(".hidden/nested", isDirectory: true)
        let picks = DiskPickerCalls()
        let insights = RoomInsightsModel(access: persisted, folderPicker: { _, _, _, _ in picks.count += 1; return nil })
        for _ in 0..<2 {
            insights.scanDisk(url: target)
            for _ in 0..<300 where insights.isScanningDisk { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!insights.isScanningDisk)
            let report = try #require(insights.diskReport)
            #expect(report.url.path == target.path)
            #expect(report.fileCount == 1)
            #expect(report.issues.isEmpty)
            #expect(picks.count == 0)
        }
        let outside = root.deletingLastPathComponent().appendingPathComponent(suite + "-other", isDirectory: true)
        insights.scanDisk(url: outside)
        for _ in 0..<30 where picks.count == 0 { await Task.yield() }
        #expect(picks.count == 1)
        #expect(insights.diskURL?.path == target.path)
    }

    @Test func cancellingRememberedHomeApprovalDoesNotInventAHomeGrantOrStartAScan() async throws {
        let suite = "RoomHomeAccess-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = RoomFileAccess(defaults: defaults)
        let picks = DiskPickerCalls()
        let insights = RoomInsightsModel(access: access, folderPicker: { title, message, _, _ in
            picks.count += 1; picks.title = title; picks.message = message
            return nil
        })
        insights.chooseHomeAccess()
        for _ in 0..<30 where picks.count == 0 { await Task.yield() }
        #expect(picks.count == 1)
        #expect(picks.title == "Remember home folder access")
        #expect(picks.message.contains("read-only"))
        #expect(picks.message.contains("macOS may still protect"))
        #expect(access.folders.isEmpty && !insights.hasRememberedHomeAccess)
        #expect(!insights.isScanningDisk && insights.diskReport == nil)
    }
}

@MainActor private final class DiskPickerCalls {
    var count = 0
    var title = ""
    var message = ""
}
