import Foundation
import ServiceManagement
import Testing
@testable import RoomApp

@Suite("Settings logic")
struct RoomSettingsLogicTests {
    @Test(arguments: ["overview", "clean", "memory", "disk", "developer", "activity", "unknown"])
    func overviewPreferenceResolvesOverview(_ last: String) {
        #expect(RoomOpenOn.resolve(preference: "overview", last: last) == .overview)
    }

    @Test func lastOverviewRestores() {
        #expect(RoomOpenOn.resolve(preference: "last", last: "overview") == .overview)
    }

    @Test func lastCleanStillRestores() {
        #expect(RoomOpenOn.resolve(preference: "last", last: "clean") == .clean)
    }

    @Test(arguments: [RoomDestination.memory, .disk, .developer])
    func lastRestoresSupportedDestinations(_ destination: RoomDestination) {
        #expect(RoomOpenOn.resolve(preference: "last", last: destination.rawValue) == destination)
    }

    @Test(arguments: [String?.none, "activity", "invalid", ""])
    func invalidAndActivityFallBackOverview(_ last: String?) {
        #expect(RoomOpenOn.resolve(preference: "last", last: last) == .overview)
    }

    @Test func unknownOpenPreferenceFallsBackToOverview() {
        #expect(RoomOpenOn.resolve(preference: "unknown", last: "disk") == .overview)
    }

    @Test func previewUsesFixedMeasurementsAndKeepsPreferences() {
        let input = RoomMenuBarInput(value: .both, layout: .stacked, icon: .symbol, tintOnlyWhenNeeded: false,
            memoryUsedBytes: 1, memoryTotalBytes: 2, pressure: .critical,
            diskFreeBytes: 3, goalBytes: 80_000_000_000)
        let scenarios = RoomMenuBarPreviewScenarios.inputs(from: input)
        #expect(scenarios.normal.memoryUsedBytes == 16_200_000_000)
        #expect(scenarios.normal.memoryTotalBytes == 32_000_000_000)
        #expect(scenarios.normal.pressure == .normal)
        #expect(scenarios.normal.diskFreeBytes == 312_000_000_000)
        #expect(scenarios.elevated.memoryUsedBytes == 24_800_000_000)
        #expect(scenarios.elevated.memoryTotalBytes == 32_000_000_000)
        #expect(scenarios.elevated.pressure == .elevated)
        #expect(scenarios.elevated.diskFreeBytes == 71_000_000_000)
        for scenario in [scenarios.normal, scenarios.elevated] {
            #expect(scenario.value == input.value)
            #expect(scenario.layout == .stacked)
            #expect(scenario.icon == input.icon)
            #expect(scenario.tintOnlyWhenNeeded == input.tintOnlyWhenNeeded)
            #expect(scenario.goalBytes == input.goalBytes)
        }
    }

    @Test(arguments: [Int64.min, 0, 5_000_000_000, 10_000_000_000])
    func elevatedPreviewNeverShowsLessThanOneGigabyte(_ goal: Int64) {
        let scenarios = RoomMenuBarPreviewScenarios.inputs(from: RoomMenuBarInput(goalBytes: goal))
        #expect(scenarios.elevated.diskFreeBytes == 1_000_000_000)
        #expect(scenarios.elevated.goalBytes == goal)
    }

