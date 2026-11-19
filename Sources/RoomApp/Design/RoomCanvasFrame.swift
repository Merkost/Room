import SwiftUI

/// Canvas can render off the main actor. The renderer captures a frame of values,
/// leaving hover, selection and wake state on the view's actor.
nonisolated struct RoomCanvasFrame {
    private enum Mark {
        case stroke(Path, Color, StrokeStyle, clip: Path?, opacity: Double)
        case fill(Path, Color, clip: Path?, opacity: Double)
        case label(Text, CGRect, centeredVertically: Bool)
        case lines(Line, Line?, CGRect, inline: Bool, opacity: Double)
    }

    struct Line {
        let value: String
        let font: Font
        let ink: Color

        func resolve(in context: GraphicsContext, width: CGFloat, truncates: Bool = true) -> (GraphicsContext.ResolvedText, CGSize)? {
            func measured(_ string: String) -> (GraphicsContext.ResolvedText, CGSize) {
                let text = context.resolve(Text(verbatim: string).font(font).foregroundStyle(ink))
                return (text, text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)))
            }

            let line = value.split(whereSeparator: \.isNewline).joined(separator: " ")
            let complete = measured(line)
            if complete.1.width <= width { return complete }
            guard truncates else { return nil }
            let characters = Array(line)
            var best: (GraphicsContext.ResolvedText, CGSize)?
            var low = 1
            var high = characters.count - 1
            while low <= high {
                let length = (low + high) / 2
                let sample = measured(String(characters.prefix(length)) + "…")
                if sample.1.width <= width {
                    best = sample
                    low = length + 1
                } else {
                    high = length - 1
                }
            }
            return best
        }
    }

    private var marks: [Mark] = []

    mutating func stroke(_ path: Path, _ ink: Color, lineWidth: CGFloat, clip: Path? = nil, opacity: Double = 1) {
        stroke(path, ink, style: StrokeStyle(lineWidth: lineWidth), clip: clip, opacity: opacity)
    }

    mutating func stroke(_ path: Path, _ ink: Color, style: StrokeStyle, clip: Path? = nil, opacity: Double = 1) {
        marks.append(.stroke(path, ink, style, clip: clip, opacity: opacity))
    }

    mutating func fill(_ path: Path, _ ink: Color, clip: Path? = nil, opacity: Double = 1) {
        marks.append(.fill(path, ink, clip: clip, opacity: opacity))
    }

    mutating func label(_ text: String, in bounds: CGRect, font: Font, ink: Color, centeredVertically: Bool = false) {
        marks.append(.label(Text(text).font(font).foregroundStyle(ink), bounds, centeredVertically: centeredVertically))
    }

    mutating func lines(_ title: Line, _ detail: Line?, in bounds: CGRect, inline: Bool, opacity: Double) {
        marks.append(.lines(title, detail, bounds, inline: inline, opacity: opacity))
    }

    var renderer: (inout GraphicsContext, CGSize) -> Void {
        { context, _ in
            for mark in marks {
                switch mark {
                case let .stroke(path, ink, style, clip, opacity):
                    drawingContext(context, clip: clip, opacity: opacity).stroke(path, with: .color(ink), style: style)
                case let .fill(path, ink, clip, opacity):
                    drawingContext(context, clip: clip, opacity: opacity).fill(path, with: .color(ink))
                case let .lines(title, detail, bounds, inline, opacity):
                    drawLines(title, detail: detail, in: bounds, inline: inline,
                              context: drawingContext(context, clip: nil, opacity: opacity))
                case let .label(text, bounds, centeredVertically):
                    let label = context.resolve(text)
                    let size = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                    guard size.width <= bounds.width, size.height <= bounds.height else { continue }
                    let point = CGPoint(x: bounds.minX, y: centeredVertically ? bounds.midY : bounds.minY)
                    context.draw(label, at: point, anchor: centeredVertically ? .leading : .topLeading)
                }
            }
        }
    }

    private func drawLines(_ title: Line, detail: Line?, in bounds: CGRect,
                           inline: Bool, context: GraphicsContext) {
        let gap: CGFloat = inline ? 5 : 2
        var secondary = detail?.resolve(in: context, width: inline ? bounds.width * 0.55 : bounds.width, truncates: false)
        let reserved = inline ? secondary.map { $0.1.width + gap } ?? 0 : 0
        guard let (name, nameSize) = title.resolve(in: context, width: bounds.width - reserved),
              nameSize.height <= bounds.height else { return }
        if !inline, let height = secondary?.1.height, nameSize.height + gap + height > bounds.height {
            secondary = nil
        }
        let blockHeight = nameSize.height + (inline ? 0 : secondary.map { $0.1.height + gap } ?? 0)
        let top = bounds.midY - blockHeight / 2
        context.draw(name, at: CGPoint(x: bounds.minX, y: top), anchor: .topLeading)
        if let (amount, _) = secondary {
            let point = inline ? CGPoint(x: bounds.minX + nameSize.width + gap, y: top)
                : CGPoint(x: bounds.minX, y: top + nameSize.height + gap)
            context.draw(amount, at: point, anchor: .topLeading)
        }
    }

    private func drawingContext(_ context: GraphicsContext, clip: Path?, opacity: Double) -> GraphicsContext {
        var drawing = context
        if let clip { drawing.clip(to: clip) }
        drawing.opacity *= opacity
        return drawing
    }
}
