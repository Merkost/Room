#if DEBUG
import Observation
import SwiftUI

@Observable
final class RoomDebugMenuBarState {
    /// One state shared by the menu and the status item, so the menu can observe it before the monitor exists.
    static let shared = RoomDebugMenuBarState()
    var scenario: RoomDebugMenuBarScenario = .live
}

struct RoomDebugMenuCommands: Commands {
    var monitor: () -> RoomStatusMonitor?

    var body: some Commands {
        CommandMenu("Debug") {
            Menu("Menu bar state") {
                ForEach(RoomDebugMenuBarScenario.allCases, id: \.self) { scenario in
                    Toggle(scenario.menuTitle, isOn: Binding(
                        get: { RoomDebugMenuBarState.shared.scenario == scenario },
                        set: { selected in
                            if selected { monitor()?.setDebugMenuBarScenario(scenario) }
                        }))
                }
            }
        }
    }
}

extension RoomDebugMenuBarScenario {
    var menuTitle: String {
        switch self {
        case .live: "Live"
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .critical: "Critical"
        case .diskBelowGoal: "Disk below goal"
        case .bothElevatedBelowGoal: "Both (elevated and below goal)"
        case .iconOnlyElevated: "Icon only (elevated)"
        }
    }
}
#endif
