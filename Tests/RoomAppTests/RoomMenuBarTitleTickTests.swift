import Foundation
import Testing
@testable import RoomApp

@Suite("Menu bar title ticks")
struct RoomMenuBarTitleTickTests {
    private let english = Locale(identifier: "en_US")

    @Test func memoryCountsInTheShownUnitAndFinishesWithTheExactTitle() {
        let titles = RoomMenuBarTitleTick.titles(from: "16.2 GB", to: "24.8 GB",
                                               previousMode: .memory, mode: .memory, locale: english)
        #expect(titles.count == 8)
        #expect(titles.first == "19 GB")
        #expect(titles.last == "24.8 GB")
        #expect(titles.allSatisfy { $0.hasSuffix(" GB") })
    }

    @Test func diskTicksKeepTheFreeSuffix() {
        let titles = RoomMenuBarTitleTick.titles(from: "41 GB free", to: "50 GB free",
                                               previousMode: .disk, mode: .disk, locale: english)
        #expect(titles.count == 8)
        #expect(titles.first == "44 GB free")
        #expect(titles.last == "50 GB free")
    }

    @Test func decimalTenthsAnimateInBothDirections() {
        let up = RoomMenuBarTitleTick.titles(from: "16.3 GB", to: "16.4 GB",
                                           previousMode: .memory, mode: .memory, locale: english)
        let down = RoomMenuBarTitleTick.titles(from: "16.4 GB", to: "16.3 GB",
                                             previousMode: .memory, mode: .memory, locale: english)
        #expect(up.count == 8 && up.last == "16.4 GB")
        #expect(down.count == 8 && down.last == "16.3 GB")
    }

    @Test func smallChangesSwapImmediately() {
        #expect(RoomMenuBarTitleTick.titles(from: "16.2 GB", to: "16.25 GB",
                                          previousMode: .memory, mode: .memory, locale: english).isEmpty)
    }

    @Test func firstValueAndModeChangesSwapImmediately() {
        #expect(RoomMenuBarTitleTick.titles(from: "16.2 GB", to: "24.8 GB",
                                          previousMode: nil, mode: .memory, locale: english).isEmpty)
        #expect(RoomMenuBarTitleTick.titles(from: "16.2 GB", to: "41 GB free",
                                          previousMode: .memory, mode: .disk, locale: english).isEmpty)
    }

    @Test func bothAndNoneSwapImmediately() {
        #expect(RoomMenuBarTitleTick.titles(from: "16.2 GB · 312 GB", to: "24.8 GB · 41 GB",
                                          previousMode: .both, mode: .both, locale: english).isEmpty)
        #expect(RoomMenuBarTitleTick.titles(from: "", to: "",
                                          previousMode: RoomMenuBarValueMode.none, mode: .none, locale: english).isEmpty)
    }

    @Test func unavailableAndChangedUnitsSwapImmediately() {
        #expect(RoomMenuBarTitleTick.titles(from: "—", to: "24.8 GB",
                                          previousMode: .memory, mode: .memory, locale: english).isEmpty)
        #expect(RoomMenuBarTitleTick.titles(from: "999 MB", to: "1 GB",
                                          previousMode: .memory, mode: .memory, locale: english).isEmpty)
    }

    @Test func localizedDecimalsAndGroupingArePreserved() {
        let titles = RoomMenuBarTitleTick.titles(from: "1.216,2 GB", to: "1.224,8 GB",
                                               previousMode: .memory, mode: .memory,
                                               locale: Locale(identifier: "de_DE"))
        #expect(titles.count == 8)
        #expect(titles.first == "1.219 GB")
        #expect(titles.last == "1.224,8 GB")
    }

    @Test func fractionalPrecisionAndNonbreakingUnitSpaceArePreserved() {
        let titles = RoomMenuBarTitleTick.titles(from: "1.25\u{00A0}GB", to: "1.75\u{00A0}GB",
                                               previousMode: .memory, mode: .memory, locale: english)
        #expect(titles.count == 8)
        #expect(titles.first == "1.42\u{00A0}GB")
        #expect(titles.last == "1.75\u{00A0}GB")
    }
}
