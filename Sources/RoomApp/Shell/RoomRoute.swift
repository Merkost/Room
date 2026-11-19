import Foundation

/// Where the detail column is. Screens keep their stored raw values; Rooms and saved views are routes, not screens.
nonisolated enum RoomRoute: Hashable, Sendable, Codable {
    case screen(RoomDestination)
    case room(UUID)               // Disk Map rooted at a pinned Room (Job D row, Job B map)
    case savedView(UUID)          // a saved Disk Map view (Job B)

    /// The sidebar row that shows selected for this route.
    var highlightedScreen: RoomDestination? {
        switch self { case .screen(let d): d; case .room, .savedView: nil }
    }
    /// The raw value Open on › Last place may restore. Rooms and views restore as Disk Map (their bookmark may be gone).
    var restorableRaw: String {
        switch self {
        case .screen(let d): d.rawValue
        case .room, .savedView: RoomDestination.disk.rawValue
        }
    }
    // Codable by hand so the stored form is readable and stable ("screen:disk", "room:<uuid>").
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let bad = DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: raw))
        guard parts.count == 2 else { throw bad }
        if parts[0] == "screen", let d = RoomDestination(rawValue: parts[1]) { self = .screen(d) }
        else if parts[0] == "room", let id = UUID(uuidString: parts[1]) { self = .room(id) }
        else if parts[0] == "view", let id = UUID(uuidString: parts[1]) { self = .savedView(id) }
        else { throw bad }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .screen(let d): try c.encode("screen:\(d.rawValue)")
        case .room(let id): try c.encode("room:\(id.uuidString)")
        case .savedView(let id): try c.encode("view:\(id.uuidString)")
        }
    }
}

/// How a selection was made. Keyboard selections (⌘1–5, arrows, ⌘[ ⌘]) never animate (14 §5).
nonisolated enum RoomSelectionOrigin: Sendable { case pointer, keyboard, programmatic }
