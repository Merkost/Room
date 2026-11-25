import SwiftUI

/// One place in the sidebar: a room-shaped glyph tile, the name, and one value. Nothing else at rest. While its engine
/// works, a ring fills round the glyph and the row grows by one sentence with counted dots.
struct RoomSidebarRow: View {
    let place: RoomDestination
    let value: RoomSidebarValue
    let selected: Bool
    let labelled: Bool
    let commandHeld: Bool
    var activity = RoomRowActivity()
    var hovering = false

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        HStack(alignment: .center, spacing: labelled ? RoomTokens.Nav.rowColumnGap : 0) {
            RoomPlaceTile(glyph: RoomSidebarPlan.glyph(place), selected: selected, activity: activity)
            if labelled {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
                        Text(RoomSidebarPlan.title(place))
                            .font(labelFont)
                            .foregroundStyle(quiet && !selected ? RoomTokens.Ink.secondary : RoomTokens.Ink.graphite)
                            .lineLimit(1)
                        Spacer(minLength: RoomTokens.Space.tight)
                        trailing
                    }
                    if activity.showsSentence {
                        RoomMaskable(activity.sentence)
                            .font(RoomTokens.Nav.sentence)
                            .foregroundStyle(activity.showsCheck ? accent.text : RoomTokens.Ink.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                        if let dots = activity.dots {
                            RoomCountedDots(total: dots.total, filled: dots.filled)
                                .padding(.top, 4).padding(.bottom, 2)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.vertical, activity.showsSentence ? 5 : 0)
            }
        }
        .padding(.leading, labelled ? RoomTokens.Nav.rowInsetLeading : 0)
        .padding(.trailing, labelled ? RoomTokens.Nav.rowInsetTrailing : 0)
        .frame(maxWidth: labelled ? .infinity : nil, minHeight: RoomTokens.Nav.rowHeight,
               alignment: labelled ? .leading : .center)
        .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: activity.showsSentence)
    }

    private var quiet: Bool { RoomSidebarPlan.isQuiet(place) }

    private var labelFont: Font {
        if selected { return quiet ? RoomTokens.Nav.label : RoomTokens.Nav.labelSelected }
        return quiet ? RoomTokens.Nav.labelQuiet : RoomTokens.Nav.label
    }

    @ViewBuilder private var trailing: some View {
        if activity.isWorking {
            // Stop takes this place on hover (drawn by the sidebar above the row's button).
            if !hovering {
                Text(verbatim: activity.of.map { "\(activity.done)/\($0)" } ?? "")
                    .font(RoomTokens.Nav.value)
                    .foregroundStyle(RoomTokens.Ink.tertiary)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
            }
        } else if commandHeld {
            // Hold ⌘: the shortcut takes the value's place.
            Text(verbatim: "⌘\(RoomSidebarPlan.shortcut(place))")
                .font(RoomTokens.Nav.value)
                .foregroundStyle(RoomTokens.Ink.tertiary)
                .accessibilityHidden(true)
        } else {
            RoomSidebarValueView(value: value, live: selected && place == .memory, emphasised: activity.unseen)
        }
    }
}

struct RoomSidebarValueView: View {
    let value: RoomSidebarValue
    var live = false
    var emphasised = false
    @Environment(\.roomAccent) private var accent

    var body: some View {
        switch value {
        case .none:
            EmptyView()
        case .size(let text):
            RoomMaskable(text)
                .font(emphasised ? RoomTokens.Nav.valueUnseen : RoomTokens.Nav.value)
                .foregroundStyle(emphasised ? accent.text : RoomTokens.Ink.tertiary)
                .lineLimit(1).fixedSize()
        case .words(let text):
            Text(text)
                .font(emphasised ? RoomTokens.Nav.valueUnseen : RoomTokens.Nav.value)
                .foregroundStyle(emphasised ? accent.text : RoomTokens.Ink.tertiary)
                .lineLimit(1).fixedSize()
        case .sparkline(let samples):
            RoomNavSparkline(samples: samples, live: live)
        }
    }
}

/// The glyph in its quiet tile. Selected: accent glyph on an accent wash. Working: a room-shaped ring fills round the
/// glyph. Finished: the glyph gives way to a check (the one bounce). Unseen: a small accent dot on the corner.
struct RoomPlaceTile: View {
    let glyph: RoomGlyph
    var selected = false
    var activity = RoomRowActivity()
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    private var ringed: Bool { activity.phase == .working || activity.phase == .finished }

