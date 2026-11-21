// Compiled reference (DISK-MAP-SPEC.md §9.3, WP-07 remainder a). Proposed path: Sources/RoomApp/Views/Overview/RoomWakeField.swift.
// The per-dot state the dot plan's TimelineView(.animation(paused: field.isAtRest)) reads. All constants and curves
// come from RoomPure (design/spec/snippets/RoomPure.swift, 19 §5); this type only holds energies and rings.
import CoreGraphics
import Foundation

nonisolated struct RoomWakeField: Sendable {
    struct Ring: Sendable, Equatable { var center: CGPoint; var ageMS: Double }

    static let maxFrameMS: Double = 64            // OV-9: a stalled frame never jumps
    static let drawnRingLifeMS: Double = 650      // OV-7 drawn ring: r 4 → 150, opacity 0.55 → 0
    private(set) var energy: [CGFloat]
    private(set) var rings: [Ring] = []
    let enabled: Bool                             // false under Reduce Motion or Gentle motion off (OV-10)

    init(dotCount: Int, enabled: Bool) {
        energy = Array(repeating: 0, count: dotCount)
        self.enabled = enabled
    }

    /// Energy enters only while the pointer moves (OV-6).
    mutating func pointerMoved(to p: CGPoint, dots: [CGPoint]) {
        guard enabled else { return }
        for i in dots.indices where i < energy.count {
            let d = hypot(dots[i].x - p.x, dots[i].y - p.y)
            energy[i] = max(energy[i], RoomPure.wakeFalloff(distance: d))
        }
    }

    /// One ring per press (OV-7).
    mutating func press(at p: CGPoint) {
        guard enabled else { return }
        rings.append(Ring(center: p, ageMS: 0))
    }

    mutating func step(dtMS raw: Double, dots: [CGPoint]) {
        let dt = min(Self.maxFrameMS, max(0, raw))
        for i in energy.indices { energy[i] = RoomPure.wakeDecay(energy[i], dtMS: dt) }
        for r in rings.indices { rings[r].ageMS += dt }
        rings.removeAll { $0.ageMS >= RoomPure.ringLifeMS }
        for ring in rings {
            for i in dots.indices where i < energy.count {
                let d = hypot(dots[i].x - ring.center.x, dots[i].y - ring.center.y)
                energy[i] = max(energy[i], RoomPure.ringEnergy(distance: d, tMS: ring.ageMS))
            }
        }
    }

    /// The TimelineView pauses on this: zero frames when nothing moves (OV-9, OV-A5).
    var isAtRest: Bool { rings.isEmpty && energy.allSatisfy { $0 == 0 } }

    func radius(_ i: Int, rest r: CGFloat) -> CGFloat { r * RoomPure.wakeScale(energy[i]) }

    /// Drawn ring for one press: (radius, opacity), nil once its 650 ms are over.
    static func drawnRing(ageMS t: Double) -> (radius: CGFloat, opacity: Double)? {
        guard t < drawnRingLifeMS else { return nil }
        let p = t / drawnRingLifeMS, eased = 1 - pow(1 - p, 3)          // ease-out
        return (4 + CGFloat(eased) * 146, 0.55 * (1 - eased))
    }
}
