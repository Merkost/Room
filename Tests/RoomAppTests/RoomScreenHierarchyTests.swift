import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

/// nav-v3 screen hierarchy: one headline with the number first, one supporting line, sizes through RoomFormat.gb.
@MainActor
struct RoomScreenHierarchyTests {
    @Test func overviewLeadsWithFreeSpaceAndTheGoalDistance() {
        let above = RoomOverviewWords.make(freeBytes: 64_000_000_000, capacityBytes: 494_000_000_000, goalBytes: 50_000_000_000,
                                           cachesChecked: true, change: .since(label: "Monday", usedBytes: -8_000_000_000))
        #expect(above.headline == RoomHeadline(figure: "64 GB", words: "free"))
        #expect(above.supporting == "of 494 GB, 14 GB above your goal")
        #expect(above.note == "8 GB more free than Monday")

        let below = RoomOverviewWords.make(freeBytes: 30_000_000_000, capacityBytes: 494_000_000_000, goalBytes: 50_000_000_000,
                                           cachesChecked: true, change: .tracking)
        #expect(below.supporting == "of 494 GB, 20 GB below your goal")
        #expect(below.note == "Nothing moves without a review")

        let unread = RoomOverviewWords.make(freeBytes: nil, capacityBytes: nil, goalBytes: nil, cachesChecked: false,
                                            change: .tracking)
        #expect(unread.headline.figure == nil, "a missing measurement is never a zero")
        #expect(unread.supporting == nil)
        #expect(unread.note == "A scan only reads. Nothing moves.")
    }

    @Test func floorPlanSortsKindsAndKeepsFreeLast() {
        let plan = RoomOverviewFloorPlan.make(kinds: [("media", 88), ("developer", 120), ("apps", 96), ("documents", 74),
                                                      ("system", 52), ("archives", 3)],
                                              notMappedBytes: 0, freeBytes: 64_000_000_000, capacityBytes: 494_000_000_000)
        #expect(plan.rooms.map(\.title) == ["Developer", "Apps", "Media", "Documents", "System", "Other", "Free"])
        #expect(plan.rooms.last?.isFree == true)
        #expect(plan.percent(of: plan.rooms[0]) == 24)
        let unmapped = RoomOverviewFloorPlan.make(kinds: nil, notMappedBytes: 0, freeBytes: 64, capacityBytes: 494)
        #expect(unmapped.rooms.map(\.title) == ["Used", "Free"], "no map: Room does not guess what is inside")
    }

    @Test func floorPlanWidthsAreProportionalWithAFloor() {
        let rooms = [RoomOverviewFloorPlan.Room(fill: .kind("developer"), title: "Developer", bytes: 120_000_000_000),
                     RoomOverviewFloorPlan.Room(fill: .kind("apps"), title: "Apps", bytes: 1_000_000_000),
                     RoomOverviewFloorPlan.Room(fill: .free, title: "Free", bytes: 64_000_000_000)]
        let widths = RoomOverviewFloorPlan.widths(rooms, total: 812, gap: 6, minimum: 72, freeBoostGB: 26)
        #expect(widths.count == 3)
        #expect(abs(widths.reduce(0, +) - 800) < 0.5, "fills the row minus the gaps")
        #expect(widths[1] == 72, "a tiny room keeps the minimum width")
        #expect(widths[0] > widths[2])
    }

    @Test func leftoverKindsGetTheirOwnRoomBesideSystem() {
        let kinds: [(String, Double)] = [("developer", 120), ("system", 100), ("documents", 90), ("apps", 80),
                                         ("media", 70), ("archives", 14), ("hidden", 6)]
        let plan = RoomOverviewFloorPlan.make(kinds: kinds, notMappedBytes: 0, freeBytes: 64_000_000_000,
                                              capacityBytes: 544_000_000_000)
        #expect(Set(plan.rooms.map(\.id)).count == plan.rooms.count, "a shared identity draws one room twice")
        #expect(plan.rooms.filter { $0.title == "Other" }.map(\.bytes) == [20_000_000_000])
        #expect(plan.rooms.filter { $0.title == "System" }.count == 1)
    }

    @Test func narrowPlanNeverDrawsASmallerRoomWider() {
        let gigabytes: [Int64] = [120, 109, 96, 91, 14]
        let kinds = gigabytes.enumerated().map { index, size in
            RoomOverviewFloorPlan.Room(fill: .kind("kind-\(index)"), title: "Kind \(index)", bytes: size * 1_000_000_000)
        }
        let rooms = kinds + [RoomOverviewFloorPlan.Room(fill: .free, title: "Free", bytes: 64_000_000_000)]
        for total: CGFloat in [650, 726, 800, 1046] {
            let widths = RoomOverviewFloorPlan.widths(rooms, total: total, gap: 6, minimum: 104, freeBoostGB: 26)
            #expect(zip(widths, widths.dropFirst()).prefix(4).allSatisfy { $0 >= $1 }, "at \(total): \(widths)")
        }
    }

