import Foundation
import Observation
import SwiftUI

nonisolated enum RoomOpenOn: String, CaseIterable, Sendable {
    case overview, last

    static func resolve(preference: String, last: String?) -> RoomDestination {
        guard preference == Self.last.rawValue,
              let last, let destination = RoomDestination(rawValue: last) else { return .overview }
        return destination
    }
}

/// The launch preference is resolved once, even if SwiftUI recreates the window content.
@Observable @MainActor
final class RoomWindowNavigation {
    private(set) var history: RoomNavigationHistory
    private(set) var prefersSidebarIcons: Bool
    var route: RoomRoute { history.current }
    var destination: RoomDestination { route.highlightedScreen ?? .disk }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    private(set) var needsWelcome: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let destination = RoomOpenOn.resolve(
            preference: defaults.string(forKey: "RoomOpenOn") ?? RoomOpenOn.last.rawValue,
            last: defaults.string(forKey: "RoomLastDestination"))
        history = RoomNavigationHistory(current: .screen(destination))
        prefersSidebarIcons = defaults.bool(forKey: "RoomSidebarIconsOnly")
        needsWelcome = defaults.integer(forKey: "RoomOnboardingVersion") < 1
    }

    func select(_ destination: RoomDestination) {
        select(.screen(destination), origin: .programmatic)
    }

    func select(_ route: RoomRoute, origin: RoomSelectionOrigin) {
        guard self.route != route else { return }
        change(origin) { history.visit(route) }
    }

    func back() { change(.keyboard) { history.goBack() } }
    func forward() { change(.keyboard) { history.goForward() } }

    func removeRoute(_ route: RoomRoute) {
        change(.programmatic) { history.remove(route, fallback: .screen(.disk)) }
    }

    func toggleSidebarLabels() {
        prefersSidebarIcons.toggle()
        defaults.set(prefersSidebarIcons, forKey: "RoomSidebarIconsOnly")
    }

    func transaction(for origin: RoomSelectionOrigin) -> Transaction {
        var transaction = Transaction(animation: nil)
        if case .keyboard = origin { transaction.disablesAnimations = true }
        return transaction
    }

    private func change(_ origin: RoomSelectionOrigin, operation: () -> Void) {
        if case .keyboard = origin {
            withTransaction(transaction(for: origin), operation)
        } else {
            operation()
        }
        defaults.set(route.restorableRaw, forKey: "RoomLastDestination")
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
