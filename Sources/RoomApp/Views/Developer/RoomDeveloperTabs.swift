import SwiftUI

/// Developer's rooms (Rooms, Matrix, Devices, Storage, AI Tools and, in Direct, Worktrees) as one row on the page
/// itself, each with its size once it has been read. The sidebar keeps a single Developer row.
struct RoomDeveloperTabs: View {
    let selected: RoomDeveloperSection
    /// Sizes for the rooms that have been read; a room without an entry shows no figure yet.
    let values: [RoomDeveloperSection: String]
    let select: (RoomDeveloperSection) -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: RoomTokens.Space.group + RoomTokens.Space.row) {
                ForEach(RoomDeveloperSection.allCases, id: \.self) { section in tab(section) }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RoomTokens.Surface.line).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Developer rooms")
    }

    private func tab(_ section: RoomDeveloperSection) -> some View {
        let on = section == selected
        let value = values[section]
        return Button {
            select(section)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.rawValue)
                    .font(RoomTokens.Typography.bodyStrong)
                    .foregroundStyle(on ? RoomTokens.Ink.graphite : RoomTokens.Ink.secondary)
                Group {
                    if let value { RoomMaskable(value) } else { Text("Not read") }
                }
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(on ? accent.text : RoomTokens.Ink.tertiary)
                .monospacedDigit()
            }
            .padding(.bottom, RoomTokens.Space.row)
            .overlay(alignment: .bottom) {
                if on {
                    Capsule().fill(accent.text).frame(height: 2)
                        .matchedGeometryEffect(id: "developer-tab", in: underline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(motion.animation(RoomTokens.Motion.ui, fallback: nil), value: selected)
        .accessibilityLabel("Developer, \(section.rawValue)")
        .accessibilityValue(value ?? "Not read yet")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("RoomDeveloperTab-\(section.rawValue)")
    }
}