    @Test func madeRoomExcludesRestoresAndErrorsAndUsesEarliestKeptDate() throws {
        let calendar = Self.calendar(locale: "en_US")
        let early = try #require(calendar.date(from: DateComponents(year: 2025, month: 3, day: 2)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let excluded = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let activities = [
            Self.activity(date: later, bytes: 8_000_000_000),
            Self.activity(date: excluded, bytes: 99_000_000_000, restored: 1),
            Self.activity(date: early, bytes: 12_000_000_000),
            Self.activity(date: excluded, bytes: 99_000_000_000, errors: 1)
        ]
        let summary = try #require(RoomMadeRoom.summary(activities: activities, calendar: calendar))
        #expect(summary.bytes == 20_000_000_000)
        #expect(summary.count == 2)
        #expect(summary.since == early)
        #expect(summary.sinceMonth == "March 2025")
        #expect(summary.caption == "moved to Trash since March 2025, across 2 cleanups")
    }

    @Test func noKeptCleanupsHasNoSummary() {
        #expect(RoomMadeRoom.summary(activities: []) == nil)
        #expect(RoomMadeRoom.summary(activities: [Self.activity(date: Date(), bytes: 10, restored: 1)]) == nil)
        #expect(RoomMadeRoom.summary(activities: [Self.activity(date: Date(), bytes: 10, errors: 1)]) == nil)
    }

    @Test func singleCleanupUsesSingularAndLocalizedMonth() throws {
        let calendar = Self.calendar(locale: "fr_FR")
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let summary = try #require(RoomMadeRoom.summary(
            activities: [Self.activity(date: date, bytes: 10)], calendar: calendar))
        #expect(summary.bytes == 10)
        #expect(summary.count == 1)
        #expect(summary.sinceMonth == "mars 2026")
        #expect(summary.caption == "moved to Trash since mars 2026, across 1 cleanup")
    }

    private static func calendar(locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func activity(date: Date, bytes: Int64, restored: Int = 0, errors: Int = 0) -> RoomActivity {
        RoomActivity(id: UUID(), date: date, bytes: bytes, itemCount: 1,
            restoredCount: restored, errorCount: errors, canRestore: false, title: "Cleanup", details: [])
    }
}

@Suite("Login item settings") @MainActor
struct RoomLoginItemTests {
    @Test func turningOnRegistersAndTurningOffUnregisters() {
        let service = FakeRoomLoginItem()
        let model = RoomLoginItemModel(service: service)
        #expect(!model.enabled)
        model.setEnabled(true)
        #expect(service.registerCount == 1)
        #expect(model.enabled)
        model.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(!model.enabled)
        #expect(model.errorMessage == nil)
    }

    @Test func approvalRequiredShowsHintAndDoesNotClaimEnabled() {
        let service = FakeRoomLoginItem()
        service.registrationStatus = .requiresApproval
        let model = RoomLoginItemModel(service: service)
        model.setEnabled(true)
        #expect(model.requiresApproval)
        #expect(!model.enabled)
        #expect(model.approvalHint == "Allow Room in System Settings › General › Login Items.")
    }

    @Test(arguments: [false, true])
    func errorsShowTheRealStatusAndTheRecoveryMessage(_ initiallyEnabled: Bool) {
        let service = FakeRoomLoginItem()
        service.status = initiallyEnabled ? .enabled : .notRegistered
        service.shouldThrow = true
        let model = RoomLoginItemModel(service: service)
        model.setEnabled(!initiallyEnabled)
        // The switch tells the truth: a failed register stays off, a failed unregister stays on.
        #expect(model.enabled == initiallyEnabled)
        #expect(model.errorMessage == "Room couldn't change this. Try again in System Settings.")
    }

    @Test func refreshingReadsTheSystemStatusAgain() {
        let service = FakeRoomLoginItem()
        let model = RoomLoginItemModel(service: service)
        service.status = .enabled
        model.refreshStatus()
        #expect(model.enabled)
        service.status = .requiresApproval
        model.refreshStatus()
        #expect(!model.enabled && model.requiresApproval)
        service.status = .notFound
        model.refreshStatus()
        #expect(!model.enabled && !model.requiresApproval)
    }
}

@MainActor private final class FakeRoomLoginItem: RoomLoginItem {
    enum Failure: Error { case unavailable }
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registerCount = 0
    var unregisterCount = 0
    var shouldThrow = false

    func register() throws {
        registerCount += 1
        if shouldThrow { throw Failure.unavailable }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCount += 1
        if shouldThrow { throw Failure.unavailable }
        status = .notRegistered
    }
}
