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
        let treeStore = RoomTreeStore(state: RoomStateStore(directory: root.appendingPathComponent("Test State")))
        let insights = RoomInsightsModel(access: persisted, treeStore: treeStore,
            folderPicker: { _, _, _, _ in picks.count += 1; return nil })
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
        await treeStore.flush()
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

    @Test func cancellingTheHomeScopeConfirmationDoesNotRememberOrScanIt() async throws {
        let suite = "RoomHomeConsent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #if ROOM_APP_STORE
        let home = try #require(RoomStoreEnvironment.userHome)
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        #endif
        let access = RoomFileAccess(defaults: defaults)
        let calls = DiskPickerCalls()
        let insights = RoomInsightsModel(access: access, folderPicker: { _, _, _, _ in home },
            confirmHomeMap: {
                calls.count += 1
                return false
            })

        insights.scanHome()
        #expect(insights.isChoosingDiskFolder && !insights.isScanningDisk)
        let deadline = ContinuousClock.now + .seconds(5)
        while insights.isChoosingDiskFolder && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls.count == 1)
        #expect(!insights.isChoosingDiskFolder && !insights.isScanningDisk)
        #expect(access.folders.isEmpty && insights.diskMap.current == nil && insights.requestedDestination == nil)
    }

    @Test func openingAnUnmappedApprovalWaitsForExplicitMapAndAllowsRescan() async throws {
        let suite = "RoomOpenMap-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(suite, isDirectory: true)
        let folder = root.appendingPathComponent("Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([0x43]).write(to: folder.appendingPathComponent("sample.bin"))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let access = RoomFileAccess(defaults: defaults)
        let approved = try access.remember(folder)
        let picks = DiskPickerCalls()
        let insights = RoomInsightsModel(access: access,
            treeStore: RoomTreeStore(state: RoomStateStore(directory: root.appendingPathComponent("State"))),
            folderPicker: { _, _, _, _ in
                picks.count += 1
                return nil
            })

        insights.openDiskMap(rootURL: approved, requestNavigation: false)
        let deadline = ContinuousClock.now + .seconds(5)
        while insights.diskMap.pendingFolder == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(insights.diskMap.pendingFolder == approved)
        #expect(insights.diskReport == nil && !insights.isScanningDisk)
        #expect(!insights.canRescanDisk)

        insights.scanDisk(url: approved)
        #expect(insights.isScanningDisk && !insights.canChooseDiskLocation)
        let scanDeadline = ContinuousClock.now + .seconds(10)
        while insights.isScanningDisk && ContinuousClock.now < scanDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(insights.diskReport?.fileCount == 1)
        #expect(insights.diskMap.pendingFolder == nil)
        #expect(insights.canRescanDisk)

        insights.rescanDisk()
        #expect(insights.isScanningDisk)
        let rescanDeadline = ContinuousClock.now + .seconds(10)
        while insights.isScanningDisk && ContinuousClock.now < rescanDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!insights.isScanningDisk && insights.canRescanDisk)
        #expect(insights.diskReport?.fileCount == 1)
        #expect(picks.count == 0)
        await insights.treeStore.flush()
    }

    @Test func mapYourMacShowsDiskMapWhenThePickerApprovesAnotherFolder() async throws {
        let suite = "RoomMapYourMac-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        let folder = directory.appendingPathComponent("Example", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 4096).write(to: folder.appendingPathComponent("test-data.bin"))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let calls = DiskPickerCalls()
        let insights = RoomInsightsModel(access: RoomFileAccess(defaults: defaults),
            treeStore: RoomTreeStore(state: RoomStateStore(directory: directory.appendingPathComponent("State"))),
            folderPicker: { _, _, _, _ in
                calls.count += 1
                try? await Task.sleep(for: .milliseconds(25))
                return folder
            })
        insights.scanHome()
        insights.scanHome()

        let deadline = ContinuousClock.now + .seconds(10)
        while (insights.diskReport == nil || insights.isScanningDisk) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls.count == 1)
        #expect(insights.requestedDestination == .disk)
        #expect(insights.diskReport?.url.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(insights.diskReport?.fileCount == 1)
    }
}

@Suite("Onboarding: Map my home folder") @MainActor
struct RoomOnboardingMapHomeTests {
    private var home: URL {
        get throws {
            #if ROOM_APP_STORE
            try #require(RoomStoreEnvironment.userHome)
            #else
            FileManager.default.homeDirectoryForCurrentUser
            #endif
        }
    }

    /// D-ONV-8: the "Map your Home folder?" alert is skipped only when the person chose it in onboarding.
    @Test func mapHomeSkipsSecondConfirmOnlyFromOnboarding() async throws {
        let home = try home
        for confirmed in [false, true] {
            let suite = "RoomOnboardingMapHome-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let state = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            defer {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: state)
            }
            let confirms = DiskPickerCalls()
            let picks = DiskPickerCalls()
            let insights = RoomInsightsModel(access: RoomFileAccess(defaults: defaults),
                treeStore: RoomTreeStore(state: RoomStateStore(directory: state)),
                folderPicker: { _, _, _, _ in picks.count += 1; return home },
                confirmHomeMap: { confirms.count += 1; return false })

            insights.scanHome(confirmed: confirmed)
            #expect(await RoomTestWait.until { !insights.isChoosingDiskFolder })
            #expect(picks.count == 1)
            #expect(confirms.count == (confirmed ? 0 : 1))
            #expect(insights.isScanningDisk == confirmed)
            #expect(insights.isMappingHome == confirmed)
            #expect(insights.requestedDestination == nil)
            insights.cancelDiskScan()
            #expect(await RoomTestWait.until(timeout: .seconds(10)) { !insights.isScanningDisk })
            await insights.treeStore.flush()
        }
    }

    @Test func cancelledPickerStartsNothing() async throws {
        let suite = "RoomOnboardingMapHomeCancel-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = RoomFileAccess(defaults: defaults)
        let picks = DiskPickerCalls()
        let insights = RoomInsightsModel(access: access, folderPicker: { title, _, _, initial in
            picks.count += 1
            picks.title = initial?.path ?? ""
            return nil
        }, confirmHomeMap: { Issue.record("no second confirm"); return false })

        insights.scanHome(confirmed: true)
        #expect(await RoomTestWait.until { picks.count == 1 && !insights.isChoosingDiskFolder })
        #expect(picks.title == (try home).path)
        #expect(access.folders.isEmpty && !insights.isScanningDisk && insights.diskReport == nil)
        #expect(insights.requestedDestination == nil)
    }
}

@MainActor private final class DiskPickerCalls {
    var count = 0
    var title = ""
    var message = ""
}
