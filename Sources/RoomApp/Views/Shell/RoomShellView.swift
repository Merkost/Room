import SwiftUI

/// The window: the screen at full width, with the dock floating above its bottom edge. Screens publish their next step
/// with `roomDock`; the dock draws it.
struct RoomShellView<Detail: View>: View {
    let navigation: RoomWindowNavigation
    let insights: RoomInsightsModel
    var dockValues = RoomPlaceValue.Input()
    var activity: [RoomDestination: RoomRowActivity] = [:]
    var stopPlace: (RoomDestination) -> Void = { _ in }
    var openGoTo: (_ keyboard: Bool) -> Void = { _ in }
    @ViewBuilder var detail: () -> Detail

    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var goalBytes = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true

    var body: some View {
        detail()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(RoomDockActionKey.self, alignment: .bottom) { actions in
                RoomDock(navigation: navigation, values: dockValues, activity: activity, belowGoal: belowGoal,
                         actions: actions, stop: stopPlace, openGoTo: openGoTo)
                    .padding(.bottom, RoomTokens.Dock.margin)
            }
            .background(RoomTokens.Surface.canvas)
            .ignoresSafeArea(.container, edges: .top)
            .background(RoomTokens.Surface.canvas.ignoresSafeArea())
            // An empty, see-through unified toolbar: it only gives the title bar its 52 pt so the traffic lights
            // centre on the pane's own bar.
            .toolbar {
                ToolbarItem(placement: .navigation) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                    .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .frame(minWidth: 800, minHeight: 650)
    }

    private var belowGoal: Bool {
        let capacity = insights.volumeCapacity
        return RoomSidebarFoot.make(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes,
                                    goalBytes: goalEnabled ? Int64(goalBytes) : nil,
                                    volumeName: capacity?.volumeName, hidden: false, format: RoomFormat.gb).belowGoal
    }
}
