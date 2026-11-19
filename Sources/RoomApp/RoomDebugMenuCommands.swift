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
    let windowContext: RoomCommandWindowContext
    let enabled: Bool
    var monitor: () -> RoomStatusMonitor?

    var body: some Commands {
        CommandMenu(RoomMenuModel.Section.debug.title) {
            if enabled, windowContext.window != .modal {
                Menu(RoomMenuModel.ID.debugState.title) {
                    ForEach(RoomDebugMenuBarScenario.allCases, id: \.self) { scenario in
                        Toggle(scenario.menuTitle, isOn: Binding(
                            get: { RoomDebugMenuBarState.shared.scenario == scenario },
                            set: { selected in
                                if selected, RoomCommandWindowContext.current != .modal {
                                    monitor()?.setDebugMenuBarScenario(scenario)
                                }
                            }))
                    }
                }
            } else {
                Button(RoomMenuModel.ID.debugState.title) {}.disabled(true)
            }
        }
    }
}

extension RoomDebugMenuBarScenario {
    var menuTitle: String {
        switch self {
        case .live: RoomMenuModel.ID.debugLive.title
        case .normal: RoomMenuModel.ID.debugNormal.title
        case .elevated: RoomMenuModel.ID.debugElevated.title
        case .critical: RoomMenuModel.ID.debugCritical.title
        case .diskBelowGoal: RoomMenuModel.ID.debugBelowGoal.title
        case .bothElevatedBelowGoal: RoomMenuModel.ID.debugBoth.title
        case .bothStacked: RoomMenuModel.ID.debugStacked.title
        case .iconOnlyElevated: RoomMenuModel.ID.debugIcon.title
        }
    }
}
#endif
