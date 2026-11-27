import RoomCore
import SwiftUI

/// A column's heading: what it is on the left, what you can do with it on the right.
struct RoomMemoryColumnHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: RoomTokens.Space.breath1) {
            HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
                Text(title).font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                Spacer(minLength: 0)
                trailing.font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
            Divider()
        }
    }
}

/// Icon, name, size and a bar against the largest in the column; `selected` adds the tick.
struct RoomMemoryProcessRow: View {
    let pid: Int32
    let name: String
    let bytes: Int64?
    let maximum: Int64
    var selected: Bool? = nil

    var body: some View {
        HStack(spacing: RoomTokens.Space.row) {
            RoomProcessIcon(pid: pid, name: name, size: RoomTokens.Memory2.rowIcon)
            Text(name).font(RoomTokens.Typography.body).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: RoomTokens.Space.breath1)
            if let bytes {
                RoomMaskable(RoomFormat.memory(bytes)).font(RoomTokens.Typography.body)
                    .monospacedDigit().foregroundStyle(RoomTokens.Ink.secondary).fixedSize()
                Capsule().fill(RoomTokens.Surface.used)
                    .frame(width: 44 * Double(max(0, min(bytes, maximum))) / Double(max(1, maximum)), height: 4)
                    .frame(width: 44, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                Text("Not measured").font(RoomTokens.Typography.caption).foregroundStyle(.tertiary).fixedSize()
            }
            if let selected {
                RoomChangingSymbol(name: selected ? "checkmark.circle.fill" : "circle",
                                   color: selected ? .accentColor : .secondary.opacity(0.55))
                    .font(.system(size: 16)) // design-gate: allow symbol size
            }
        }
        .frame(height: RoomTokens.Memory2.rowHeight)
        .contentShape(Rectangle())
    }
}
