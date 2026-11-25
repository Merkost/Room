import SwiftUI

/// One place in the sidebar: a room-shaped glyph tile, the name, and one value. Nothing else at rest.
struct RoomSidebarRow: View {
    let place: RoomDestination
    let value: RoomSidebarValue
    let selected: Bool
    let labelled: Bool
    let commandHeld: Bool

    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: labelled ? RoomTokens.Nav.rowColumnGap : 0) {
            RoomPlaceTile(glyph: RoomSidebarPlan.glyph(place), selected: selected)
            if labelled {
                Text(RoomSidebarPlan.title(place))
                    .font(labelFont)
                    .foregroundStyle(quiet && !selected ? RoomTokens.Ink.secondary : RoomTokens.Ink.graphite)
                    .lineLimit(1)
                Spacer(minLength: RoomTokens.Space.tight)
                trailing
            }
        }
        .padding(.leading, labelled ? RoomTokens.Nav.rowInsetLeading : 0)
        .padding(.trailing, labelled ? RoomTokens.Nav.rowInsetTrailing : 0)
        .frame(maxWidth: labelled ? .infinity : nil, minHeight: RoomTokens.Nav.rowHeight,
               alignment: labelled ? .leading : .center)
    }

    private var quiet: Bool { RoomSidebarPlan.isQuiet(place) }

    private var labelFont: Font {
        if selected { return quiet ? RoomTokens.Nav.label : RoomTokens.Nav.labelSelected }
        return quiet ? RoomTokens.Nav.labelQuiet : RoomTokens.Nav.label
    }

    @ViewBuilder private var trailing: some View {
        if commandHeld {
            // Hold ⌘: the shortcut takes the value's place.
            Text(verbatim: "⌘\(RoomSidebarPlan.shortcut(place))")
                .font(RoomTokens.Nav.value)
                .foregroundStyle(RoomTokens.Ink.tertiary)
                .accessibilityHidden(true)
        } else {
            RoomSidebarValueView(value: value, live: selected && place == .memory)
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

/// The glyph in its quiet tile. Selected: accent glyph on an accent wash.
struct RoomPlaceTile: View {
    let glyph: RoomGlyph
    var selected = false
    var clearsTile = false
    @Environment(\.roomAccent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: RoomTokens.Nav.tileRadius)
            .fill(clearsTile ? Color.clear : (selected ? accent.wash : RoomTokens.Surface.tile))
            .overlay {
                RoomGlyphView(glyph: glyph)
                    .foregroundStyle(selected ? accent.text : RoomTokens.Ink.secondary)
            }
            .frame(width: RoomTokens.Nav.tile, height: RoomTokens.Nav.tile)
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
