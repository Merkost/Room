import SwiftUI

/// First-run task selection only. Access stays contextual after this sheet closes.
enum RoomOnboardingTask: String, CaseIterable, Identifiable {
    case storage, memory, disk, developer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .storage: "Review caches"
        case .memory: "Understand memory"
        case .disk: "Explore disk space"
        case .developer: "Review developer resources"
        }
    }
    var detail: String {
        switch self {
        case .storage: "Measure first, then choose what to clear."
        case .memory: "See pressure, compression, and swap."
        case .disk: "Find large folders and hidden files."
        case .developer: "Connect devices and build versions to projects."
        }
    }
    var symbol: String {
        switch self {
        case .storage: "sparkles"
        case .memory: "memorychip"
        case .disk: "square.grid.2x2"
        case .developer: "shippingbox"
        }
    }
    var actionTitle: String {
        switch self {
        case .storage: "Open Clean"
        case .memory: "Open Memory"
        case .disk: "Open Disk Map"
        case .developer: "Open Developer"
        }
    }
}

struct RoomOnboardingView: View {
    let onFinish: (RoomOnboardingTask?) -> Void
    var motion = RoomMotionPolicy()
    @State private var page = 0
    @State private var selectedTask = RoomOnboardingTask.storage

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            HStack(spacing: RoomSpace.small) {
                RoomMark().fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: 25, height: 25).accessibilityHidden(true)
                Text("Room").font(RoomTypography.sectionTitle)
                Spacer()
                Text("\(page + 1) of 2").font(RoomTypography.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Introduction, step \(page + 1) of 2")
            }

            RoomPageHeader(title: page == 0 ? "Where shall we start?" : "Always in your hands.",
                           subtitle: page == 0 ? "Choose your first task. You can switch anytime." : "Scan first. Review changes. Keep recovery close.")

            ZStack {
                if page == 0 {
                    taskSelection.transition(motion.pageTransition)
                } else {
                    safeguards.transition(motion.pageTransition)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)

            Spacer(minLength: 0)
            HStack(spacing: RoomSpace.standard) {
                Button("Skip") { onFinish(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("RoomOnboardingSkip")
                if page > 0 {
                    Button("Back") { move(to: 0) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityIdentifier("RoomOnboardingBack")
                }
                Spacer()
                Button {
                    if page == 0 { move(to: 1) } else { onFinish(selectedTask) }
                } label: {
                    Label(page == 0 ? "Continue" : selectedTask.actionTitle, systemImage: "arrow.right")
                        .font(RoomTypography.bodyEmphasis)
                        .padding(.horizontal, RoomSpace.small)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(page == 0 ? "RoomOnboardingContinue" : "RoomOnboardingFinish")
            }
            .font(RoomTypography.body)
        }
        .padding(32)
        .frame(width: 620, height: 570)
        .background(RoomSurface.canvas)
        .animation(motion.selection, value: selectedTask)
        .animation(motion.disclosure, value: page)
    }

    private var taskSelection: some View {
        RoomContentGroup(inset: RoomSpace.small, spacing: 2) {
            ForEach(RoomOnboardingTask.allCases) { task in
                Button { selectedTask = task } label: {
                    HStack(spacing: RoomSpace.standard) {
                        Image(systemName: task.symbol)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: RoomSpace.micro) {
                            Text(task.title).font(RoomTypography.bodyEmphasis).foregroundStyle(.primary)
                            Text(task.detail).font(RoomTypography.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: selectedTask == task ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(selectedTask == task ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(RoomSpace.compact)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(selectedTask == task ? RoomSurface.selection : .clear,
                                in: RoundedRectangle(cornerRadius: RoomRadius.row))
                    .contentShape(RoundedRectangle(cornerRadius: RoomRadius.row))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.title)
                .accessibilityHint(task.detail)
                .accessibilityValue(selectedTask == task ? "Selected" : "")
                .accessibilityAddTraits(selectedTask == task ? [.isSelected] : [])
                .accessibilityIdentifier("RoomOnboardingTask-\(task.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your first task")
    }

    private var safeguards: some View {
        VStack(alignment: .leading, spacing: RoomSpace.standard) {
            Label(selectedTask.title, systemImage: selectedTask.symbol)
                .font(RoomTypography.bodyEmphasis)
                .foregroundStyle(.secondary)
            RoomContentGroup(spacing: RoomSpace.section) {
                safeguard(symbol: "folder.badge.plus", title: "Access when you need it",
                          detail: "Choose folders in Room. macOS manages protected locations.")
                #if ROOM_APP_STORE
                safeguard(symbol: "trash", title: "Review supported cache files",
                          detail: "Approve exact folders before a move. Files stay recoverable in Trash.")
                safeguard(symbol: "memorychip", title: "Understand your memory",
                          detail: "See pressure and swap. Suggestions do not close your apps.")
                #else
                safeguard(symbol: "trash", title: "Review every cleanup",
                          detail: "Choose caches to move to Trash. A recovery record stays in Room.")
                safeguard(symbol: "memorychip", title: "Apps stay under your control",
                          detail: "Closing an app requires your review. Unsaved-work prompts remain.")
                #endif
            }
        }
    }

    private func safeguard(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: RoomSpace.standard) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary).frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomSpace.micro) {
                Text(title).font(RoomTypography.bodyEmphasis)
                Text(detail).font(RoomTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func move(to nextPage: Int) {
        withAnimation(motion.disclosure) { page = nextPage }
    }
}
