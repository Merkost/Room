import Foundation
import Observation

nonisolated enum RoomOpenOn: String, CaseIterable, Sendable {
    case overview, last

    static func resolve(preference: String, last: String?) -> RoomDestination {
        guard preference == Self.last.rawValue,
              let last, let destination = RoomDestination(rawValue: last) else { return .overview }
        switch destination {
        case .overview, .clean, .memory, .disk, .developer: return destination
        case .activity: return .overview
        }
    }
}

/// The launch preference is resolved once, even if SwiftUI recreates the window content.
@Observable @MainActor
final class RoomWindowNavigation {
    private(set) var destination: RoomDestination
    private(set) var needsWelcome: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destination = RoomOpenOn.resolve(
            preference: defaults.string(forKey: "RoomOpenOn") ?? RoomOpenOn.last.rawValue,
            last: defaults.string(forKey: "RoomLastDestination"))
        needsWelcome = defaults.integer(forKey: "RoomOnboardingVersion") < 1
    }

    func select(_ destination: RoomDestination) {
        guard self.destination != destination else { return }
        self.destination = destination
        defaults.set(destination.rawValue, forKey: "RoomLastDestination")
    }

    func dismissWelcome() {
        needsWelcome = false
        defaults.set(1, forKey: "RoomOnboardingVersion")
    }

    func consumeRequest(from insights: RoomInsightsModel) {
        guard let request = insights.requestedDestination else { return }
        switch request {
        case .overview: select(.overview)
        case .clean: select(.clean)
        case .memory: select(.memory)
        case .disk: select(.disk)
        }
        insights.requestedDestination = nil
    }
}
