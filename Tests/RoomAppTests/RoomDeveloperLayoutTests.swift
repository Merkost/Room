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

    @Test func showMoreHidesOnlyWhenItSavesRows() {
        let split = RoomDeveloperList.visible(Array(0..<12), expanded: false)
        #expect(split.shown.count == 8 && split.hidden == 4)
        #expect(RoomDeveloperList.visible(Array(0..<12), expanded: true).hidden == 0)
        // One leftover row is shown rather than hidden behind a "Show 1 more".
        #expect(RoomDeveloperList.visible(Array(0..<9), expanded: false).hidden == 0)
    }

    @Test func legendKeepsDerivedDataShort() {
        #expect(RoomDevPinKind.derivedData.legendTitle == "DerivedData")
        #expect(RoomDevPinKind.gradle.legendTitle == "Gradle")
    }
}
