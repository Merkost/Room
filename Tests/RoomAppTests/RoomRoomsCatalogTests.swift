import Foundation
import Testing
@testable import RoomApp

@Suite("Room catalogue reference")
struct RoomRoomsCatalogTests {
    @Test func referenceChecks() throws {
        func check(_ id: String, _ passed: Bool) { #expect(passed, Comment(rawValue: id)) }
        let gb: Int64 = 1_000_000_000
        func format(_ bytes: Int64) -> String {
            let v = Double(bytes) / Double(gb)
            return v >= 100 || v == v.rounded() ? "\(Int(v.rounded())) GB" : String(format: "%.1f GB", v)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        cal.locale = Locale(identifier: "en_GB")
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
        }
        // Thursday 19 Nov 2026, 12:00 London. Week starts Monday 16 Nov.
        let now = date(2026, 11, 19)
        func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID() }

        // MARK: Rooms: record compatibility
        let legacy = #"[{"id":"00000000-0000-0000-0000-000000000001","accessFolderID":"f1","name":"Work","order":0}]"#.data(using: .utf8) ?? Data()
        let decoded = RoomRoomsDecoding.rooms(from: legacy)
        check("DMR-C01_LegacyRoomsJSONDecodes", decoded?.count == 1 && decoded?.first?.name == "Work")
        check("DMR-C02_LegacyDefaultsGlyphFolderColourDeveloper", decoded?.first?.resolvedGlyph == .folder && decoded?.first?.resolvedColour == .developer && decoded?.first?.budgetBytes == nil)
        let oneBad = #"[{"id":"00000000-0000-0000-0000-000000000001","accessFolderID":"f1","name":"Work","order":0},{"id":"nope"},{"id":"00000000-0000-0000-0000-000000000003","accessFolderID":"f3","name":"Photos","order":1,"glyph":"photo"}]"#.data(using: .utf8) ?? Data()
        check("DMR-C03_OneDamagedEntryKeepsTheOthers", RoomRoomsDecoding.rooms(from: oneBad)?.map(\.name) == ["Work", "Photos"])
        check("DMR-C04_NotAnArrayIsNil", RoomRoomsDecoding.rooms(from: Data("{}".utf8)) == nil)
        let unknownGlyph = RoomPinnedRoom(id: uuid(9), accessFolderID: "x", name: "X", order: 0, glyph: "flame", colour: "neon")
        check("DMR-C05_UnknownGlyphColourFallBackNotDropped", unknownGlyph.resolvedGlyph == .folder && unknownGlyph.resolvedColour == .developer)
        let roundTrip = try JSONDecoder().decode([RoomPinnedRoom].self, from: JSONEncoder().encode([unknownGlyph]))
        check("DMR-C06_RoundTripKeepsStoredStrings", roundTrip.first?.glyph == "flame")

        // MARK: Rooms: catalogue
        let work = RoomPinnedRoom(id: uuid(1), accessFolderID: "f1", name: "Work", order: 0)
        guard case let .added(two, added) = RoomRoomsCatalog.add([work], id: uuid(2), accessFolderID: "f2", name: "  suby-kmp \n", glyph: .hammer) else { Issue.record("Expected to add a room"); return }
        check("DMR-C07_PinAddsNotReplaces", two.map(\.name) == ["Work", "suby-kmp"] && added.order == 1)
        check("DMR-C08_PopoverRoomStaysFirst", RoomRoomsCatalog.popoverRoom(two)?.id == uuid(1))
        check("DMR-C09_SameFolderIsAlreadyPinned", RoomRoomsCatalog.add(two, id: uuid(3), accessFolderID: "f2", name: "dup") == .alreadyPinned(uuid(2)))
        let full = (0..<64).map { RoomPinnedRoom(id: uuid(100 + $0), accessFolderID: "a\($0)", name: "R\($0)", order: $0) }
        check("DMR-C10_SixtyFiveIsFull", RoomRoomsCatalog.add(full, id: uuid(999), accessFolderID: "new", name: "New") == .full)
        let removed = RoomRoomsCatalog.remove(two, id: uuid(1))
        check("DMR-C11_UnpinRenumbersOrder", removed.map(\.order) == [0] && removed.first?.id == uuid(2))
        let three = RoomRoomsCatalog.normalized(two + [RoomPinnedRoom(id: uuid(3), accessFolderID: "f3", name: "Photos", order: 7)])
        check("DMR-C12_NormalizeGivesDenseOrder", three.map(\.order) == [0, 1, 2])
        check("DMR-C13_MoveToFrontChangesPopoverRoom", RoomRoomsCatalog.popoverRoom(RoomRoomsCatalog.move(three, id: uuid(3), to: 0))?.id == uuid(3))
        check("DMR-C14_EmptyRenameKeepsName", RoomRoomsCatalog.rename(three, id: uuid(1), to: "   ").first?.name == "Work")
        check("DMR-C15_RenameTrimsAndCaps", RoomRoomsCatalog.rename(three, id: uuid(1), to: String(repeating: "a", count: 200)).first?.name.count == 80)
        check("DMR-C16_BudgetRange", RoomRoomsCatalog.setBudget(three, id: uuid(2), gb: 20)?[1].budgetBytes == 20 * gb
              && RoomRoomsCatalog.setBudget(three, id: uuid(2), gb: 0) == nil && RoomRoomsCatalog.setBudget(three, id: uuid(2), gb: 10_000) == nil)
        check("DMR-C17_BudgetNilClears", RoomRoomsCatalog.setBudget((RoomRoomsCatalog.setBudget(three, id: uuid(2), gb: 20) ?? []), id: uuid(2), gb: nil)?[1].budgetBytes == nil)
        var sizes: [String: RoomSizeLog] = [:]
        check("DMR-C18_PruneDropsUnpinnedSizes", RoomRoomsCatalog.prunedSizes(["\(uuid(1))": RoomSizeLog(), "\(uuid(77))": RoomSizeLog()], rooms: three).count == 1)

        // MARK: Rooms: measuring queue
        func log(_ points: [(Date, Int64, Bool)]) -> RoomSizeLog {
            var l = RoomSizeLog(); for p in points { l.record(RoomSizePoint(at: p.0, bytes: p.1, partial: p.2), calendar: cal) }; return l
        }
        sizes["\(uuid(1))"] = log([(now.addingTimeInterval(-7_200), 10 * gb, false)])
        sizes["\(uuid(2))"] = log([(now.addingTimeInterval(-600), 20 * gb, false)])
        check("DMR-C19_NeverMeasuredFirst", RoomRoomsMeasureQueue.next(rooms: three, sizes: sizes, unavailable: [], now: now) == uuid(3))
        check("DMR-C20_UnavailableSkipped", RoomRoomsMeasureQueue.next(rooms: three, sizes: sizes, unavailable: [uuid(3)], now: now) == uuid(1))
        sizes["\(uuid(3))"] = log([(now.addingTimeInterval(-60), 5 * gb, false)])
        sizes["\(uuid(1))"] = log([(now.addingTimeInterval(-3_599), 10 * gb, false)])
        check("DMR-C21_AllFreshMeansNothing", RoomRoomsMeasureQueue.next(rooms: three, sizes: sizes, unavailable: [], now: now) == nil)
        sizes["\(uuid(1))"] = log([(now.addingTimeInterval(-3_600), 10 * gb, false)])
        check("DMR-C22_ExactlyOneHourIsStale", RoomRoomsMeasureQueue.next(rooms: three, sizes: sizes, unavailable: [], now: now) == uuid(1))

        // MARK: Rooms: weeks, trend, sparkline
        let weekly = log([(date(2026, 8, 20), 9 * gb, false), (date(2026, 9, 1), 10 * gb, false), (date(2026, 10, 6), 12 * gb, false), (date(2026, 11, 13), 14 * gb, false),
                          (date(2026, 11, 17), 17 * gb, false), (date(2026, 11, 19, 9), 17_200_000_000, false)])
        let series = RoomRoomWeekly.series(weekly, now: now, calendar: cal)
        check("DMR-C23_TwelveWeeksCurrentLast", series.count == 12 && series.last??.bytes == 17_200_000_000)
        check("DMR-C24_UnmeasuredWeeksAreGapsNotZero", series.compactMap { $0 }.count == 4 && series.filter { $0 == nil }.count == 8)
        check("DMR-C25_OlderThanTwelveWeeksExcluded", !series.contains { $0?.bytes == 9 * gb } && series.first??.bytes == 10 * gb)
        let segs = RoomRoomWeekly.segments(series)
        check("DMR-C26_GapBreaksLine", segs.count == 3 && segs.allSatisfy { !$0.isEmpty })
        check("DMR-C27_SparklineInsideSlot", segs.joined().allSatisfy { $0.x >= 0 && $0.x <= 72 && $0.y >= 2 - 1e-9 && $0.y <= 18 + 1e-9 })
        check("DMR-C28_OneWeekDrawsNothing", RoomRoomWeekly.segments(RoomRoomWeekly.series(log([(now, 5 * gb, false)]), now: now, calendar: cal)).isEmpty)
        let trend = RoomRoomTrend.make(weekly, now: now, calendar: cal)
        check("DMR-C29_TrendSinceLastWeekReadsThisWeek", trend == .change(deltaBytes: 3_200_000_000, since: "Monday")
              && trend.text(format: format).emphasis == "+3.2 GB" && trend.text(format: format).rest == " this week")
        check("DMR-C30_NoPointThisWeekSaysNotMeasured", RoomRoomTrend.make(log([(date(2026, 11, 10), 5 * gb, false)]), now: now, calendar: cal) == .notMeasuredThisWeek)
        check("DMR-C31_NoLogNotMeasuredYet", RoomRoomTrend.make(nil, now: now, calendar: cal).text(format: format).rest == "Not measured yet")
        let midweek = RoomRoomTrend.make(log([(date(2026, 11, 17), 5 * gb, false), (date(2026, 11, 19), 7 * gb, false)]), now: now, calendar: cal)
        check("DMR-C32_FirstPointThisWeekNamesItsDay", midweek.text(format: format).rest == " since Tuesday")
        check("DMR-C33_PartialHidesDelta", RoomRoomTrend.make(log([(date(2026, 11, 13), 5 * gb, false), (now, 7 * gb, true)]), now: now, calendar: cal) == .partial)

        // MARK: Rooms: budget frame
        let under = try #require(RoomBudgetFrame.make(sizeBytes: 10 * gb, budgetBytes: 20 * gb))
        check("DMR-C34_UnderBudgetHalfFill", abs(under.fill.width - 27) < 1e-9 && under.overrun == nil && !under.frameOpenAtRight)
        let over = try #require(RoomBudgetFrame.make(sizeBytes: 21_600_000_000, budgetBytes: 20 * gb))
        check("DMR-C35_OverBudgetOpensFrameAmber", over.isOver && over.frameOpenAtRight && abs(over.fill.width - 54) < 1e-9
              && abs((over.overrun?.width ?? 0) - 54 * 0.08) < 1e-6 && abs((over.overrun?.minX ?? 0) - 55) < 1e-9)
        let way = try #require(RoomBudgetFrame.make(sizeBytes: 100 * gb, budgetBytes: 20 * gb))
        check("DMR-C36_OverrunStopsAtSlotEdge", abs((way.overrun?.maxX ?? 0) - 70) < 1e-9)
        check("DMR-C37_ExactBudgetNotOver", RoomBudgetFrame.make(sizeBytes: 20 * gb, budgetBytes: 20 * gb)?.isOver == false)
        check("DMR-C38_BudgetSpokenOver", RoomBudgetFrame.spoken(name: "suby-kmp", sizeBytes: 21_600_000_000, partial: false, budgetBytes: 20 * gb, format: format)
              == "suby-kmp: 21.6 GB of a 20 GB budget, 1.6 GB over")
        check("DMR-C39_PartialNeverPromisesLeft", !RoomBudgetFrame.spoken(name: "a", sizeBytes: 5 * gb, partial: true, budgetBytes: 20 * gb, format: format).contains("left"))
        check("DMR-C40_ZeroBudgetNoFrame", RoomBudgetFrame.make(sizeBytes: 1, budgetBytes: 0) == nil)

        // MARK: Rooms: chapter rows
        let five = (0..<5).map { RoomPinnedRoom(id: uuid(200 + $0), accessFolderID: "c\($0)", name: "R\($0)", order: $0) }
        let shown = RoomRoomsChapter.shown(five, editing: nil)
        check("DMR-C41_ThreeRowsAndMore", shown.rows.count == 3 && shown.more == 2)
        check("DMR-C42_EditedRoomTakesLastRow", RoomRoomsChapter.shown(five, editing: uuid(204)).rows.map(\.name) == ["R0", "R1", "R4"])
        var budgeted = RoomPinnedRoom(id: uuid(2), accessFolderID: "f2", name: "suby-kmp", order: 0); budgeted.budgetBytes = 20 * gb
        let budgetLog = log([(date(2026, 11, 13), 18_400_000_000, false), (date(2026, 11, 19, 9), 21_600_000_000, false)])
        let row = RoomRoomsChapter.row(budgeted, log: budgetLog, unavailable: false, now: now, calendar: cal, hidden: false, format: format)
        check("DMR-C43_BudgetReplacesSparkline", row.budget != nil && row.sparkline.isEmpty && row.size == "21.6 GB")
        check("DMR-C44_RowSpokenLabel", row.spoken == "suby-kmp: 21.6 GB of a 20 GB budget, 1.6 GB over, up 3.2 GB this week. Open in Disk Map.")
        let hiddenRow = RoomRoomsChapter.row(budgeted, log: budgetLog, unavailable: false, now: now, calendar: cal, hidden: true, format: format)
        check("DMR-C45_HideMasksNameSizeTrend", hiddenRow.name == "••••-•••" && hiddenRow.size == "••.• GB" && hiddenRow.trendEmphasis == "+•.• GB")
        check("DMR-C46_HideSpeaksNoNumberOrName", !hiddenRow.spoken.contains("suby") && hiddenRow.spoken.rangeOfCharacter(from: .decimalDigits) == nil)
        check("DMR-C47_HideKeepsGeometry", hiddenRow.budget == row.budget)
        let unread = RoomRoomsChapter.row(work, log: weekly, unavailable: true, now: now, calendar: cal, hidden: false, format: format)
        check("DMR-C48_UnavailableSaysNeedsAccessDash", unread.size == "—" && unread.trendRest == "Needs access" && unread.isUnavailable)
        let partialRow = RoomRoomsChapter.row(work, log: log([(now, 7 * gb, true)]), unavailable: false, now: now, calendar: cal, hidden: false, format: format)
        check("DMR-C49_PartialSizeGetsAtLeast", partialRow.size == "≥ 7 GB" && partialRow.spoken.contains("at least 7 GB"))

    }
}
