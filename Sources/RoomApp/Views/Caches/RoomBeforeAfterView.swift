import SwiftUI

struct RoomBeforeAfterView: View {
    let sources: [RoomSource]
    let selection: Set<String>
    let format: (Int64) -> String

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text("Before and after").font(RoomTokens.Typography.section)
            ForEach(sources) { source in
                let toTrash = selection.contains(source.id) ? source.eligibleBytes : 0
                let after = max(0, source.bytes - toTrash)
                let fraction = source.bytes > 0 ? CGFloat(after) / CGFloat(source.bytes) : 0
                let description = "\(source.name): \(format(source.bytes)) before, \(format(after)) after, \(format(toTrash)) to Trash"
                HStack(spacing: 10) {
                    Text(source.name).lineLimit(1).frame(width: 96, alignment: .leading)
                    GeometryReader { proxy in
                        VStack(spacing: 2) {
                            ZStack(alignment: .trailing) {
                                Capsule().fill(RoomTokens.Surface.track)
                                if toTrash > 0 {
                                    Capsule().fill(accent.fill).frame(width: proxy.size.width * (1 - fraction))
                                }
                            }
                            Capsule().fill(RoomTokens.Surface.used.opacity(after == 0 ? 0.25 : 1))
                                .frame(width: proxy.size.width * max(fraction, 0.005))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .animation(motion.isFull ? RoomTokens.Motion.quick : nil, value: fraction)
                    }
                    .frame(height: 14)
                    .accessibilityHidden(true)
                    Text(format(after)).monospacedDigit().frame(minWidth: 52, alignment: .trailing)
                }
                .font(RoomTokens.Typography.caption)
                .padding(.vertical, 4)
                .focusable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(description)
                .help(description)
            }
            HStack(spacing: RoomTokens.Space.group) {
                Label("Now", systemImage: "capsule.fill").foregroundStyle(RoomTokens.Ink.secondary)
                Label("Selected to move", systemImage: "capsule.fill").foregroundStyle(accent.text)
            }
            .font(RoomTokens.Typography.caption)
        }
    }
}
