import Foundation

nonisolated enum RoomGreetingName {
    /// PE-1. `givenName` wraps PersonNameComponentsFormatter(...).givenName in the app; injected for tests.
    /// Read at render time, never stored, never sent.
    static func resolve(fullName: String, loginName: String, givenName: (String) -> String?) -> String? {
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return nil }
        let candidate: String
        if let given = givenName(full)?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty {
            candidate = given
        } else {
            candidate = full.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        }
        guard !candidate.isEmpty, candidate.compare(loginName, options: .caseInsensitive) != .orderedSame else { return nil }
        return String(candidate.prefix(40))
    }

    /// nil = no greeting line at all (switch off: the first screen has four groups, PE-3).
    /// Hide drops the name (PE-4); no name → OVB's generic "Good morning.".
    static func line(hour: Int, enabled: Bool, name: String?, hidden: Bool) -> String? {
        guard enabled else { return nil }
        let generic = RoomOverviewCopy.greeting(hour: hour)
        guard let name, !hidden else { return generic }
        switch hour {   // same boundaries as RoomOverviewCopy.greeting(hour:): 5–11 / 12–17 / 18–4
        case 5..<12: return "Good morning, \(name)"
        case 12..<18: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
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
    static let greetingKey = "RoomGreetingEnabled"       // default true
    static let roomsChapterKey = "RoomChapterRoomsShown" // spec 04 `RoomChapters` narrowed to the one built chapter
    var greetingEnabled = true
    var roomsChapterShown = true

    /// Absent keys read as defaults; a stored non-Bool is ignored, never crashes.
    static func read(_ values: [String: Any]) -> Self {
        var p = Self()
        if let g = values[greetingKey] as? Bool { p.greetingEnabled = g }
        if let r = values[roomsChapterKey] as? Bool { p.roomsChapterShown = r }
        return p
    }

    /// "Reset Overview" restores these defaults and the accent/goal defaults owned elsewhere. It never forgets Rooms,
    /// budgets, approvals or history: those are records, not preferences.
    static let resetKeys: [String] = [greetingKey, roomsChapterKey, "RoomAccent"]

    /// The chapter is drawn only with something true to show: at least one Room, or the empty line with Add a Room…
    /// The receipt line (05 §8) is not part of this chapter until the Job C ledger exists.
    func showsRoomsChapter(roomCount: Int, canPin: Bool) -> Bool { roomsChapterShown && (roomCount > 0 || canPin) }
}
