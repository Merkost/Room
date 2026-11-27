import Foundation
import SwiftUI
import Testing
@testable import RoomApp

@MainActor
struct RoomPlaceTests {
    @Test func dockHoldsFivePlaces() {
        #expect(RoomPlacePlan.places == [.overview, .disk, .clean, .developer, .memory, .history, .settings])
        #expect(RoomPlacePlan.dock == [.overview, .disk, .clean, .developer, .memory])
    }

    @Test func stoppingExistsOnlyForScans() {
        #expect(RoomPlacePlan.places.filter(RoomDock.canStop) == [.disk, .clean, .developer])
    }

    @Test func commandNumbersRunOneToSeven() {
        #expect(RoomPlacePlan.places.map(RoomPlacePlan.shortcut) == Array(1...7))
        #expect(RoomPlacePlan.place(forShortcut: 6) == .history)
        #expect(RoomPlacePlan.place(forShortcut: 7) == .settings)
        #expect(RoomPlacePlan.place(forShortcut: 8) == nil)
        #expect(RoomPlacePlan.place(forShortcut: 0) == nil)
        #expect(RoomDock.items.map(\.shortcut) == ["1", "2", "3", "4", "5", "6", "7"])
    }

    @Test func arrowStepsClampAtTheEnds() {
        #expect(RoomPlacePlan.step(from: .overview, by: -1) == .overview)
        #expect(RoomPlacePlan.step(from: .overview, by: 1) == .disk)
        #expect(RoomPlacePlan.step(from: .memory, by: 1) == .history)
        #expect(RoomPlacePlan.step(from: .settings, by: 1) == .settings)
    }

    @Test func everyPlaceHasItsOwnRoomGlyph() {
        let glyphs = RoomPlacePlan.places.map(RoomPlacePlan.glyph)
        #expect(Set(glyphs).count == glyphs.count)
        for glyph in RoomGlyph.allCases {
            let bounds = glyph.path.boundingRect
            #expect(!bounds.isEmpty, "\(glyph) draws nothing")
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 18 && bounds.maxY <= 18, "\(glyph) leaves its box")
        }
    }

    @Test func pathParserReadsRelativeAndImplicitCommands() {
        var path = Path()
        RoomGlyphPathParser.add("M2 2h4v4H2z M10 10l2-3 2 4", to: &path)
        let bounds = path.boundingRect
        #expect(bounds.minX == 2 && bounds.minY == 2)
        #expect(bounds.maxX == 14 && bounds.maxY == 11)
    }

    @Test func oneValuePerRowThroughTheFormatter() {
        var input = RoomPlaceValue.Input()
        input.freeBytes = 64_000_000_000
        input.mappedBytes = 430_000_000_000
        input.cachesChecked = true
        input.cachesReclaimableBytes = 22_400_000_000
        input.developerBytes = 120_000_000_000
        input.receipts = 3
        #expect(RoomPlaceValue.make(.overview, input) == .size(RoomFormat.gb(64_000_000_000)))
        #expect(RoomPlaceValue.make(.overview, input) == .size("64 GB"))
        #expect(RoomPlaceValue.make(.disk, input) == .size("430 GB"))
        #expect(RoomPlaceValue.make(.clean, input) == .size("22 GB"), "whole GB")
        #expect(RoomPlaceValue.make(.developer, input) == .size("120 GB"))
        #expect(RoomPlaceValue.make(.history, input) == .words("3 receipts"))
        #expect(RoomPlaceValue.make(.settings, input) == .none)

        input.cachesReclaimableBytes = 0
        #expect(RoomPlaceValue.make(.clean, input) == .words("Clear"))
        input.cachesChecked = false
        #expect(RoomPlaceValue.make(.clean, input) == .none, "no check yet is not a measured zero")
        input.receipts = 1
        #expect(RoomPlaceValue.make(.history, input) == .words("1 receipt"))
        input.freeBytes = nil
        #expect(RoomPlaceValue.make(.overview, input) == .none)
    }

    @Test func memoryShowsUsedOrNothing() {
        var input = RoomPlaceValue.Input()
        #expect(RoomPlaceValue.make(.memory, input) == .none, "no reading is not a measured zero")
        input.memoryUsedBytes = 9_663_676_416
        #expect(RoomPlaceValue.make(.memory, input) == .size(RoomFormat.memory(9_663_676_416)))
    }

    @Test func nameplateMeterSplitsUsedCouldGoAndFree() throws {
        let meter = try #require(RoomNameplateMeter.make(capacityBytes: 494, freeBytes: 64, couldGoBytes: 22))
        #expect(abs(meter.used - 408.0 / 494) < 0.0001)
        #expect(abs(meter.couldGo - 22.0 / 494) < 0.0001)
        #expect(abs(meter.free - 64.0 / 494) < 0.0001)
        #expect(abs(meter.used + meter.couldGo + meter.free - 1) < 0.0001)
        let capped = try #require(RoomNameplateMeter.make(capacityBytes: 100, freeBytes: 90, couldGoBytes: 50))
        #expect(capped.couldGo == 0.1, "Make room cannot give back more than is used")
        #expect(RoomNameplateMeter.make(capacityBytes: nil, freeBytes: 1, couldGoBytes: 0) == nil)
        #expect(RoomNameplateMeter.make(capacityBytes: 10, freeBytes: 11, couldGoBytes: 0) == nil)
    }

    @Test func keyboardSelectionHasNoTransaction() {
        let full = RoomMotionPolicy(gentleMotion: true, reduceMotion: false)
        let reduced = RoomMotionPolicy(gentleMotion: true, reduceMotion: true)
        #expect(RoomDock.selectionAnimation(origin: .keyboard, motion: full) == nil)
        #expect(RoomDock.selectionAnimation(origin: .programmatic, motion: full) == nil)
        #expect(RoomDock.selectionAnimation(origin: .pointer, motion: full) == RoomTokens.Motion.ui)
        #expect(RoomDock.selectionAnimation(origin: .pointer, motion: reduced) == nil, "Reduce Motion drops the travel")

        let defaults = UserDefaults(suiteName: "RoomPlaceTests-\(UUID().uuidString)")!
        let navigation = RoomWindowNavigation(defaults: defaults)
        let transaction = navigation.transaction(for: .keyboard)
        #expect(transaction.disablesAnimations && transaction.animation == nil)
        navigation.select(.screen(.memory), origin: .keyboard)
        #expect(navigation.selectionOrigin == .keyboard)
    }

    @Test func historyAndSettingsArePlacesThatRestore() {
        #expect(RoomRoute.screen(.history).restorableRaw == "history")
        #expect(RoomOpenOn.resolve(preference: "last", last: "settings") == .settings)
    }
}
