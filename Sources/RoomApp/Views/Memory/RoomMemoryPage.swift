import Foundation
import RoomCore

nonisolated enum RoomMemoryRange: String, CaseIterable {
    case now, quarter, hour

    var title: String { self == .now ? "Now" : self == .quarter ? "15 min" : "1 hour" }
    var seconds: Double { self == .now ? 300 : self == .quarter ? 900 : 3_600 }
}

/// What the Memory screen shows, worked out away from the views.
nonisolated enum RoomMemoryPage {
    /// A pause longer than three 20-second readings (sleep, Room closed) is a gap, not a line.
    static let gapSeconds: Double = 65
    static let visibleRows = 5
    static let expandedRows = 30

    static func window(_ samples: [RoomMemorySampleRing.Sample], range: RoomMemoryRange) -> [RoomMemorySampleRing.Sample] {
        guard let end = samples.last?.at else { return [] }
        return samples.filter { end.timeIntervalSince($0.at) <= range.seconds }
    }

    /// One sentence about the samples on screen; it names only the time they really cover.
    static func pressureSentence(_ window: [RoomMemorySampleRing.Sample]) -> String {
        guard let first = window.first, let last = window.last else { return "Waiting for the first reading" }
        guard let worst = window.compactMap(\.level).max() else { return "macOS didn’t report pressure" }
        let minutes = Int((last.at.timeIntervalSince(first.at) / 60).rounded())
        let word = worst.word.lowercased()
        guard minutes >= 1 else { return "Pressure is \(word) so far" }
        return "Pressure \(worst == .normal ? "stayed" : "reached") \(word) over the last \(minutes) min"
    }

    /// Curve points placed by time, newest at the right edge, split where readings are missing.
    static func runs(_ samples: [RoomMemorySampleRing.Sample], range: RoomMemoryRange, size: CGSize) -> [[CGPoint]] {
        var shown = window(samples, range: range)
        // One reading from just before the range lets the line reach the left edge; the canvas clips the rest.
        if let first = shown.first, let before = samples.last(where: { $0.at < first.at }),
           first.at.timeIntervalSince(before.at) <= gapSeconds {
            shown.insert(before, at: 0)
        }
        guard let end = shown.last?.at, let low = shown.map(\.bytes).min(), let high = shown.map(\.bytes).max() else { return [] }
        // The samples sit in the middle of the height, with at least a 3 GB band so a flat minute looks flat.
        let span = max(Double(high - low), 3e9)
        let bottom = Double(low) - span, top = Double(high) + span * 0.5
        var runs: [[CGPoint]] = []
        var previous: Date?
        for sample in shown {
            let x = size.width * CGFloat(1 - end.timeIntervalSince(sample.at) / range.seconds)
            let y = size.height * CGFloat(1 - (Double(sample.bytes) - bottom) / (top - bottom))
            if let previous, sample.at.timeIntervalSince(previous) <= gapSeconds {
                runs[runs.count - 1].append(CGPoint(x: x, y: y))
            } else {
                runs.append([CGPoint(x: x, y: y)])
            }
            previous = sample.at
        }
        return runs
    }

    static func background(_ processes: [MemoryProcess], apps: Set<Int32>) -> [MemoryProcess] {
        processes.filter { !apps.contains($0.id) }
    }

    /// Normal pressure needs no advice, and swap already has its own figure.
    static func advice(_ recommendations: [MemoryRecommendation]) -> [MemoryRecommendation] {
        recommendations.filter { $0.id != "normal" && $0.id != "swap" }
    }
}
