import Foundation

nonisolated enum RoomGoalRuler {
    // Board v4 (B4 d38, `55-patterns.js` RUL): 2.4 pt per GB, detents every 10 GB, labels every 50, range 20 … 200 GB,
    // rubber band past the ends (dimension 40), arrows ±10, Page ±50, release velocity clamped to ±3 pt/ms.
    static let pointsPerGB: Double = 2.4
    static let stepGB: Double = 10
    static let labelEveryGB: Double = 50
    static let minimumGB: Double = 20
    static let maximumGB: Double = 200
    static let rubberDimension: Double = 40
    static let maxReleaseVelocity: Double = 3      // pt per ms

    /// Upper end for this Mac: never more than capacity − 10 GB.
    static func upperGB(capacityGB: Double) -> Double { min(maximumGB, max(minimumGB, capacityGB - stepGB)) }

    /// Value shown while dragging: 1:1 inside the range, rubber-banded outside it.
    static func dragValue(startGB: Double, dragPoints: Double, capacityGB: Double) -> Double {
        let v = startGB - dragPoints / pointsPerGB, hi = upperGB(capacityGB: capacityGB)
        if v < minimumGB { return minimumGB - RoomPure.rubber(minimumGB - v, dimension: rubberDimension) }
        if v > hi { return hi + RoomPure.rubber(v - hi, dimension: rubberDimension) }
        return v
    }

    /// Where a release comes to rest: Apple's projection, then the nearest 10 GB detent inside the range.
    static func restingGB(currentGB: Double, releaseVelocityPtPerMS v: Double, capacityGB: Double) -> Double {
        let clamped = max(-maxReleaseVelocity, min(maxReleaseVelocity, v))
        let target = currentGB - RoomPure.project(velocityPtPerMS: clamped) / pointsPerGB
        return RoomPure.nearestStep(target, step: stepGB, min: minimumGB, max: upperGB(capacityGB: capacityGB))
    }

    /// Detent index crossed during a drag; a change plays NSHapticFeedbackManager .alignment once.
    static func detent(_ gb: Double) -> Int { Int((gb / stepGB).rounded()) }
}
nonisolated enum RoomGoalRulerBridge {
    static let bytesPerGB: Int64 = 1_000_000_000
    // Mirrors RoomMenuBarSettings.minimumGoalBytes / maximumGoalBytes / goalStepBytes in the app.
    static let minimumGoalBytes = RoomMenuBarSettings.minimumGoalBytes
    static let maximumGoalBytes = RoomMenuBarSettings.maximumGoalBytes
    static let goalStepBytes = RoomMenuBarSettings.goalStepBytes

    /// RoomGoalRuler.upperGB is capacity − 10 GB, which is off the 10 GB grid on most disks (128 GB → 118). The
    /// highest value the ruler may rest on or write is the detent at or below it (128 GB → 110).
    static func upperDetentGB(capacityGB: Double) -> Double {
        max(RoomGoalRuler.minimumGB, (RoomGoalRuler.upperGB(capacityGB: capacityGB) / 10).rounded(.down) * 10)
    }

    /// The only value the ruler ever writes: a resting detent converted to bytes, kept inside this Mac's range and
    /// re-validated with Settings' 20…200 GB clamp.
    static func storedBytes(restingGB: Double, capacityGB: Double) -> Int64 {
        guard restingGB.isFinite, capacityGB.isFinite else { return minimumGoalBytes }
        let gb = min(upperDetentGB(capacityGB: capacityGB), max(RoomGoalRuler.minimumGB, (restingGB / 10).rounded() * 10))
        let bytes = Int64(gb / 10) * goalStepBytes
        return RoomMenuBarSettings.clampGoalBytes(bytes)
    }

    static func gb(_ bytes: Int64) -> Double { Double(bytes) / Double(bytesPerGB) }

    /// Keyboard (PE-15): ←/→ ±10, Page ±50, Home/End to ends, through the ruler's own range for this Mac.
    enum Key { case left, right, pageUp, pageDown, home, end }
    static func step(_ bytes: Int64, key: Key, capacityGB: Double) -> Int64 {
        let gb = gb(bytes), hi = upperDetentGB(capacityGB: capacityGB)
        let next: Double
        switch key {
        case .left: next = gb - 10
        case .right: next = gb + 10
        case .pageDown: next = gb - 50
        case .pageUp: next = gb + 50
        case .home: next = RoomGoalRuler.minimumGB
        case .end: next = hi
        }
        return storedBytes(restingGB: RoomPure.nearestStep(next, step: 10, min: RoomGoalRuler.minimumGB, max: hi), capacityGB: capacityGB)
    }

    /// Detents crossed between two continuous values: one haptic `.alignment` per crossing (PE-13).
    static func detentsCrossed(from a: Double, to b: Double) -> Int { abs(RoomGoalRuler.detent(b) - RoomGoalRuler.detent(a)) }
}
