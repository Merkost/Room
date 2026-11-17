import Foundation
import Testing
@testable import RoomApp

@Suite("Menu bar presentation")
struct RoomMenuBarPresentationTests {
    private let format = RoomMenuBarFormat.fixtureGigabytes
    private let gb: Int64 = 1_000_000_000

    private func memory(_ used: Double, _ pressure: RoomMenuBarPressure,
                        _ edit: (inout RoomMenuBarInput) -> Void = { _ in }) -> RoomMenuBarOutput {
        var input = RoomMenuBarInput(value: .memory, memoryUsedBytes: Int64(used * 1e9),
                                    memoryTotalBytes: 32 * gb, pressure: pressure)
        edit(&input)
        return RoomMenuBarPresentation.make(input, format: format)
    }

    private func disk(_ freeGB: Int64) -> RoomMenuBarOutput {
        RoomMenuBarPresentation.make(
            RoomMenuBarInput(value: .disk, diskFreeBytes: freeGB * gb, goalBytes: 50 * gb),
            format: format)
    }

    @Test func normalStateHasHollowMarkAndAccessibleValue() {
        let normal = memory(16.2, .normal)
        #expect(normal.title == "16.2 GB" && normal.pocketFill == 0 && normal.tint == .none && normal.icon == .mark)
        #expect(normal.accessibilityValue == "16.2 GB memory used of 32 GB, Normal pressure")
        #expect(normal.toolTip == "Room · 16.2 GB memory used of 32 GB, Normal pressure")
    }

    @Test func elevatedStateHasHalfPocketAndAccessibleValue() {
        let elevated = memory(24.8, .elevated)
        #expect(elevated.title == "24.8 GB" && elevated.pocketFill == 0.5 && elevated.tint == .elevated)
        #expect(elevated.accessibilityValue == "24.8 GB memory used of 32 GB, Elevated pressure")
    }

    @Test func criticalStateHasFullPocketAndAccessibleValue() {
        let critical = memory(30.1, .critical)
        #expect(critical.title == "30.1 GB" && critical.pocketFill == 1 && critical.tint == .critical)
        #expect(critical.accessibilityValue == "30.1 GB memory used of 32 GB, Critical pressure")
    }

    @Test func diskBelowGoalHasHalfPocketAndExplainsShortfall() {
        let belowGoal = disk(41)
        #expect(belowGoal.title == "41 GB" && belowGoal.pocketFill == 0.5 && belowGoal.tint == .elevated)
        #expect(belowGoal.accessibilityValue == "41 GB free, 9 GB under your 50 GB goal")
    }

    @Test func iconOnlyStateStillCarriesAndSpeaksTheLevel() {
        let iconOnly = memory(24.8, .elevated) { $0.value = .none }
        #expect(iconOnly.title == "" && iconOnly.pocketFill == 0.5 && iconOnly.tint == .elevated)
        #expect(iconOnly.accessibilityValue.hasPrefix("24.8 GB memory used of 32 GB, Elevated pressure. "))
    }

    @Test func shapeAndTintFollowTheirIndependentRules() {
        let metGoal = disk(312)
        #expect(metGoal.pocketFill == 0 && metGoal.tint == .none && metGoal.title == "312 GB")
        let elevatedWhenNeeded = memory(24.8, .elevated) { $0.tintOnlyWhenNeeded = true }
        #expect(elevatedWhenNeeded.pocketFill == 0.5)
        let alwaysTintedNormal = memory(16.2, .normal) { $0.tintOnlyWhenNeeded = false }
        #expect(alwaysTintedNormal.tint == .normal)
        let alwaysTintedElevated = memory(24.8, .elevated) { $0.tintOnlyWhenNeeded = false }
        #expect(alwaysTintedElevated.tint == .elevated)
    }

    @Test func bothValuesUseTheWorseOfPressureAndGoal() {
        var both = RoomMenuBarInput(value: .both, memoryUsedBytes: 16_200_000_000,
                                   memoryTotalBytes: 32 * gb, pressure: .normal,
                                   diskFreeBytes: 312 * gb, goalBytes: 50 * gb)
        #expect(RoomMenuBarPresentation.make(both, format: format).title == "16.2 GB · 312 GB")
        both.diskFreeBytes = 41 * gb
        #expect(RoomMenuBarPresentation.make(both, format: format).pocketFill == 0.5)
        both.pressure = .critical
        both.diskFreeBytes = 312 * gb
        #expect(RoomMenuBarPresentation.make(both, format: format).pocketFill == 1)
        both.pressure = .elevated
        both.diskFreeBytes = 41 * gb
        #expect(RoomMenuBarPresentation.make(both, format: format).pocketFill == 0.5)
    }

