import SwiftUI

struct RoomPlaceValueView: View {
    let value: RoomPlaceValue
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
