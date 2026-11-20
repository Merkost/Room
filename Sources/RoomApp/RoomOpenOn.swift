import Foundation

nonisolated enum RoomOpenOn: String, CaseIterable, Sendable {
    case overview, last

    static func resolve(preference: String, last: String?) -> RoomDestination {
        guard preference == Self.last.rawValue,
              let last, let destination = RoomDestination(rawValue: last) else { return .clean }
        switch destination {
        case .clean, .memory, .disk, .developer: return destination
        case .activity: return .clean
        }
    }
}
