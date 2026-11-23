import Foundation
import Testing
@testable import RoomApp

@Suite("Developer layout rules")
@MainActor
struct RoomDeveloperLayoutTests {
    @Test func noTabsBeforeAnyData() {
        let none = RoomDeveloperAvailability()
        #expect(RoomDeveloperTabRules.visible(none, current: .rooms).isEmpty)
        #expect(RoomDeveloperTabRules.showsIntro(none, current: .rooms, isScanning: false))
        #expect(!RoomDeveloperTabRules.showsIntro(none, current: .rooms, isScanning: true))
        // Exploring another view from the start page keeps every tab so the person can move around.
        #expect(RoomDeveloperTabRules.visible(none, current: .devices) == RoomDeveloperSection.allCases)
        #expect(!RoomDeveloperTabRules.showsIntro(none, current: .devices, isScanning: false))
    }

    @Test func reviewDataRevealsRoomsAndMatrixOnly() {
        let data = RoomDeveloperAvailability(review: true)
        #expect(RoomDeveloperTabRules.visible(data, current: .rooms) == [.rooms, .matrix])
        #expect(RoomDeveloperTabRules.hidden(data, current: .rooms) == [.devices, .storage, .aiTools] + RoomDeveloperSection.allCases.filter { ![.rooms, .matrix, .devices, .storage, .aiTools].contains($0) })
    }

    @Test func currentViewStaysVisibleWithoutData() {
        let data = RoomDeveloperAvailability(review: true)
        #expect(RoomDeveloperTabRules.visible(data, current: .storage) == [.rooms, .matrix, .storage])
    }

    @Test func headlineSumsSortsAndMarksPartial() {
        let headline = RoomDeveloperHeadline(inUse: 4_000_000_000, unreferenced: 9_000_000_000, devices: 0, toolStorage: 1_000_000_000, partial: true)
        #expect(headline.parts.map(\.kind) == [.unreferenced, .inUse, .toolStorage])
        #expect(headline.total == 14_000_000_000)
        #expect(headline.unreferenced == 9_000_000_000)
        #expect(headline.partial)
        #expect(RoomDeveloperHeadline().isEmpty)
        let fractions = headline.fractions()
        #expect(fractions.count == 3 && fractions[0] > fractions[1])
    }

    @Test func wholeUnitFormatting() {
        #expect(RoomDeveloperFormat.whole(12_400_000_000) == "12 GB")
        #expect(RoomDeveloperFormat.whole(1_500_000_000, partial: true) == "≥ 2 GB")
        #expect(RoomDeveloperFormat.whole(480_300_000) == "480 MB")
        #expect(RoomDeveloperFormat.whole(999_800_000) == "1 GB")
        #expect(RoomDeveloperFormat.whole(0) == "0 KB")
    }

    @Test func sortingGroupingAndShowMore() {
        let items = [("b", Int64(5)), ("a", 5), ("c", 9), ("d", 1)]
        let sorted = RoomDeveloperList.bySize(items, bytes: { $0.1 }, name: { $0.0 })
        #expect(sorted.map(\.0) == ["c", "a", "b", "d"])
        let groups = RoomDeveloperList.grouped(items, key: { $0.0 == "d" || $0.0 == "c" ? "x" : "y" }, bytes: { $0.1 }, name: { $0.0 })
        #expect(groups.map(\.key) == ["y", "x"] || groups.map(\.key) == ["x", "y"])
        #expect(groups.first { $0.key == "x" }?.items.map(\.0) == ["c", "d"])
        let many = Array(0..<12)
        let split = RoomDeveloperList.visible(many, expanded: false)
        #expect(split.shown.count == 8 && split.hidden == 4)
        #expect(RoomDeveloperList.visible(many, expanded: true).hidden == 0)
        // One leftover row is shown rather than hidden behind a "Show 1 more".
        #expect(RoomDeveloperList.visible(Array(0..<9), expanded: false).hidden == 0)
    }

    @Test func staggerIsCapped() {
        #expect(RoomDeveloperList.staggerDelay(index: 0) == 0)
        #expect(RoomDeveloperList.staggerDelay(index: 400) == RoomDeveloperList.staggerDelay(index: 12))
    }
}
