import SwiftUI

/// Developer's rooms (Rooms, Matrix, Devices, Storage, AI Tools and, in Direct, Worktrees) under its row, only while
/// Developer is the open place, so the column stays short everywhere else.
struct RoomSidebarDeveloperRooms: View {
    let open: Bool
    let selected: RoomDeveloperSection
    let select: (RoomDeveloperSection) -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if open {
                ForEach(Array(RoomDeveloperSection.allCases.enumerated()), id: \.element) { index, section in
                    kid(section)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: motion.isFull ? -4 : 0))
                                .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade)?
                                    .delay(Double(index) * RoomTokens.Nav.kidStagger)),
                            removal: .opacity))
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Developer rooms")
    }

    private func kid(_ section: RoomDeveloperSection) -> some View {
        let on = section == selected
        return Button {
            select(section)
        } label: {
            HStack(spacing: 0) {
                Circle()
                    .fill(on ? accent.text : Color.clear)
                    .overlay(Circle().strokeBorder(on ? Color.clear : RoomTokens.Ink.tertiary, lineWidth: 1))
                    .frame(width: RoomTokens.Nav.kidDot, height: RoomTokens.Nav.kidDot)
                    .scaleEffect(on && motion.isFull ? 1.3 : 1)
                    .frame(width: RoomTokens.Nav.tile)
                    .padding(.leading, RoomTokens.Nav.rowInsetLeading)
                Text(section.rawValue)
                    .font(on ? RoomTokens.Nav.kidSelected : RoomTokens.Nav.kid)
                    .foregroundStyle(on ? RoomTokens.Ink.graphite : RoomTokens.Ink.secondary)
                    .padding(.leading, RoomTokens.Nav.rowColumnGap)
                Spacer(minLength: 0)
            }
            .frame(height: RoomTokens.Nav.kidHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(motion.animation(RoomTokens.Motion.check, fallback: nil), value: on)
        .accessibilityLabel("Developer, \(section.rawValue)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
