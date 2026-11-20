import Foundation
import Testing
@testable import RoomApp

@Suite("Popover pure model")
struct RoomPopoverModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private let gb: Int64 = 1_000_000_000
    private var now: Date { date(2026, 11, 17, 10) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func fmt(_ bytes: Int64) -> String {
        let v = Double(bytes) / 1e9
        return v >= 1 ? String(format: "%.1f GB", v) : String(format: "%.0f MB", Double(bytes) / 1e6)
    }

    @Test func sampleRing() {
        var ring = RoomMemorySampleRing()
        for i in 0..<200 { ring.append(Int64(i)) }
        #expect(ring.values.count == 180 && ring.values.first == 20 && ring.values.last == 199, "ring keeps the last 180 samples")
        #expect(zip(ring.values, ring.values.dropFirst()).allSatisfy { $0 < $1 }, "ring keeps order")
    }

    @Test func sparkline() {
        #expect(RoomSparkline.points([gb, 2 * gb], width: 312, height: 22).isEmpty, "sparkline draws nothing below three samples")
        let pts = RoomSparkline.points([14 * gb, 15 * gb, 16 * gb, 15 * gb], width: 312, height: 22)
        #expect(pts.first?.x == 0 && pts.last?.x == 312, "sparkline first point at x 0 and last at the width")
        #expect(pts.allSatisfy { $0.y >= 2 && $0.y <= 20 }, "sparkline y stays inside the 2 pt insets")
        #expect(pts[2].y == pts.map(\.y).min(), "sparkline: the highest value is the highest point (smallest y)")
        #expect(pts[0].y == 20, "sparkline: lowest value sits on the bottom inset")
        let flat = RoomSparkline.points([16 * gb, 16 * gb, 16 * gb], width: 100, height: 22)
        #expect(Set(flat.map(\.y)).count == 1 && flat[0].y == 11, "a flat hour is a flat line in the middle")
        let tiny = RoomSparkline.points([16_000_000_000, 16_100_000_000, 16_000_000_000], width: 100, height: 22)
        #expect(tiny.allSatisfy { $0.y > 8 && $0.y < 14 }, "a 100 MB wobble stays gentle (the 1 GB minimum span)")
    }

    @Test func cachesCard() {
        func check1(_ at: Date, bytes: Int64 = 8_400_000_000, partial: Bool = false) -> RoomCachesCheck { RoomCachesCheck(at: at, bytes: bytes, partial: partial) }
        #expect(check1(now).title(format: fmt) == "8.4 GB of caches can go", "title")
        #expect(check1(now, partial: true).title(format: fmt) == "≥ 8.4 GB of caches can go", "title after a partial scan has the ≥")
        #expect(check1(now, bytes: 0).title(format: fmt) == "No caches to clear", "title when there is nothing to clear")
        #expect(check1(now.addingTimeInterval(-20)).caption(now: now, calendar: calendar) == "Checked just now", "caption: just now")
        #expect(check1(date(2026, 11, 17, 6)).caption(now: now, calendar: calendar) == "Checked today", "caption: earlier today")
        #expect(check1(date(2026, 11, 16, 23)).caption(now: now, calendar: calendar) == "Checked yesterday", "caption: yesterday, even at 23:55")
        #expect(check1(date(2026, 11, 14, 9)).caption(now: now, calendar: calendar) == "Checked 3 days ago", "caption: 3 days ago")
        #expect(check1(date(2026, 11, 10, 9)).caption(now: now, calendar: calendar) == "Checked on 10 Nov", "caption: from 7 days on it is a date")
    }

    @Test func weekStart() {
        #expect(RoomSizeLog.weekStart(containing: now, calendar: calendar) == date(2026, 11, 16, 0), "week starts on Monday 16 Nov 00:00")
        #expect(RoomSizeLog.weekStart(containing: date(2026, 11, 22, 23), calendar: calendar) == date(2026, 11, 16, 0), "a Sunday belongs to the week that began the Monday before")
        var us = calendar; us.firstWeekday = 1
        #expect(RoomSizeLog.weekStart(containing: now, calendar: us) == date(2026, 11, 16, 0), "Monday start holds in a region whose week starts on Sunday")
    }

    @Test func roomCard() {
        func log(_ entries: [(Date, Int64, Bool)]) -> RoomSizeLog {
            var l = RoomSizeLog()
            for (at, bytes, partial) in entries { l.record(RoomSizePoint(at: at, bytes: bytes, partial: partial), calendar: calendar) }
            return l
        }
        let mockup = log([(date(2026, 11, 15, 20), 71_100_000_000, false), (date(2026, 11, 17, 9), 74_300_000_000, false)])
        #expect(mockup.sizeText(format: fmt) == "74.3 GB" && mockup.caption(now: now, calendar: calendar, format: fmt) == "+3.2 GB since Monday", "mockup: Work 74.3 GB, +3.2 GB since Monday")
        #expect(log([(date(2026, 11, 15, 20), 75_400_000_000, false), (date(2026, 11, 17, 9), 74_300_000_000, false)]).caption(now: now, calendar: calendar, format: fmt) == "−1.1 GB since Monday", "a loss reads −1.1 GB")
        #expect(log([(date(2026, 11, 15, 20), 74_300_000_000, false), (date(2026, 11, 17, 9), 74_305_000_000, false)]).caption(now: now, calendar: calendar, format: fmt) == "No change since Monday", "under 10 MB is No change")
        #expect(log([(date(2026, 11, 15, 20), 74_000_000_000, false), (date(2026, 11, 17, 9), 74_420_000_000, false)]).caption(now: now, calendar: calendar, format: fmt) == "+420 MB since Monday", "a small gain is in MB")
        #expect(log([(date(2026, 11, 17, 9), 74 * gb, false)]).caption(now: now, calendar: calendar, format: fmt) == "Tracking from today", "one point only: Tracking from today")
        let startedMonday = log([(date(2026, 11, 16, 9), 70 * gb, false), (date(2026, 11, 17, 9), 71 * gb, false)])
        #expect(startedMonday.change(now: now, calendar: calendar) == .since(label: "Monday", deltaBytes: gb), "first seen on Monday: the baseline is named Monday")
        let startedWed = log([(date(2026, 11, 18, 9), 70 * gb, false), (date(2026, 11, 19, 9), 72 * gb, false)])
        #expect(startedWed.caption(now: date(2026, 11, 19, 10), calendar: calendar, format: fmt) == "+2.0 GB since Wednesday", "first seen on Wednesday: the baseline is named Wednesday")
        let stale = log([(date(2026, 10, 20, 9), 60 * gb, false), (date(2026, 11, 17, 9), 74 * gb, false)])
        #expect(stale.change(now: now, calendar: calendar) == .tracking, "a point from weeks ago is never the baseline")
        let lastWeekOK = log([(date(2026, 11, 10, 9), 60 * gb, false), (date(2026, 11, 17, 9), 74 * gb, false)])
        #expect(lastWeekOK.change(now: now, calendar: calendar) == .since(label: "Monday", deltaBytes: 14 * gb), "a point 6 days before Monday still counts")
        let partialNow = log([(date(2026, 11, 15, 20), 71 * gb, false), (date(2026, 11, 17, 9), 74 * gb, true)])
        #expect(partialNow.sizeText(format: fmt) == "≥ 74.0 GB" && partialNow.caption(now: now, calendar: calendar, format: fmt) == "Some folders could not be read", "a partial current size reads ≥ and shows no delta")
        let partialBase = log([(date(2026, 11, 15, 20), 71 * gb, true), (date(2026, 11, 17, 9), 74 * gb, false)])
        #expect(partialBase.change(now: now, calendar: calendar) == .partial, "a partial baseline shows no delta either")
        #expect(RoomSizeLog().sizeText(format: fmt) == "—", "nothing measured yet shows —")
        #expect(log([(date(2026, 11, 12, 9), 70 * gb, false)]).change(now: now, calendar: calendar) == .tracking, "no point this week yet: tracking")
    }

    @Test func recording() {
        var daily = RoomSizeLog()
        daily.record(RoomSizePoint(at: date(2026, 11, 17, 8), bytes: gb, partial: false), calendar: calendar)
        daily.record(RoomSizePoint(at: date(2026, 11, 17, 20), bytes: 2 * gb, partial: false), calendar: calendar)
        #expect(daily.points.count == 1 && daily.points[0].bytes == 2 * gb, "one point per day: the last of the day wins")
        daily.record(RoomSizePoint(at: date(2026, 11, 17, 7), bytes: 9 * gb, partial: false), calendar: calendar)
        #expect(daily.points.count == 1 && daily.points[0].bytes == 2 * gb, "a clock that went backwards is ignored")
        var long = RoomSizeLog()
        for d in 0..<150 { long.record(RoomSizePoint(at: calendar.date(byAdding: .day, value: d, to: date(2026, 1, 1))!, bytes: gb, partial: false), calendar: calendar) }
        #expect(long.points.count <= 121 && long.points.count >= 120, "retention keeps 120 days")
    }
}
