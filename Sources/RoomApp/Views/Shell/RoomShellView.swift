import SwiftUI

struct RoomShellView<Detail: View>: View {
    let navigation: RoomWindowNavigation
    let rooms: RoomRoomsModel
    let insights: RoomInsightsModel
    let selectRoom: (UUID) -> Void
    var savedViews: RoomSavedViewsStore? = nil
    var selectSavedView: (UUID) -> Void = { _ in }
    var sidebarValues = RoomSidebarValue.Input()
    var couldGoBytes: Int64 = 0
    var rowActivity: [RoomDestination: RoomRowActivity] = [:]
    var stopPlace: (RoomDestination) -> Void = { _ in }
    var openGoTo: (_ keyboard: Bool) -> Void = { _ in }
    @ViewBuilder var detail: () -> Detail

    @Environment(\.roomMotion) private var motion
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var goalBytes = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @State private var sidebarMode = RoomSidebarMode.labelled
    @State private var showsSidebarLabels = true

    /// nav-v3 window: the sidebar is a floating glass panel inset 8 pt from the window edge (mockup `.side`), the pane
    /// fills the rest. The fold button (and ⌃⌘S) folds the panel to its 62 pt rail with the UI spring; below 900 pt
    /// the window folds it on its own.
    var body: some View {
        GeometryReader { geometry in
            let target = RoomSidebarLayout.mode(windowWidth: geometry.size.width, userPrefersIcons: navigation.prefersSidebarIcons)
            HStack(spacing: 0) {
                RoomSidebar(navigation: navigation, rooms: rooms,
                            mode: sidebarMode, showsLabels: showsSidebarLabels,
                            values: sidebarValues, plate: plate,
                            canOpenRooms: insights.canChooseDiskLocation, openRoom: selectRoom,
                            savedViews: savedViews, openSavedView: selectSavedView,
                            activity: rowActivity, stop: stopPlace,
                            openGoTo: openGoTo, fold: { navigation.toggleSidebarLabels() })
                    .frame(width: RoomSidebarLayout.width(sidebarMode))
                    .frame(maxHeight: .infinity)
                    .background { RoomSidebarPanel() }
                    .padding(RoomTokens.Nav.panelMargin)
                    .zIndex(2)
                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(RoomTokens.Surface.canvas)
            .task(id: target) {
                guard target != sidebarMode || showsSidebarLabels != (target == .labelled) else { return }
                changeMode(to: target)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(RoomTokens.Surface.canvas.ignoresSafeArea())
        // An empty, see-through unified toolbar: it only gives the title bar its 52 pt so the traffic lights sit in
        // the sidebar panel's top row. The pane draws its own bar.
        .toolbar {
            ToolbarItem(placement: .navigation) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 800, minHeight: 650)
    }

    private var plate: RoomSidebarPlate {
        let capacity = insights.volumeCapacity
        let foot = RoomSidebarFoot.make(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes,
                                        goalBytes: goalEnabled ? Int64(goalBytes) : nil,
                                        volumeName: capacity?.volumeName, hidden: false, format: RoomFormat.gb)
        return RoomSidebarPlate(freeBytes: capacity?.freeBytes, capacityBytes: capacity?.capacityBytes,
                                couldGoBytes: couldGoBytes, belowGoal: foot.belowGoal)
    }

    /// Width on the UI spring (mockup `transition: width var(--t) var(--spring)`), labels fading over 160 ms at the
    /// same time. Reduce Motion keeps the fade and drops the travel.
    @MainActor private func changeMode(to target: RoomSidebarMode) {
        let labels = target == .labelled
        let keyboard = navigation.sidebarFoldByKeyboard
        withAnimation(keyboard ? nil : motion.animation(RoomTokens.Motion.ui, fallback: nil)) { sidebarMode = target }
        withAnimation(keyboard ? nil : motion.animation(RoomTokens.Motion.labels, fallback: RoomTokens.Motion.fade)) {
            showsSidebarLabels = labels
        }
    }
}

/// The sidebar's glass: a rounded panel with a top highlight, a hairline and a soft drop shadow (mockup `.side`).
struct RoomSidebarPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Nav.panelRadius, style: .continuous)
        shape.fill(RoomTokens.Surface.glass)
            .overlay(shape.strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
            .overlay(alignment: .top) {
                shape.inset(by: 0.5).trim(from: 0.0, to: 1.0)
                    .stroke(LinearGradient(colors: [RoomTokens.Surface.glassEdge, .clear], startPoint: .top,
                                           endPoint: UnitPoint(x: 0.5, y: 0.04)), lineWidth: 0.5)
            }
            .shadow(color: RoomTokens.Surface.panelShadow, radius: RoomTokens.Nav.panelShadowRadius,
                    y: RoomTokens.Nav.panelShadowY)
    }
}