    var body: some View {
        let ring = RoundedRectangle(cornerRadius: RoomTokens.Nav.ringRadius)
        ZStack {
            RoundedRectangle(cornerRadius: RoomTokens.Nav.tileRadius)
                .fill(ringed ? Color.clear : (selected ? accent.wash : RoomTokens.Surface.tile))
            if ringed {
                ring.inset(by: RoomTokens.Nav.ringInset)
                    .stroke(RoomTokens.Surface.line, lineWidth: RoomTokens.Nav.ringStroke)
                ring.inset(by: RoomTokens.Nav.ringInset)
                    .trim(from: 0, to: activity.fraction ?? 0)
                    .stroke(accent.text, style: StrokeStyle(lineWidth: RoomTokens.Nav.ringStroke, lineCap: .round))
                    .animation(motion.animation(RoomTokens.Motion.ring, fallback: nil), value: activity.fraction)
            }
            RoomGlyphView(glyph: glyph)
                .foregroundStyle(glyphColor)
                .opacity(activity.showsCheck ? 0 : 1)
                .scaleEffect(activity.showsCheck && motion.isFull ? 0.7 : 1)
            RoomCheckShape()
                .trim(from: 0, to: activity.showsCheck ? 1 : 0)
                .stroke(accent.text, style: StrokeStyle(lineWidth: RoomTokens.Nav.checkStroke, lineCap: .round, lineJoin: .round))
                .frame(width: RoomTokens.Nav.tile, height: RoomTokens.Nav.tile)
        }
        .animation(motion.animation(RoomTokens.Motion.check, fallback: RoomTokens.Motion.fade), value: activity.showsCheck)
        .frame(width: RoomTokens.Nav.tile, height: RoomTokens.Nav.tile)
        .overlay(alignment: .topTrailing) {
            Circle().fill(accent.text)
                .frame(width: RoomTokens.Nav.unseenDot, height: RoomTokens.Nav.unseenDot)
                .overlay(Circle().stroke(RoomTokens.Surface.canvas, lineWidth: 2))
                .scaleEffect(activity.unseen ? 1 : 0.001)
                .opacity(activity.unseen ? 1 : 0)
                .offset(x: 2, y: -2)
                .animation(motion.animation(RoomTokens.Motion.check, fallback: RoomTokens.Motion.fade), value: activity.unseen)
        }
        .accessibilityHidden(true)
    }

    private var glyphColor: Color {
        if activity.phase == .working { return accent.text }
        if activity.phase == .failed { return RoomTokens.Ink.graphite }
        return selected ? accent.text : RoomTokens.Ink.secondary
    }
}

/// The finished check, drawn in the tile's 28 x 28 box (mockup `M9 14.5l3.5 3.5L19.5 10.5`).
nonisolated struct RoomCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 28
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 9 * s, y: rect.minY + 14.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 12.5 * s, y: rect.minY + 18 * s))
        path.addLine(to: CGPoint(x: rect.minX + 19.5 * s, y: rect.minY + 10.5 * s))
        return path
    }
}

/// Counted dots: filled ones are done, the newest one is a little larger. They bounce once as they fill.
struct RoomCountedDots: View {
    let total: Int
    let filled: Int
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        HStack(spacing: RoomTokens.Nav.dotGap) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? accent.text : Color.clear)
                    .overlay(Circle().strokeBorder(index < filled ? Color.clear : RoomTokens.Ink.tertiary, lineWidth: 1))
                    .frame(width: RoomTokens.Nav.dot, height: RoomTokens.Nav.dot)
                    .scaleEffect(index == filled - 1 && motion.isFull ? RoomTokens.Nav.dotNowScale : 1)
            }
        }
        .animation(motion.animation(RoomTokens.Motion.check, fallback: nil), value: filled)
        .accessibilityHidden(true)
    }
}

/// Memory's row value: the last few samples as a line. It only gets new samples while Memory is open (the caller freezes
/// the input elsewhere), so the sidebar never moves at idle. The live dot shows only while Memory is open.
struct RoomNavSparkline: View {
    let samples: [Int64]
    let live: Bool
    @Environment(\.roomAccent) private var accent

    var body: some View {
        let size = RoomTokens.Nav.sparkSize
        let points = RoomSparkline.points(samples, width: size.width, height: size.height)
        Canvas { context, _ in
            guard let first = points.first else { return }
            var line = Path()
            line.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() { line.addLine(to: CGPoint(x: point.x, y: point.y)) }
            context.stroke(line, with: .color(RoomTokens.Ink.tertiary),
                           style: StrokeStyle(lineWidth: RoomTokens.Nav.sparkStroke, lineCap: .round, lineJoin: .round))
            if live, let last = points.last {
                let d = RoomTokens.Nav.sparkDot
                context.fill(Path(ellipseIn: CGRect(x: last.x - d / 2, y: last.y - d / 2, width: d, height: d)),
                             with: .color(accent.text))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
