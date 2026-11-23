import SwiftUI

/// A single place to start a storage task, with the next action beside an illustration of its result.
struct RoomStartPanel<Actions: View>: View {
    let title: String
    let message: String
    let artwork: RoomEmptyArtwork
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.breath1) {
                introduction
                    .frame(minWidth: 244, idealWidth: 326, maxWidth: 390, alignment: .leading)
                Spacer(minLength: 0)
                illustration
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
                introduction
                illustration
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.popover))
        .overlay {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.popover)
                .strokeBorder(RoomTokens.Surface.line)
                .allowsHitTesting(false)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text(title)
                .font(RoomTokens.Typography.emptyHeading)
                .tracking(RoomTokens.Typography.tracking(for: 30))
                .foregroundStyle(RoomTokens.Ink.graphite)
                .accessibilityHeading(.h1)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(RoomTokens.Typography.lead)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions().padding(.top, RoomTokens.Space.tight)
        }
    }

    private var illustration: some View {
        RoomEmptyIllustration(artwork: artwork)
            .frame(width: RoomEmptyIllustration.size.width, height: RoomEmptyIllustration.size.height)
            .background(RoomTokens.Surface.canvas, in: .rect(cornerRadius: RoomTokens.Radius.group))
            .overlay {
                RoundedRectangle(cornerRadius: RoomTokens.Radius.group)
                    .strokeBorder(RoomTokens.Surface.line)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A result or explanation inside a working screen, with a quiet recovery action when available.
struct RoomEmptyFeedback<Actions: View>: View {
    let title: String
    let message: String
    let symbol: String
    var prominent = false
    @ViewBuilder let actions: () -> Actions
    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            Image(systemName: symbol)
                .font(RoomTokens.Typography.lead)
                .foregroundStyle(accent.text)
                .frame(width: prominent ? RoomTokens.Space.breath2 : 34,
                       height: prominent ? RoomTokens.Space.breath2 : 34)
                .background(accent.wash, in: .rect(cornerRadius: RoomTokens.Radius.row))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(title)
                    .font(prominent ? RoomTokens.Typography.title : RoomTokens.Typography.section)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    .accessibilityHeading(.h2)
                Text(message)
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, prominent ? RoomTokens.Space.tight : 0)
            }
        }
        .padding(prominent ? RoomTokens.Space.group : RoomTokens.Space.inner)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(prominent ? RoomTokens.Surface.group : RoomTokens.Surface.canvas,
                    in: .rect(cornerRadius: RoomTokens.Radius.card))
        .roomPanelArrival()
    }
}

enum RoomEmptyArtwork {
    case map, caches
}

/// Schematic artwork uses the same shapes and colours as the measured screens. It carries no sample totals.
private struct RoomEmptyIllustration: View {
    static let size = CGSize(width: 260, height: 154)
    let artwork: RoomEmptyArtwork
    @Environment(\.roomAccent) private var accent

    var body: some View {
        Canvas { context, size in
            var drawing = context
            drawing.scaleBy(x: size.width / Self.size.width, y: size.height / Self.size.height)
            drawing.fill(grid, with: .color(RoomTokens.Surface.line2))
            switch artwork {
            case .map: drawMap(in: drawing)
            case .caches: drawCaches(in: drawing)
            }
        }
    }

    private var grid: Path {
        Path { grid in
            for x in stride(from: 14, through: 246, by: 12) {
                for y in stride(from: 11, through: 148, by: 12) {
                    grid.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private func drawMap(in context: GraphicsContext) {
        let outline = Path(roundedRect: CGRect(x: 21, y: 22, width: 218, height: 110), cornerRadius: 11)
        context.fill(outline, with: .color(RoomTokens.Surface.group))
        context.stroke(outline, with: .color(RoomTokens.Surface.line), lineWidth: 1)

        let active = Path(roundedRect: CGRect(x: 25, y: 26, width: 91, height: 102), cornerRadius: 7)
        context.fill(active, with: .color(accent.wash))
        context.stroke(active, with: .color(accent.text), lineWidth: 1.3)
        tile(CGRect(x: 121, y: 26, width: 114, height: 40), fill: RoomTokens.Kind.documents.fill, in: context)
        tile(CGRect(x: 121, y: 71, width: 61, height: 57), fill: RoomTokens.Kind.media.fill, in: context)
        tile(CGRect(x: 187, y: 71, width: 48, height: 31), fill: RoomTokens.Kind.developer.fill, in: context)
        tile(CGRect(x: 187, y: 107, width: 48, height: 21), fill: RoomTokens.Surface.track, in: context)
        drawSymbol("folder", size: 25, at: CGPoint(x: 70, y: 76), color: accent.text, in: context)
    }

    private func drawCaches(in context: GraphicsContext) {
        let tray = Path(roundedRect: CGRect(x: 29, y: 17, width: 202, height: 120), cornerRadius: 11)
        context.fill(tray, with: .color(RoomTokens.Surface.group))
        context.stroke(tray, with: .color(RoomTokens.Surface.line), lineWidth: 1)

        for (index, symbol) in ["checkmark", "square.dashed", "lock"].enumerated() {
            let y = CGFloat(24 + index * 37)
            let ink = index == 0 ? accent.text : RoomTokens.Ink.secondary
            tile(CGRect(x: 36, y: y, width: 188, height: 32),
                 fill: index == 0 ? accent.wash : RoomTokens.Surface.canvas, in: context)
            tile(CGRect(x: 42, y: y + 6, width: 20, height: 20),
                 fill: index == 0 ? accent.wash : RoomTokens.Surface.track, in: context)
            drawSymbol(symbol, size: 11, at: CGPoint(x: 52, y: y + 16), color: ink, in: context)
            tile(CGRect(x: 73, y: y + 9, width: [64, 52, 71][index], height: 4),
                 fill: index == 0 ? accent.text : RoomTokens.Surface.used.opacity(0.55), in: context)
            tile(CGRect(x: 73, y: y + 19, width: 34, height: 3), fill: RoomTokens.Surface.line2, in: context)
            let marker = Path(ellipseIn: CGRect(x: 205, y: y + 14, width: 4, height: 4))
            context.fill(marker, with: .color(ink))
        }
    }

    private func tile(_ rect: CGRect, fill: Color, in context: GraphicsContext) {
        let radius = min(7, rect.height / 2)
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(fill))
    }

    private func drawSymbol(_ symbol: String, size: CGFloat, at center: CGPoint, color: Color, in context: GraphicsContext) {
        let image = context.resolve(Text(Image(systemName: symbol))
            .font(.system(size: size, weight: .semibold)).foregroundStyle(color))
        context.draw(image, at: center)
    }
}
