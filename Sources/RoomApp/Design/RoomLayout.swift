import CoreGraphics
import Foundation
import RoomCore

// MARK: - Dot plan (Overview, onboarding, website hero)

/// Kinds drawn on the plan. `free` is the pocket; `notMapped` is used space no scan has measured.
nonisolated enum RoomPlanRoom: Hashable, Sendable {
    case free
    case kind(String)          // RoomTokens.Kind raw value
    case notMapped
}

nonisolated struct RoomDotPlan: Sendable {
    struct Dot: Sendable, Equatable {
        var center: CGPoint
        var room: RoomPlanRoom
    }
    var gbPerDot: Double
    var pitch: CGFloat
    var radius: CGFloat
    var dots: [Dot]
    var rooms: [RoomPlacedRect<RoomPlanRoom>]
    /// Rooms below half a dot: listed in the accessible table and the focus list, never drawn as zero.
    var underOneDot: [RoomPlanRoom]
    /// Σ dots × unit − capacity: why the caption says "about" (board fixture: 1,000 GB drawn for 994 GB).
    var drawnErrorGB: Double

    /// Board v4 model (decision 31, Phase 2b "dots from RoomPlanLayout, the same layout as the solid plan"):
    /// rooms are squarified by bytes on the plan (free pinned first, so the pocket is top-left), then each room is
    /// filled with round(gb / unit) dots at one constant pitch, sqrt(unit × pt² per GB). Each kind rounds on its own.
    static func make(capacityGB: Double, freeGB: Double, kinds: [(String, Double)], size: CGSize, inset: CGFloat = 2) -> RoomDotPlan {
        let unit = RoomPure.gbPerDot(capacityGB: capacityGB)
        let measured = kinds.reduce(0) { $0 + max(0, $1.1) }
        let used = max(0, capacityGB - freeGB)
        var parts: [(RoomPlanRoom, Double)] = [(.free, freeGB)] + kinds.map { (.kind($0.0), max(0, $0.1)) }
        if used - measured > 0.05 { parts.append((.notMapped, used - measured)) }   // honest remainder, hatched, no dots
        let bounds = CGRect(origin: .zero, size: size)
        let weighted = parts.map { RoomWeighted(id: $0.0, bytes: Int64(($0.1 * 1_000).rounded())) }   // MB as integer weight
        let rects = RoomSquarify.layout(weighted, in: bounds, pinnedFirst: .free)
        let totalGB = parts.reduce(0) { $0 + $1.1 }
        let ar = Double(size.width * size.height) / max(totalGB, 0.001)          // pt² per GB
        let pitch = RoomPure.pitch(unitGB: unit, pointsSquaredPerGB: ar)
        let alloc = RoomPure.dotAlloc(parts.filter { $0.0 != .notMapped }.map { (key: "\($0.0)", gb: $0.1) }, unit: unit)
        var dots: [Dot] = []
        var zero: [RoomPlanRoom] = []
        for placed in rects where placed.id != .notMapped {
            let n = alloc.first { $0.key == "\(placed.id)" }?.dots ?? 0
            if n == 0 { zero.append(placed.id); continue }
            let r = placed.rect.insetBy(dx: inset, dy: inset)
            let pts = placed.id == .free ? RoomPure.dotsInPocket(n, in: r, notch: nil, pitch: pitch)
                                         : RoomPure.dotsInRect(n, in: r, pitch: pitch)
            dots += pts.map { Dot(center: $0, room: placed.id) }
        }
        let drawn = Double(RoomPure.dotSum(alloc)) * unit
        return RoomDotPlan(gbPerDot: unit, pitch: pitch, radius: RoomPure.restRadius(pitch: pitch), dots: dots,
                           rooms: rects, underOneDot: zero, drawnErrorGB: drawn - (freeGB + measured))
    }
}
