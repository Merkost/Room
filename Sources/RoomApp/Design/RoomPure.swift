// RoomPure.swift: the pure functions of board v4 (`src/55-patterns.js` lines 6-40, `window.RoomPure`), ported to Swift.
// No UI, no state, no I/O: every function is a unit-test target (18-BUILD-PLAN-AND-TESTS.md §5.1).
// Proposed path: Sources/RoomCore/RoomPure.swift. Values are board v4's (19 §5); keep them in one place.
import CoreGraphics
import Foundation

nonisolated enum RoomPure {
    // MARK: Dot allocation (v4 decision 31: one dot is about 4 GB; each kind rounded on its own; the caption says "about")

    /// Units a plan may use, in GB. The plan uses the smallest unit that keeps the dot count at or below `targetDots`.
    static let unitLadderGB: [Double] = [1, 2, 4, 5, 10, 20, 50, 100]
    /// 994 GB / 4 GB is about 250 dots (v4). 260 leaves room for rounding on a 1 TB disk.
    static let targetDots = 260

    static func gbPerDot(capacityGB: Double) -> Double {
        for unit in unitLadderGB where capacityGB / unit <= Double(targetDots) { return unit }
        return unitLadderGB.last!
    }

    struct Allocation: Sendable, Equatable {
        var key: String
        var gb: Double
        var dots: Int
        /// dots × unit − gb: what the drawing over- or under-states (v4 `err`). |error| ≤ unit / 2 by construction.
        var errorGB: Double
    }

    /// v4 `dotAlloc`: n = round(gb / unit) per part. Parts below half a unit get 0 dots and are listed, never drawn as 0.
    static func dotAlloc(_ parts: [(key: String, gb: Double)], unit: Double) -> [Allocation] {
        parts.map { p in
            let n = Int((p.gb / unit).rounded(.toNearestOrAwayFromZero))
            return Allocation(key: p.key, gb: p.gb, dots: n, errorGB: Double(n) * unit - p.gb)
        }
    }

    static func dotSum(_ a: [Allocation]) -> Int { a.reduce(0) { $0 + $1.dots } }

    // MARK: Dot placement

    /// v4 `dotsInRect`: n dots row by row at about `pitch` apart, last row left-aligned (a waffle per room).
    static func dotsInRect(_ n: Int, in r: CGRect, pitch: CGFloat) -> [CGPoint] {
        guard n > 0, r.width > 0, r.height > 0, pitch > 0 else { return [] }
        var cols = max(1, min(n, Int((r.width / pitch).rounded())))
        var rows = Int((Double(n) / Double(cols)).rounded(.up))
        if r.height / CGFloat(rows) < pitch * 0.62 {
            rows = max(1, Int((r.height / (pitch * 0.62)).rounded(.down)))
            cols = Int((Double(n) / Double(rows)).rounded(.up))
            rows = Int((Double(n) / Double(cols)).rounded(.up))
        }
        let px = r.width / CGFloat(cols), py = r.height / CGFloat(rows)
        return (0..<n).map { i in
            CGPoint(x: r.minX + px * (CGFloat(i % cols) + 0.5), y: r.minY + py * (CGFloat(i / cols) + 0.5))
        }
    }

    /// v4 `dotsInPocket`: the free room is an L (the pocket): the rectangle minus a notch at its bottom right.
    /// Shrinks the pitch by 5 % per try (at most 40) until n cells fit; returns exactly n points when they fit.
    static func dotsInPocket(_ n: Int, in r: CGRect, notch: CGPoint?, pitch: CGFloat) -> [CGPoint] {
        var p = pitch
        var cells: [CGPoint] = []
        for _ in 0..<40 {
            cells = []
            let cols = max(1, Int((r.width / p).rounded(.down))), rows = max(1, Int((r.height / p).rounded(.down)))
            let px = r.width / CGFloat(cols), py = r.height / CGFloat(rows)
            for row in 0..<rows {
                for col in 0..<cols {
                    let c = CGPoint(x: r.minX + px * (CGFloat(col) + 0.5), y: r.minY + py * (CGFloat(row) + 0.5))
                    if let notch, c.x > notch.x - px * 0.3, c.y > notch.y - py * 0.3 { continue }
                    cells.append(c)
                }
            }
            if cells.count >= n { break }
            p *= 0.95
        }
        return Array(cells.prefix(n))
    }

    /// v4 plan geometry: pitch = sqrt(unit × points² per GB); dot radius = clamp(0.15 × pitch, 2.4, 3.6).
    static func pitch(unitGB: Double, pointsSquaredPerGB: Double) -> CGFloat { CGFloat((unitGB * pointsSquaredPerGB).squareRoot()) }
    static func restRadius(pitch: CGFloat) -> CGFloat { min(3.6, max(2.4, pitch * 0.15)) }

    /// v4 `hitDot`: index of the nearest dot within `radius`, or nil.
    static func hitDot(_ dots: [CGPoint], at p: CGPoint, radius: CGFloat) -> Int? {
        var best: Int? = nil, bestD = radius * radius
        for (i, d) in dots.enumerated() {
            let q = (d.x - p.x) * (d.x - p.x) + (d.y - p.y) * (d.y - p.y)
            if q <= bestD { bestD = q; best = i }
        }
        return best
    }

    // MARK: Wake, ring, lamp (Motion.wake, v4 decision 33)

    static let wakeRadius: CGFloat = 34          // pt, quadratic falloff
    static let wakeTauMS: Double = 150           // exponential decay constant
    static let wakeGain: CGFloat = 1.2           // scale 1× … 2.2×
    static let wakeRest: CGFloat = 0.01          // below this the dot is at rest (energy 0)

    static func wakeFalloff(distance d: CGFloat, radius: CGFloat = wakeRadius) -> CGFloat {
        guard d < radius else { return 0 }
        let t = 1 - d / radius
        return t * t
    }

    static func wakeDecay(_ e: CGFloat, dtMS: Double, tauMS: Double = wakeTauMS) -> CGFloat {
        let v = e * CGFloat(exp(-dtMS / tauMS))
        return v < wakeRest ? 0 : v
    }

    static func wakeScale(_ e: CGFloat) -> CGFloat { 1 + wakeGain * e }

    /// v4 `ringEnergy`: one ring per press, a front at 0.42 pt/ms, 16 pt wide, lending up to 0.7 energy, gone after 700 ms.
    static let ringSpeed: CGFloat = 0.42, ringWidth: CGFloat = 16, ringPeak: CGFloat = 0.7, ringLifeMS: Double = 700
    static func ringEnergy(distance d: CGFloat, tMS: Double) -> CGFloat {
        let front = ringSpeed * CGFloat(tMS), k = abs(d - front)
        guard k < ringWidth else { return 0 }
        return (1 - k / ringWidth) * ringPeak * CGFloat(max(0, 1 - tMS / ringLifeMS))
    }

    /// v4 `plLamp`: label opacity by distance from the pointer, clamp(1.25 − d / 110, 0, 1).
    static func lampOpacity(distance d: CGFloat) -> CGFloat { min(1, max(0, 1.25 - d / 110)) }

    // MARK: Momentum, detents, rubber band (Motion.coast)

    /// Apple's projection (Designing Fluid Interfaces): distance travelled after release, in points.
    static func project(velocityPtPerMS v: Double, rate: Double = 0.998) -> Double { v * rate / (1 - rate) }
    static func nearestStep(_ v: Double, step: Double, min lo: Double, max hi: Double) -> Double {
        Swift.max(lo, Swift.min(hi, (v / step).rounded() * step))
    }
    static func rubber(_ overshoot: Double, dimension: Double, constant c: Double = 0.55) -> Double {
        overshoot * dimension * c / (dimension + c * abs(overshoot))
    }
    /// Goal ruler coast duration: 260 ms + 3 ms per GB travelled, at most 620 ms.
    static func coastMS(distanceGB: Double) -> Double { Swift.min(620, 260 + abs(distanceGB) * 3) }

    // MARK: Goal bars, Hide

    /// v4 `goalBarsSVG` hover: bars within 36 pt of the pointer swell up to 1.6× wide.
    static func barSwell(dx: CGFloat) -> CGFloat { 1 + 0.6 * max(0, 1 - abs(dx) / 36) }

    /// v4 `privMask`: mask the first k maskable characters with "•". Digits only, or digits and letters for names.
    static func mask(_ s: String, first k: Int, lettersToo: Bool) -> String {
        var masked = 0
        return String(s.map { ch -> Character in
            let maskable = ch.isNumber || (lettersToo && ch.isLetter)
            if maskable, masked < k { masked += 1; return "•" }
            return ch
        })
    }
    static let hideStepMS: Double = 22, peekHoldMS: Double = 280
}
