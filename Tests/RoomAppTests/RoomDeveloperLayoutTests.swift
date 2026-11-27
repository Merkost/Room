import Foundation
import Testing
import RoomCore
@testable import RoomApp

@Suite("Developer layout rules")
@MainActor
struct RoomDeveloperLayoutTests {
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

    @Test func barFractionsScaleToTheLargest() {
        #expect(RoomDeveloperList.barFractions([]) == [])
        #expect(RoomDeveloperList.barFractions([0, 0]) == [0, 0])
        #expect(RoomDeveloperList.barFractions([5_000_000]) == [1])
        #expect(RoomDeveloperList.barFractions([7, 7, 7]) == [1, 1, 1])
        let dominant = RoomDeveloperList.barFractions([1_000_000_000, 500_000_000, 1_000, 0])
        #expect(dominant[0] == 1 && dominant[1] == 0.5)
        #expect(dominant[2] == 0.03)
        #expect(dominant[3] == 0)
    }

    @Test func legendKeepsDerivedDataShort() {
        #expect(RoomDevPinKind.derivedData.legendTitle == "DerivedData")
        #expect(RoomDevPinKind.gradle.legendTitle == "Gradle")
    }

    @Test func staggerIsCapped() {
        #expect(RoomDeveloperList.staggerDelay(index: 0) == 0)
        #expect(RoomDeveloperList.staggerDelay(index: 400) == RoomDeveloperList.staggerDelay(index: 12))
    }
}
