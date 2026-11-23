import Foundation

nonisolated enum RoomGreetingName {
    /// The generic line for the hour; no name, no switch (the "Greet me by name" setting was removed).
    static func line(hour: Int) -> String {
        RoomOverviewCopy.greeting(hour: hour)
    }

    /// PE-2: the single scheduled wake-up is the next of 05:00, 12:00, 18:00 local; no polling.
    static func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let today = [5, 12, 18].compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        if let next = today.first(where: { $0 > date }) { return next }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return calendar.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow)
    }
}

/// Customise (spec 05 §9) as built in DMR-3: only controls whose feature exists. Keys are the spec 04 / 12 keys.
nonisolated struct RoomOverviewPreferences: Equatable, Sendable {
    static let densityKey = "RoomDensity"
    static let recentReceiptKey = "RoomChapterRecentShown"
    static let roomsChapterKey = "RoomChapterRoomsShown" // spec 04 `RoomChapters` narrowed to the one built chapter
    var roomsChapterShown = true

    /// Absent keys read as defaults; a stored non-Bool is ignored, never crashes.
    static func read(_ values: [String: Any]) -> Self {
        var p = Self()
        if let r = values[roomsChapterKey] as? Bool { p.roomsChapterShown = r }
        return p
    }

    /// "Reset Overview" restores these defaults and the accent/goal defaults owned elsewhere. It never forgets Rooms,
    /// budgets, approvals or history: those are records, not preferences.
    static let resetKeys: [String] = [roomsChapterKey, "RoomAccent"]

    /// An established Overview keeps its empty chapter visible while the Add action is busy.
    func showsRoomsChapter(roomCount: Int, allowsEmptyChapter: Bool) -> Bool {
        roomsChapterShown && (roomCount > 0 || allowsEmptyChapter)
    }
}

nonisolated enum RoomOverviewStyle: String, CaseIterable, Sendable {
    case dots, rooms
    static let preferenceKey = "RoomOverviewStyle"
    var title: String {
        switch self {
        case .dots: String(localized: "style.dots", defaultValue: "Dots", table: "Overview", bundle: RoomCopy.bundle)
        case .rooms: String(localized: "style.rooms", defaultValue: "Rooms", table: "Overview", bundle: RoomCopy.bundle)
        }
    }
    static func isAvailable(homeKinds: RoomHomeKinds?) -> Bool { homeKinds?.kinds.isEmpty == false }
}
