import Foundation

/// A transient plot in normalized coordinates. Snapshots contain geometry, never inferred measurements.
nonisolated struct RoomOverviewHistoryPlot: Equatable, Sendable {
    static let resolution = 96
    static let gigabyte = 1_000_000_000.0

    struct Column: Equatable, Sendable {
        var left: Double
        var right: Double
        var topLeft: Double
        var topRight: Double
        var base: Double
        var area = 0.0
        var growth = 0.0
        var freed = 0.0
        var line = 0.0

        fileprivate func blended(to end: Self, at fraction: Double) -> Self {
            Self(left: mix(left, end.left, fraction), right: mix(right, end.right, fraction),
                 topLeft: mix(topLeft, end.topLeft, fraction), topRight: mix(topRight, end.topRight, fraction),
                 base: mix(base, end.base, fraction), area: mix(area, end.area, fraction),
                 growth: mix(growth, end.growth, fraction), freed: mix(freed, end.freed, fraction),
                 line: mix(line, end.line, fraction))
        }

        fileprivate func faded(by weight: Double) -> Self {
            var result = self
            result.area *= weight
            result.growth *= weight
            result.freed *= weight
            result.line *= weight
            return result
        }
    }

    struct Dot: Identifiable, Equatable, Sendable {
        enum Kind: Hashable, Sendable { case sample, latest, zero, growth, freed }
        struct ID: Hashable, Sendable {
            let slot: Int
            let step: Int
            let kind: Kind
        }

        let id: ID
        var x: Double
        var y: Double
        var diameter: Double
        var opacity = 1.0
        var lift = 0.0

        var entersInSequence: Bool { id.kind == .growth || id.kind == .freed }

        fileprivate func faded(by weight: Double) -> Self {
            var result = self
            result.opacity *= weight
            return result
        }

        fileprivate func blended(to end: Self, at fraction: Double) -> Self {
            Self(id: id, x: mix(x, end.x, fraction), y: mix(y, end.y, fraction),
                 diameter: mix(diameter, end.diameter, fraction),
                 opacity: mix(opacity, end.opacity, fraction), lift: mix(lift, end.lift, fraction))
        }
    }

    let columns: [Column?]
    let gaps: [Double]
    let dots: [Dot]

    init(history: RoomOverviewHistory, range: RoomOverviewHistoryRange, metric: RoomOverviewHistoryMetric,
         domain: ClosedRange<Double>, now: Date, selected: Int?) {
        let points = history.points
        guard !points.isEmpty else {
            columns = Array(repeating: nil, count: Self.resolution)
            gaps = Array(repeating: 0, count: Self.resolution)
            dots = []
            return
        }
        let values = points.map { $0.value(for: metric).map { Double($0) / Self.gigabyte } }
        let count = Double(points.count)
        let span = max(1, domain.upperBound - domain.lowerBound)
        let latest = history.latest(for: metric)?.id
        func position(_ value: Double) -> Double {
            1 - (value - domain.lowerBound) / span
        }
        func usesDots(_ value: Double) -> Bool {
            range == .week && (1...32).contains(Int(abs(value).rounded()))
        }
        func value(at x: Double, in slot: Int) -> Double? {
            guard let value = values[slot] else { return nil }
            let offset = x * count - Double(slot) - 0.5
            let neighbour = slot + (offset < 0 ? -1 : 1)
            guard values.indices.contains(neighbour), points[neighbour].run == points[slot].run,
                  let adjacent = values[neighbour] else { return value }
            return mix(value, adjacent, abs(offset))
        }

        var columns: [Column?] = []
        var gaps: [Double] = []
        for index in 0..<Self.resolution {
            let left = Double(index) / Double(Self.resolution)
            let right = Double(index + 1) / Double(Self.resolution)
            let middle = (left + right) / 2
            let slot = Int(middle * count)
            let center = (Double(slot) + 0.5) / count
            gaps.append(values[slot] == nil && points[slot].bucket <= now ? 1 : 0)
            guard let raw = values[slot] else { columns.append(nil); continue }
            switch metric {
            case .freeSpace:
                let neighbour = slot + (middle < center ? -1 : 1)
                let connected = points.indices.contains(neighbour) && points[neighbour].run == points[slot].run
                    && values[neighbour] != nil
                columns.append(Column(left: left, right: right,
                    topLeft: position(value(at: left, in: slot) ?? raw),
                    topRight: position(value(at: right, in: slot) ?? raw),
                    base: 1, area: 1, line: connected ? 1 : 0))
            case .change:
                let halfWidth = (selected == slot ? 0.42 : 0.335) / count
                let start = min(center + halfWidth, max(center - halfWidth, left))
                let end = min(center + halfWidth, max(center - halfWidth, right))
                let hasBar = start < end && raw != 0 && !usesDots(raw)
                let base = position(0)
                let top = hasBar ? position(raw) : base
                columns.append(Column(left: start, right: end, topLeft: top, topRight: top, base: base,
                    growth: hasBar && raw > 0 ? 1 : 0, freed: hasBar && raw < 0 ? 1 : 0))
            }
        }
        self.columns = columns
        self.gaps = gaps
        dots = points.flatMap { point -> [Dot] in
            guard let raw = values[point.id] else { return [] }
            let x = (Double(point.id) + 0.5) / count
            if metric == .freeSpace {
                let kind: Dot.Kind = point.id == latest ? .latest : .sample
                return [Dot(id: .init(slot: point.id, step: 0, kind: kind), x: x, y: position(raw),
                            diameter: kind == .latest || selected == point.id ? 7.5 : 4)]
            }
            if raw == 0 {
                return [Dot(id: .init(slot: point.id, step: 0, kind: .zero), x: x, y: position(0),
                            diameter: selected == point.id ? 5.5 : 4)]
            }
            guard usesDots(raw) else { return [] }
            let kind: Dot.Kind = raw > 0 ? .growth : .freed
            return (0..<Int(abs(raw).rounded())).map { step in
                Dot(id: .init(slot: point.id, step: step, kind: kind), x: x,
                    y: position(Double(step + 1) * (raw > 0 ? 1 : -1)),
                    diameter: selected == point.id ? 7.5 : 6)
            }
        }
    }

    private init(columns: [Column?], gaps: [Double], dots: [Dot]) {
        self.columns = columns
        self.gaps = gaps
        self.dots = dots
    }

    func blended(to end: Self, at fraction: Double, incomingDot: (Dot) -> Double) -> Self {
        let columns = zip(columns, end.columns).map { old, new -> Column? in
            switch (old, new) {
            case (let old?, let new?): old.blended(to: new, at: fraction)
            case (let old?, nil): old.faded(by: 1 - fraction)
            case (nil, let new?): new.faded(by: fraction)
            case (nil, nil): nil
            }
        }
        let gaps = zip(gaps, end.gaps).map { mix($0, $1, fraction) }
        let oldDots = Dictionary(uniqueKeysWithValues: dots.map { ($0.id, $0) })
        let newIDs = Set(end.dots.map(\.id))
        let exiting = dots.filter { !newIDs.contains($0.id) }.map { $0.faded(by: 1 - fraction) }
        let arriving = end.dots.map { target in
            if let current = oldDots[target.id] {
                return current.blended(to: target, at: fraction)
            }
            let amount = target.entersInSequence ? incomingDot(target) : fraction
            var dot = target.faded(by: amount)
            dot.lift = target.entersInSequence ? 1 - amount : 0
            return dot
        }
        return Self(columns: columns, gaps: gaps, dots: (exiting + arriving).filter { $0.opacity > 0 })
    }
}

nonisolated private func mix(_ from: Double, _ to: Double, _ fraction: Double) -> Double {
    from + (to - from) * fraction
}
