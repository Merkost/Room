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
    @ViewBuilder var detail: () -> Detail

    @Environment(\.roomMotion) private var motion
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var goalBytes = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @State private var sidebarMode = RoomSidebarMode.labelled
    @State private var showsSidebarLabels = true
    /// The toolbar button (and ⌃⌘S) collapses and restores the sidebar; it used to be pinned open, so the button did nothing.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        GeometryReader { geometry in
            let target = RoomSidebarLayout.mode(windowWidth: geometry.size.width, userPrefersIcons: navigation.prefersSidebarIcons)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RoomSidebar(navigation: navigation, rooms: rooms,
                            mode: sidebarMode, showsLabels: showsSidebarLabels,
                            values: sidebarValues, plate: plate,
                            canOpenRooms: insights.canChooseDiskLocation, openRoom: selectRoom,
                            savedViews: savedViews, openSavedView: selectSavedView)
                    .navigationSplitViewColumnWidth(RoomSidebarLayout.width(sidebarMode))
            } detail: {
                detail()
            }
            .navigationSplitViewStyle(.balanced)
            .task(id: target) {
                guard target != sidebarMode || showsSidebarLabels != (target == .labelled) else { return }
                await changeMode(to: target)
            }
        }
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

    @MainActor private func changeMode(to target: RoomSidebarMode) async {
        let labels = target == .labelled
        let animateLabels = motion.animation(RoomTokens.Motion.quick, fallback: RoomTokens.Motion.fade)
        if !labels {
            withAnimation(animateLabels) { showsSidebarLabels = false }
            if animateLabels != nil { try? await Task.sleep(for: .milliseconds(110)) }
            guard !Task.isCancelled else { return }
        }
        withAnimation(motion.animation(RoomTokens.Motion.standard, fallback: nil)) { sidebarMode = target }
        if labels {
            if motion.animation(RoomTokens.Motion.standard, fallback: nil) != nil {
                try? await Task.sleep(for: .milliseconds(160))
            }
            guard !Task.isCancelled else { return }
            withAnimation(animateLabels) { showsSidebarLabels = true }
        }
    }
}
