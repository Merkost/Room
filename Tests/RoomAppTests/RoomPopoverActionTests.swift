import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Popover navigation") @MainActor
struct RoomPopoverActionTests {
    @Test(arguments: [false, true])
    func openCachesNeverChangesScanState(_ alreadyScanning: Bool) async throws {
        let fixture = try PopoverActionFixture()
        defer { fixture.remove() }
        if alreadyScanning { fixture.cache.scan() }
        let wasScanning = fixture.cache.isScanning
        var opened = 0
        let view = RoomMenuBarView(insights: fixture.insights, cacheModel: fixture.cache,
                                   rooms: fixture.rooms, openRoom: { opened += 1 }, showSettings: {})
        view.openCaches()
        #expect(fixture.cache.isScanning == wasScanning)
        #expect(fixture.insights.requestedDestination == .clean && opened == 1)
        fixture.cache.cancelScan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while fixture.cache.isScanning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!fixture.cache.isScanning)
    }

    @Test func gearOpensSettingsWithoutOpeningMainWindow() throws {
        let fixture = try PopoverActionFixture()
        defer { fixture.remove() }
        var opened = false
        var settingsOpened = false
        let view = RoomMenuBarView(insights: fixture.insights, cacheModel: fixture.cache,
                                   rooms: fixture.rooms, openRoom: { opened = true }, showSettings: { settingsOpened = true })
        view.openSettings()
        #expect(settingsOpened && !opened)
        #expect(!fixture.insights.requestedSettings)
        #expect(!fixture.cache.isScanning)
    }

    @Test func pinnedRoomRequestsItsRouteWithoutScanning() async throws {
        let fixture = try PopoverActionFixture()
        defer { fixture.remove() }
        fixture.rooms.pin(url: fixture.root)
        let id = try #require(fixture.rooms.pinnedRoom?.id)
        var opened = false
        let view = RoomMenuBarView(insights: fixture.insights, cacheModel: fixture.cache,
                                   rooms: fixture.rooms, openRoom: { opened = true }, showSettings: {})
        view.openPinnedRoom()
        #expect(opened && fixture.insights.requestedPinnedRoom == id)
        #expect(fixture.insights.diskURL == nil && !fixture.insights.isScanningDisk)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        fixture.rooms.cancelMeasurement()
        while fixture.rooms.isMeasuring, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!fixture.rooms.isMeasuring)
    }
}

@MainActor private struct PopoverActionFixture {
    let suite: String
    let root: URL
    let defaults: UserDefaults
    let cache: RoomViewModel
    let insights: RoomInsightsModel
    let rooms: RoomRoomsModel

    init() throws {
        suite = "RoomPopoverActionTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        root = URL(fileURLWithPath: "/private/tmp/\(suite)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let access = RoomFileAccess(defaults: defaults)
        cache = RoomViewModel(engine: CacheEngine(configuration: CacheConfiguration(roots: [], homeDirectory: root),
            activityDirectory: root.appendingPathComponent("activity")), cachesCheckStore: RoomCachesCheckStore(defaults: defaults))
        insights = RoomInsightsModel(access: access, folderPicker: { _, _, _, _ in nil })
        rooms = RoomRoomsModel(store: RoomRoomsStore(directory: root.appendingPathComponent("State")), access: access,
            measurer: RoomRoomMeasurer(measure: { _ in .measured(RoomSizePoint(at: Date(), bytes: 4096, partial: false)) }))
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
