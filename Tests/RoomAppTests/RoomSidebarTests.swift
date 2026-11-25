import Foundation
import SwiftUI
import Testing
@testable import RoomApp

@MainActor
struct RoomSidebarTests {
    @Test func placesAreGroupedInMockupOrder() {
        #expect(RoomSidebarPlan.places == [.overview, .disk, .clean, .developer, .memory, .history, .settings])
        #expect(RoomSidebarPlan.places(in: .yourMac) == [.overview, .disk])
        #expect(RoomSidebarPlan.places(in: .makeRoom) == [.clean, .developer])
        #expect(RoomSidebarPlan.places(in: .rightNow) == [.memory])
        #expect(RoomSidebarPlan.places(in: .bottom) == [.history, .settings])
        #expect(RoomSidebarPlan.Group.bottom.title == nil)
        #expect(RoomSidebarPlan.Group.yourMac.title == "Your Mac")
        #expect(RoomSidebarPlan.Group.makeRoom.title == "Make room")
        #expect(RoomSidebarPlan.Group.rightNow.title == "Right now")
    }

    @Test func commandNumbersRunOneToSeven() {
        #expect(RoomSidebarPlan.places.map(RoomSidebarPlan.shortcut) == Array(1...7))
        #expect(RoomSidebarPlan.place(forShortcut: 6) == .history)
        #expect(RoomSidebarPlan.place(forShortcut: 7) == .settings)
        #expect(RoomSidebarPlan.place(forShortcut: 8) == nil)
        #expect(RoomSidebarPlan.place(forShortcut: 0) == nil)
        #expect(RoomSidebar.items.map(\.shortcut) == ["1", "2", "3", "4", "5", "6", "7"])
    }

    @Test func arrowStepsClampAtTheEnds() {
        #expect(RoomSidebarPlan.step(from: .overview, by: -1) == .overview)
        #expect(RoomSidebarPlan.step(from: .overview, by: 1) == .disk)
        #expect(RoomSidebarPlan.step(from: .memory, by: 1) == .history)
        #expect(RoomSidebarPlan.step(from: .settings, by: 1) == .settings)
    }

    @Test func everyPlaceHasItsOwnRoomGlyph() {
        let glyphs = RoomSidebarPlan.places.map(RoomSidebarPlan.glyph)
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
        var input = RoomSidebarValue.Input()
        input.freeBytes = 64_000_000_000
        input.mappedFolders = 12
        input.cachesChecked = true
        input.cachesReclaimableBytes = 22_400_000_000
        input.developerBytes = 120_000_000_000
        input.receipts = 3
        #expect(RoomSidebarValue.make(.overview, input) == .size(RoomFormat.gb(64_000_000_000)))
        #expect(RoomSidebarValue.make(.overview, input) == .size("64 GB"))
        #expect(RoomSidebarValue.make(.disk, input) == .words("12 folders"))
        #expect(RoomSidebarValue.make(.clean, input) == .size("22 GB"), "whole GB")
        #expect(RoomSidebarValue.make(.developer, input) == .size("120 GB"))
        #expect(RoomSidebarValue.make(.history, input) == .words("3 receipts"))
        #expect(RoomSidebarValue.make(.settings, input) == .none)

        input.cachesReclaimableBytes = 0
        #expect(RoomSidebarValue.make(.clean, input) == .words("Clear"))
        input.cachesChecked = false
        #expect(RoomSidebarValue.make(.clean, input) == .none, "no check yet is not a measured zero")
        input.receipts = 1
        #expect(RoomSidebarValue.make(.history, input) == .words("1 receipt"))
        input.freeBytes = nil
        #expect(RoomSidebarValue.make(.overview, input) == .none)
    }

    @Test func memorySparklineKeepsTheLastFourteenSamples() {
        var input = RoomSidebarValue.Input()
        input.memorySamples = (1...30).map { Int64($0) }
        guard case .sparkline(let samples) = RoomSidebarValue.make(.memory, input) else {
            Issue.record("memory shows a sparkline"); return
        }
        #expect(samples == (17...30).map { Int64($0) })
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
        #expect(RoomSidebar.selectionAnimation(origin: .keyboard, motion: full) == nil)
        #expect(RoomSidebar.selectionAnimation(origin: .programmatic, motion: full) == nil)
        #expect(RoomSidebar.selectionAnimation(origin: .pointer, motion: full) == RoomTokens.Motion.ui)
        #expect(RoomSidebar.selectionAnimation(origin: .pointer, motion: reduced) == nil, "Reduce Motion drops the travel")

        let defaults = UserDefaults(suiteName: "RoomSidebarTests-\(UUID().uuidString)")!
        let navigation = RoomWindowNavigation(defaults: defaults)
        let transaction = navigation.transaction(for: .keyboard)
        #expect(transaction.disablesAnimations && transaction.animation == nil)
        navigation.select(.screen(.memory), origin: .keyboard)
        #expect(navigation.selectionOrigin == .keyboard)
    }

    @Test func historyAndSettingsArePlacesThatRestore() {
        #expect(RoomRoute.screen(.history).restorableRaw == "history")
        #expect(RoomOpenOn.resolve(preference: "last", last: "settings") == .settings)
        #expect(RoomSidebarPlan.isQuiet(.history) && RoomSidebarPlan.isQuiet(.settings))
        #expect(!RoomSidebarPlan.isQuiet(.overview))
    }
}