    @Test(arguments: RoomMenuBarValueMode.allCases, RoomMenuBarLayoutMode.allCases)
    func stackedLinesOnlyExistForBothInStackedLayout(value: RoomMenuBarValueMode,
                                                    layout: RoomMenuBarLayoutMode) {
        let input = RoomMenuBarInput(value: value, layout: layout,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32 * gb,
            pressure: .normal, diskFreeBytes: 312 * gb, goalBytes: 50 * gb)
        let output = RoomMenuBarPresentation.make(input, format: format)
        #expect((output.stackedLines != nil) == (value == .both && layout == .stacked))
    }

    @Test func stackedFiguresMatchTheInlineFiguresAndKeepExistingPresentation() {
        var input = RoomMenuBarInput(value: .both, icon: .symbol,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32 * gb,
            pressure: .elevated, diskFreeBytes: 312 * gb, goalBytes: 50 * gb)
        let inline = RoomMenuBarPresentation.make(input, format: format)
        input.layout = .stacked
        var stacked = RoomMenuBarPresentation.make(input, format: format)
        input.value = .memory
        let memory = RoomMenuBarPresentation.make(input, format: format)
        input.value = .disk
        let disk = RoomMenuBarPresentation.make(input, format: format)
        #expect(stacked.stackedLines == [
            RoomMenuBarStackedLine(symbolName: "memorychip", text: memory.title),
            RoomMenuBarStackedLine(symbolName: "internaldrive", text: disk.title)
        ])
        #expect(stacked.title == "16.2 GB · 312 GB")
        #expect(stacked.icon == .mark)
        stacked.stackedLines = nil
        #expect(stacked == inline)
    }

    @Test(arguments: [false, true], [false, true])
    func stackedMissingMeasurementsStayOnTheirOwnLines(memoryKnown: Bool, diskKnown: Bool) {
        let input = RoomMenuBarInput(value: .both, layout: .stacked,
            memoryUsedBytes: memoryKnown ? 16_200_000_000 : nil,
            memoryTotalBytes: memoryKnown ? 32 * gb : nil,
            diskFreeBytes: diskKnown ? 312 * gb : nil)
        let output = RoomMenuBarPresentation.make(input, format: format)
        #expect(output.stackedLines == [
            RoomMenuBarStackedLine(symbolName: "memorychip", text: memoryKnown ? "16.2 GB" : "—"),
            RoomMenuBarStackedLine(symbolName: "internaldrive", text: diskKnown ? "312 GB" : "—")
        ])
    }

    @Test func stackedMemoryWithoutItsTotalIsUnavailable() {
        let input = RoomMenuBarInput(value: .both, layout: .stacked,
            memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 0, diskFreeBytes: 312 * gb)
        #expect(RoomMenuBarPresentation.make(input, format: format).stackedLines?.first?.text == "—")
    }

    @Test func iconModesKeepAnInvisibleItemImpossible() {
        #expect(RoomMenuBarPresentation.make(RoomMenuBarInput(value: .none, icon: .none), format: format).icon == .mark)
        let noIcon = memory(16.2, .normal) { $0.icon = .none }
        #expect(noIcon.icon == .none)
        let symbol = memory(16.2, .normal) { $0.icon = .symbol }
        let belowGoal = disk(41)
        #expect(symbol.symbolName == "memorychip" && belowGoal.symbolName == "internaldrive")
    }

    @Test func ramAndStorageEachGetTheirOwnSymbol() {
        // D-MB-14: Value Memory shows the chip, Value Disk the drive; Both and None have no single symbol, so the Room mark stays.
        let ram = memory(16.2, .normal) { $0.icon = .symbol }
        let storage = RoomMenuBarPresentation.make(
            RoomMenuBarInput(value: .disk, icon: .symbol, diskFreeBytes: 41 * gb, goalBytes: 50 * gb), format: format)
        let both = RoomMenuBarPresentation.make(
            RoomMenuBarInput(value: .both, icon: .symbol, memoryUsedBytes: 16_200_000_000, memoryTotalBytes: 32 * gb,
                             pressure: .normal, diskFreeBytes: 312 * gb, goalBytes: 50 * gb), format: format)
        let iconOnly = memory(24.8, .elevated) { $0.value = .none; $0.icon = .symbol }
        #expect(ram.icon == .symbol && ram.symbolName == "memorychip")
        #expect(storage.icon == .symbol && storage.symbolName == "internaldrive" && storage.title == "41 GB")
        #expect(both.icon == .mark && iconOnly.icon == .mark && iconOnly.pocketFill == 0.5)
    }

    @Test func missingDataIsNeverPresentedAsZero() {
        let gone = RoomMenuBarPresentation.make(RoomMenuBarInput(value: .memory), format: format)
        #expect(gone.title == "—" && gone.pocketFill == 0 && gone.tint == .none && gone.accessibilityValue == "Memory measurement unavailable")
        let noDisk = RoomMenuBarPresentation.make(RoomMenuBarInput(value: .disk), format: format)
        #expect(noDisk.title == "—" && noDisk.accessibilityValue == "Free space unavailable")
        let unknown = memory(16.2, .unknown) { $0.tintOnlyWhenNeeded = false }
        #expect(unknown.tint == .none)
    }

    @Test func thirtyValuesWithTwoToneChangesAnnounceExactlyTwice() {
        var announcer = RoomMenuBarAnnouncer()
        var announced = 0
        let sequence: [(Double, RoomMenuBarPressure)] =
            (0..<12).map { (16.0 + Double($0) * 0.1, .normal) }
            + (0..<10).map { (24.0 + Double($0) * 0.1, .elevated) }
            + (0..<8).map { (17.0 + Double($0) * 0.1, .normal) }
        for (used, pressure) in sequence {
            if announcer.shouldAnnounce(memory(used, pressure).announcementKey) { announced += 1 }
        }
        #expect(sequence.count == 30 && announced == 2)
    }

    @Test func firstValueAfterLaunchIsNotAnnounced() {
        var fresh = RoomMenuBarAnnouncer()
        let announced = fresh.shouldAnnounce("m0d-")
        #expect(announced == false)
    }

    @Test func crossingTheDiskGoalAnnounces() {
        var announcer = RoomMenuBarAnnouncer()
        _ = announcer.shouldAnnounce(disk(312).announcementKey)
        let announced = announcer.shouldAnnounce(disk(41).announcementKey)
        #expect(announced)
    }

    @Test func pocketFillUsesMonotonicCachedFrames() {
        let up = RoomMenuBarMotion.fillFrames(from: 0, to: 1)
        #expect(up.count == 6 && up.allSatisfy { RoomMenuBarMotion.cachedFills.contains($0) }
                && zip(up, up.dropFirst()).allSatisfy { $0 <= $1 })
        let down = RoomMenuBarMotion.fillFrames(from: 0.5, to: 0)
        #expect(zip(down, down.dropFirst()).allSatisfy { $0 >= $1 }
                && down.allSatisfy { $0 >= 0 && $0 <= 0.5 })
        #expect(RoomMenuBarMotion.cachedFills.count == 9)
    }

    @Test func valueTickEndsExactlyOnTheNewValueWithoutOvershooting() {
        let tick = RoomMenuBarMotion.tickValues(from: 16.2, to: 24.8)
        #expect(tick.count == 8 && tick.last == 24.8 && tick.allSatisfy { $0 >= 16.2 && $0 <= 24.8 }
                && zip(tick, tick.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(RoomMenuBarMotion.tickValues(from: 16.2, to: 16.25).isEmpty)
        #expect(RoomMenuBarMotion.tickSteps == 8 && RoomMenuBarMotion.tickDuration == 0.32)
    }

#if DEBUG
    private func scenario(_ scenario: RoomDebugMenuBarScenario) -> RoomMenuBarOutput {
        RoomMenuBarPresentation.make(scenario.apply(to: RoomMenuBarInput()), format: format)
    }

    @Test func debugScenariosReproduceTheStateTable() {
        #expect(scenario(.normal).pocketFill == 0 && scenario(.normal).title == "16.2 GB")
        #expect(scenario(.elevated).pocketFill == 0.5 && scenario(.elevated).tint == .elevated)
        #expect(scenario(.critical).pocketFill == 1 && scenario(.critical).tint == .critical)
        #expect(scenario(.diskBelowGoal).title == "41 GB" && scenario(.diskBelowGoal).pocketFill == 0.5)
        #expect(scenario(.iconOnlyElevated).title == "" && scenario(.iconOnlyElevated).pocketFill == 0.5)
        #expect(scenario(.bothElevatedBelowGoal).title == "24.8 GB · 41 GB")
        #expect(scenario(.bothStacked).stackedLines == [
            RoomMenuBarStackedLine(symbolName: "memorychip", text: "24.8 GB"),
            RoomMenuBarStackedLine(symbolName: "internaldrive", text: "41 GB")
        ])
        var live = RoomMenuBarInput(layout: .stacked)
        live.value = .both
        #expect(RoomDebugMenuBarScenario.bothElevatedBelowGoal.apply(to: live).layout == .inline)
        #expect(RoomDebugMenuBarScenario.live.apply(to: RoomMenuBarInput()) == RoomMenuBarInput())
    }
#endif
}
