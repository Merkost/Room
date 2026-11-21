import SwiftUI

nonisolated struct RoomOverviewHistoryTransition: Equatable, Sendable {
    struct Layer: Equatable, Sendable {
        let plot: RoomOverviewHistoryPlot
        let opacity: Double
    }

    let source: [Layer]
    let target: RoomOverviewHistoryPlot
    let morphs: Bool
    let start: ContinuousClock.Instant
    let duration: TimeInterval

    init(source: [Layer], target: RoomOverviewHistoryPlot, morphs: Bool, start: ContinuousClock.Instant) {
        self.source = source
        self.target = target
        self.morphs = morphs
        self.start = start
        if morphs {
            let oldDots = Set(source.first?.plot.dots.map(\.id) ?? [])
            let lastArrival = target.dots.filter { $0.entersInSequence && !oldDots.contains($0.id) }
                .map { Double($0.id.step) * RoomTokens.Motion.stagger + RoomTokens.Motion.historyDotDuration }
                .max() ?? 0
            duration = max(RoomTokens.Motion.morphDuration, lastArrival)
        } else {
            duration = RoomTokens.Motion.fadeDuration
        }
    }

    func layers(at instant: ContinuousClock.Instant) -> [Layer] {
        let elapsed = (instant - start).components
        return layers(elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    func layers(elapsed: TimeInterval) -> [Layer] {
        if elapsed <= 0 { return source }
        if elapsed >= duration { return [Layer(plot: target, opacity: 1)] }

        if morphs, let first = source.first {
            let fraction = RoomTokens.Motion.morphCurve.value(at: min(1, elapsed / RoomTokens.Motion.morphDuration))
            let next = first.plot.blended(to: target, at: fraction) { dot in
                let begin = Double(dot.id.step) * RoomTokens.Motion.stagger
                let percent = (elapsed - begin) / RoomTokens.Motion.historyDotDuration
                return RoomTokens.Motion.fadeCurve.value(at: min(1, max(0, percent)))
            }
            return [Layer(plot: next, opacity: 1)]
        }

        let fraction = RoomTokens.Motion.fadeCurve.value(at: elapsed / RoomTokens.Motion.fadeDuration)
        var layers = source.map { Layer(plot: $0.plot, opacity: $0.opacity * (1 - fraction)) }
        if let previous = layers.firstIndex(where: { $0.plot == target }) {
            layers[previous] = Layer(plot: target, opacity: layers[previous].opacity + fraction)
        } else {
            layers.append(Layer(plot: target, opacity: fraction))
        }
        return layers.filter { $0.opacity > 0.001 }
    }
}

struct RoomOverviewHistoryPlotView: View, Equatable {
    let plot: RoomOverviewHistoryPlot
    let transition: RoomOverviewHistoryTransition?
    @Environment(\.roomAccent) private var accent

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.plot == rhs.plot && lhs.transition == rhs.transition
    }

    var body: some View {
        Group {
            if let transition {
                TimelineView(.animation) { _ in
                    drawing(transition.layers(at: .now))
                }
            } else {
                drawing([.init(plot: plot, opacity: 1)])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawing(_ layers: [RoomOverviewHistoryTransition.Layer]) -> some View {
        Canvas { context, size in
            if layers.count == 1, let layer = layers.first, layer.opacity == 1 {
                draw(layer.plot, in: context, size: size)
                return
            }
            for layer in layers {
                var context = context
                context.opacity = layer.opacity
                context.drawLayer { context in
                    draw(layer.plot, in: context, size: size)
                }
            }
        }
    }

    private func draw(_ plot: RoomOverviewHistoryPlot, in context: GraphicsContext, size: CGSize) {
        drawHatches(plot.gaps, in: context, size: size)
        drawColumns(plot.columns, weight: \.area, color: accent.wash, in: context, size: size)
        drawColumns(plot.columns, weight: \.growth, color: accent.fill, in: context, size: size)
        drawColumns(plot.columns, weight: \.freed, color: RoomTokens.Surface.used, in: context, size: size)
        drawColumns(plot.columns, weight: \.line, color: accent.text, in: context, size: size, stroke: true)

        for dot in plot.dots {
            let x = dot.x * size.width
            let y = dot.y * size.height + dot.lift * RoomTokens.Motion.historyDotRise
            let radius = dot.diameter / 2
            let circle = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: dot.diameter, height: dot.diameter))
            var context = context
            context.opacity *= dot.opacity
            switch dot.id.kind {
            case .freed: context.stroke(circle, with: .color(accent.text), lineWidth: 1.2)
            case .growth: context.fill(circle, with: .color(accent.fill))
            case .zero: context.fill(circle, with: .color(RoomTokens.Ink.secondary))
            case .sample, .latest: context.fill(circle, with: .color(accent.text))
            }
        }
    }

    private func drawColumns(_ columns: [RoomOverviewHistoryPlot.Column?],
                             weight: KeyPath<RoomOverviewHistoryPlot.Column, Double>, color: Color,
                             in context: GraphicsContext, size: CGSize, stroke: Bool = false) {
        var paths: [Double: Path] = [:]
        for case let column? in columns where column[keyPath: weight] > 0 && column.left < column.right {
            let alpha = column[keyPath: weight]
            let left = column.left * size.width
            let right = column.right * size.width
            let base = column.base * size.height
            let topLeft = CGPoint(x: left, y: column.topLeft * size.height)
            let topRight = CGPoint(x: right, y: column.topRight * size.height)
            paths[alpha, default: Path()].move(to: topLeft)
            paths[alpha, default: Path()].addLine(to: topRight)
            if !stroke {
                paths[alpha, default: Path()].addLine(to: CGPoint(x: right, y: base))
                paths[alpha, default: Path()].addLine(to: CGPoint(x: left, y: base))
                paths[alpha, default: Path()].closeSubpath()
            }
        }
        for (opacity, path) in paths.sorted(by: { $0.key < $1.key }) {
            var context = context
            context.opacity *= opacity
            if stroke {
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2))
            } else {
                context.fill(path, with: .color(color))
            }
        }
    }

    private func drawHatches(_ gaps: [Double], in context: GraphicsContext, size: CGSize) {
        let width = size.width / Double(gaps.count)
        var masks: [Double: Path] = [:]
        for (index, opacity) in gaps.enumerated() where opacity > 0 {
            masks[opacity, default: Path()].addRect(CGRect(x: Double(index) * width, y: 0, width: width, height: size.height))
        }
        guard !masks.isEmpty else { return }
        var hatch = Path()
        for x in stride(from: -size.height, to: size.width, by: RoomTokens.Space.tight) {
            hatch.move(to: CGPoint(x: x, y: 0))
            hatch.addLine(to: CGPoint(x: x + size.height, y: size.height))
        }
        for (opacity, mask) in masks.sorted(by: { $0.key < $1.key }) {
            var context = context
            context.opacity *= opacity
            context.clip(to: mask)
            context.stroke(hatch, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
        }
    }
}
