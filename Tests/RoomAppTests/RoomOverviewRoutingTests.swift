import AppKit
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Overview routing") @MainActor
struct RoomOverviewRoutingTests {
    @Test func shortcutsUseSpecOrder() {
        let numbered = RoomSidebar.items.filter { $0.shortcut != nil }
        #expect(numbered.map(\.destination) == [.overview, .disk, .clean, .developer, .memory])
        #expect(numbered.compactMap(\.shortcut) == Array("12345"))
        #expect(numbered.first?.id == "overview")
        #expect(numbered.first { $0.destination == .clean }?.title == "Caches")
    }

    @Test func activityRemainsReachable() throws {
        let activity = try #require(RoomSidebar.items.last)
        let fixture = try RoutingFixture()
        defer { fixture.remove() }
        fixture.navigation.select(activity.destination)
        #expect(fixture.navigation.destination == .activity)
        #expect(activity.id == "activity" && activity.shortcut == nil)
    }

    @Test func footerRequestsOverview() async throws {
        let fixture = try RoutingFixture(last: "disk")
        defer { fixture.remove() }
        var requested: RoomInsightDestination?
        let popover = fixture.popover(openRoom: {
            requested = fixture.insights.requestedDestination
            fixture.navigation.consumeRequest(from: fixture.insights)
        })
        popover.openOverview()

        #expect(requested == .overview)
        #expect(fixture.navigation.destination == .overview)
        #expect(fixture.insights.requestedDestination == nil)
        try await fixture.expectIdle()
    }

    @Test func retryCapacityReadsOnlyTheVolume() async throws {
        let fixture = try RoutingFixture()
        defer { fixture.remove() }
        let view = RoomOverviewView(insights: fixture.insights, rooms: fixture.rooms, navigate: fixture.navigation.select,
                                    refresh: fixture.insights.refreshDiskCapacity)

        view.retryCapacity()

        #expect(fixture.capacityReads == 1)
        #expect(fixture.navigation.destination == .overview)
        try await fixture.expectIdle()
    }

    @Test(arguments: [RoomInsightDestination.disk, .memory, .clean])
    func cardsKeepTheirDestination(_ request: RoomInsightDestination) async throws {
        let fixture = try RoutingFixture()
        defer { fixture.remove() }
        var opened = 0
        let popover = fixture.popover(openRoom: {
            opened += 1
            fixture.navigation.consumeRequest(from: fixture.insights)
        })
        if request == .clean { popover.openCaches() } else { popover.open(request) }

        let expected: RoomDestination = switch request {
        case .disk: .disk
        case .memory: .memory
        case .clean: .clean
        case .overview: .overview
        }
        #expect(opened == 1 && fixture.navigation.destination == expected)
        #expect(fixture.insights.requestedDestination == nil)
        try await fixture.expectIdle()
    }

    @Test func gearOpensSettingsOnly() async throws {
        let fixture = try RoutingFixture(last: "disk")
        defer { fixture.remove() }
        var mainOpens = 0
        var settingsOpens = 0
        fixture.popover(openRoom: { mainOpens += 1 }, showSettings: { settingsOpens += 1 }).openSettings()

        #expect(settingsOpens == 1 && mainOpens == 0)
        #expect(fixture.navigation.destination == .disk)
        #expect(fixture.insights.requestedDestination == nil)
        try await fixture.expectIdle()
    }

    @Test func reopenKeepsDestination() throws {
        let fixture = try RoutingFixture()
        defer { fixture.remove() }
        fixture.navigation.select(.memory)
        fixture.defaults.set("overview", forKey: "RoomOpenOn")
        let delegate = RoomApplicationDelegate()
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        #expect(fixture.navigation.destination == .memory)
    }

    @Test(arguments: ["overview", "last"])
    func onboardingDismissesToResolvedDestination(_ preference: String) async throws {
        let fixture = try RoutingFixture(preference: preference, last: "clean")
        defer { fixture.remove() }
        #expect(fixture.navigation.needsWelcome)

        fixture.navigation.dismissWelcome()

        #expect(!fixture.navigation.needsWelcome)
        #expect(fixture.defaults.integer(forKey: "RoomOnboardingVersion") == 1)
        #expect(fixture.navigation.destination == (preference == "overview" ? .overview : .clean))
        try await fixture.expectIdle()
    }

    @Test func overviewActionsNavigateWithoutStartingWork() async throws {
        let fixture = try RoutingFixture()
        defer { fixture.remove() }
        let view = RoomOverviewView(insights: fixture.insights, rooms: fixture.rooms, navigate: fixture.navigation.select,
                                    refresh: fixture.insights.refreshDiskCapacity)

        view.openCaches()
        #expect(fixture.navigation.destination == .clean)
        try await fixture.expectIdle()

        fixture.navigation.select(.overview)
        view.openDiskMap()
        #expect(fixture.navigation.destination == .disk)
        try await fixture.expectIdle()
    }
}

@MainActor
private final class RoutingFixture {
    let defaults: UserDefaults
    let navigation: RoomWindowNavigation
    let insights: RoomInsightsModel
    private let cache: RoomViewModel
    let rooms: RoomRoomsModel
    private let suite: String
    private let root: URL
    private let probe: RoutingProbe
    var capacityReads: Int { probe.capacityReads }

    init(preference: String? = nil, last: String? = nil) throws {
        suite = "RoomOverviewRoutingTests-\(UUID())"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(preference, forKey: "RoomOpenOn")
        defaults.set(last, forKey: "RoomLastDestination")
        navigation = RoomWindowNavigation(defaults: defaults)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let access = RoomFileAccess(defaults: defaults)
        let probe = RoutingProbe()
        self.probe = probe
        insights = RoomInsightsModel(access: access, folderPicker: { _, _, _, _ in
            probe.pickerOpens += 1
            return nil
        }, capacityReader: {
            probe.capacityReads += 1
            return RoomVolumeCapacity(capacityBytes: 100, freeBytes: 25)
        })
        cache = RoomViewModel(engine: CacheEngine(configuration: CacheConfiguration(roots: [], homeDirectory: root),
            activityDirectory: root.appendingPathComponent("activity")), cachesCheckStore: RoomCachesCheckStore(defaults: defaults))
        rooms = RoomRoomsModel(store: RoomRoomsStore(directory: root.appendingPathComponent("State")), access: access)
    }

    func popover(openRoom: @escaping () -> Void, showSettings: @escaping () -> Void = {}) -> RoomMenuBarView {
        RoomMenuBarView(insights: insights, cacheModel: cache, rooms: rooms, openRoom: openRoom, showSettings: showSettings)
    }

    func expectIdle() async throws {
        #expect(!cache.isScanning && !cache.isWorking && !insights.isScanningDisk)
        // The picker and the engines can schedule work on the next turn of the main actor.
        try await Task.sleep(for: .milliseconds(20))
        #expect(probe.pickerOpens == 0)
        #expect(cache.lastScanned == nil && !cache.canReviewCleanup)
        #expect(insights.diskURL == nil && insights.diskReport == nil)
        #expect(!rooms.isMeasuring)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class RoutingProbe {
    var pickerOpens = 0
    var capacityReads = 0
}
