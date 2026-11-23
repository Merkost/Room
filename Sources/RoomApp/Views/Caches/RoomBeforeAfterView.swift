import SwiftUI

struct RoomBeforeAfterView: View {
    let sources: [RoomSource]
    let selectedBytes: (String) -> Int64
    let format: (Int64) -> String

    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        let maximum = max(1, sources.map(\.bytes).max() ?? 1)
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text("Before and after").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
            ForEach(sources.sorted { $0.bytes > $1.bytes }) { source in
                let toTrash = min(source.bytes, selectedBytes(source.id))
                let after = max(0, source.bytes - toTrash)
                let beforeFraction = CGFloat(source.bytes) / CGFloat(maximum)
                let afterFraction = CGFloat(after) / CGFloat(maximum)
                let description = "\(source.name): \(format(source.bytes)) before, \(format(after)) after, \(format(toTrash)) to Trash"
                HStack(spacing: 10) {
                    Text(source.name).lineLimit(1).frame(width: 90, alignment: .leading)
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Rectangle().fill(RoomTokens.Surface.track).frame(width: width * afterFraction)
                                Rectangle().fill(accent.fill).frame(width: width * (beforeFraction - afterFraction))
                            }
                            .clipShape(Capsule())
                            Capsule().fill(RoomTokens.Surface.used).frame(width: width * afterFraction)
                        }
                        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: afterFraction)
                    }
                    .frame(height: 12)
                    .accessibilityHidden(true)
                    Text(toTrash > 0 ? "\(format(source.bytes)) → \(format(after))" : "\(format(source.bytes)) · kept")
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 110, alignment: .trailing)
                        .foregroundStyle(toTrash > 0 ? RoomTokens.Ink.graphite : RoomTokens.Ink.secondary)
                }
                .font(RoomTokens.Typography.caption)
                .padding(.vertical, 4)
                .focusable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hidden ? "\(source.name), sizes hidden" : description)
                .help(hidden ? "Sizes hidden" : description)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoomTokens.Space.inner) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
            .padding(.top, RoomTokens.Space.tight)
            Text("Free space changes when you empty Trash.")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
    }

    @ViewBuilder private var legend: some View {
        swatch("Before", color: RoomTokens.Surface.track)
        swatch("Goes to Trash", color: accent.fill)
        swatch("After", color: RoomTokens.Surface.used)
    }

    private func swatch(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3).accessibilityHidden(true)
            Text(title).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
        }
        .fixedSize()
    }
}