    @Test func equalSizedCacheRowsKeepOneOrder() {
        let browser = (agents: false, bytes: Int64(2), name: "Browser caches", id: "b")
        let homebrew = (agents: false, bytes: Int64(2), name: "Homebrew downloads", id: "a")
        #expect(RoomViewModel.listsBefore(browser, homebrew))
        #expect(!RoomViewModel.listsBefore(homebrew, browser))
    }

    @Test func cachesSayWhatCanGoOrAllClear() {
        var input = RoomCachesWords.Input()
        input.hasReport = true
        input.foundBytes = 31_400_000_000
        input.selectedBytes = 22_400_000_000
        let found = RoomCachesWords.make(input)
        #expect(found.headline == RoomHeadline(figure: "31 GB", words: "of caches found"))
        #expect(found.supporting == "22 GB ticked")
        #expect(found.note == "Nothing moves without a review. Everything goes to Trash.")

        input.foundBytes = 0
        #expect(RoomCachesWords.make(input).headline == .words("All clear"))

        input.unreadable = 2
        #expect(RoomCachesWords.make(input).note == "2 places could not be read. Room left them alone.")

        var scanning = RoomCachesWords.Input()
        scanning.scanning = true
        scanning.checked = 3
        scanning.toCheck = 11
        #expect(RoomCachesWords.make(scanning).supporting == "Checking 4 of 11 places")
        #expect(RoomCachesWords.make(RoomCachesWords.Input()).headline == .words("Not checked yet"))
    }

    @Test func memoryLeadsWithTheNumberInUse() {
        let gib: Int64 = 1_073_741_824
        let words = RoomMemoryWords.make(usedBytes: 9 * gib, totalBytes: 16 * gib, pressureRaw: "normal")
        #expect(words.headline == RoomHeadline(figure: "9", words: "of 16 GB in use"))
        #expect(words.supporting == "Pressure is normal")
        #expect(RoomMemoryWords.make(usedBytes: nil, totalBytes: nil, pressureRaw: nil).headline.figure == nil)
    }

    @Test func diskMapNamesTheLevel() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let home = RoomDiskMapWords.make(levelName: "kosta", atRoot: true, rootIsHome: true, bytes: 430_000_000_000,
                                         partial: false, folders: 12, scannedAt: now.addingTimeInterval(-3 * 86_400), now: now)
        #expect(home.headline == RoomHeadline(figure: "430 GB", words: "in your home"))
        #expect(home.supporting == "12 folders, mapped 3 days ago")
        let inside = RoomDiskMapWords.make(levelName: "Developer", atRoot: false, rootIsHome: true, bytes: 120_000_000_000,
                                           partial: false, folders: 4, scannedAt: now, now: now)
        #expect(inside.headline.words == "in Developer" && inside.headline.masksWords, "Hide masks the folder name")
        #expect(inside.supporting == "4 folders inside")
    }

    @Test func historyCountsThisMonthAndGroupsByMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let a = UUID(), b = UUID(), c = UUID()
        let presentation = RoomHistoryPresentation.make([
            (id: a, date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!, bytes: 14_000_000_000, canRestore: true, restoredAll: false),
            (id: b, date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!, bytes: 14_000_000_000, canRestore: true, restoredAll: false),
            (id: c, date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!, bytes: 6_000_000_000, canRestore: false, restoredAll: true)
        ], now: now, calendar: calendar)
        #expect(presentation.headline == RoomHeadline(figure: "28 GB", words: "made this month"))
        #expect(presentation.months.count == 2)
        #expect(presentation.months[0].receiptIDs == [a, b])
        #expect(presentation.supporting == "3 receipts, 2 still in Trash")
        #expect(RoomHistoryPresentation.make([], now: now).headline == .words("Nothing moved yet"))
    }

    @Test func hideMasksHeadlineFiguresAndNamesInSpeech() {
        let headline = RoomHeadline(figure: "120 GB", words: "in Developer", masksWords: true)
        #expect(headline.spoken(hidden: true) == "Size hidden name hidden")
        #expect(headline.spoken(hidden: false) == "120 GB in Developer")
        let hidden = RoomHideState(isOn: true)
        #expect(!RoomHideMask.display("120 GB", kind: .figure, hide: hidden).contains("120"))
    }
}
