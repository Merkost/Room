import SwiftUI

struct RoomShellView<Detail: View>: View {
    let navigation: RoomWindowNavigation
    let rooms: RoomRoomsModel
    let insights: RoomInsightsModel
    let selectRoom: (UUID) -> Void
    @ViewBuilder var detail: () -> Detail

    @Environment(\.roomMotion) private var motion
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var goalBytes = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @State private var sidebarMode = RoomSidebarMode.labelled
    @State private var showsSidebarLabels = true

    var body: some View {
        GeometryReader { geometry in
            let target = RoomSidebarLayout.mode(windowWidth: geometry.size.width, userPrefersIcons: navigation.prefersSidebarIcons)
            NavigationSplitView(columnVisibility: .constant(.all)) {
                RoomSidebar(navigation: navigation, rooms: rooms,
                            mode: sidebarMode, showsLabels: showsSidebarLabels,
                            foot: foot, canOpenRooms: insights.canChooseDiskLocation, openRoom: selectRoom)
                    .navigationSplitViewColumnWidth(RoomSidebarLayout.width(sidebarMode))
            } detail: {
                detail()
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
            .task(id: target) {
                guard target != sidebarMode || showsSidebarLabels != (target == .labelled) else { return }
                await changeMode(to: target)
            }
        }
        .frame(minWidth: 800, minHeight: 650)
    }

    private var foot: RoomSidebarFoot {
        let capacity = insights.volumeCapacity
        return RoomSidebarFoot.make(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes,
                                    goalBytes: goalEnabled ? Int64(goalBytes) : nil,
                                    volumeName: capacity?.volumeName, hidden: false, format: RoomFormat.bytes)
    }

    @MainActor private func changeMode(to target: RoomSidebarMode) async {
        let labels = target == .labelled
        let animateLabels = motion.animation(RoomTokens.Motion.sidebarLabels, fallback: RoomTokens.Motion.fade)
        if !labels {
            withAnimation(animateLabels) { showsSidebarLabels = false }
            if animateLabels != nil { try? await Task.sleep(for: .milliseconds(110)) }
            guard !Task.isCancelled else { return }
        }
        withAnimation(motion.animation(RoomTokens.Motion.sidebarWidth, fallback: nil)) { sidebarMode = target }
        if labels {
            if motion.animation(RoomTokens.Motion.sidebarWidth, fallback: nil) != nil {
                try? await Task.sleep(for: .milliseconds(160))
            }
            guard !Task.isCancelled else { return }
            withAnimation(animateLabels) { showsSidebarLabels = true }
        }
    }
}
