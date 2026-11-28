import AppKit
import RoomCore
import SwiftUI

/// Memory's headline and supporting line (nav-v3): "9 of 16 GB in use", "Pressure is normal".
nonisolated struct RoomMemoryWords: Equatable, Sendable {
    let headline: RoomHeadline
    let supporting: String

    static func make(usedBytes: Int64?, totalBytes: Int64?, pressureRaw: String?) -> RoomMemoryWords {
        guard let used = usedBytes, let total = totalBytes, total > 0 else {
            return RoomMemoryWords(headline: .words("Reading memory"), supporting: "Pressure shows in a moment")
        }
        let usedText = RoomFormat.memory(used), totalText = RoomFormat.memory(total)
        // "9 of 16 GB": one unit when both are in GB, so the number leads.
        let figure = usedText.hasSuffix(" GB") && totalText.hasSuffix(" GB") ? String(usedText.dropLast(3)) : usedText
        let level = pressureRaw.flatMap(RoomPressureLevel.init(memoryPressureRaw:))
        let supporting = level.map { "Pressure is \($0.word.lowercased())" } ?? "Pressure is unknown right now"
        return RoomMemoryWords(headline: RoomHeadline(figure: figure, words: "of \(totalText) in use"), supporting: supporting)
    }

    /// The four figures under the curve, in order.
    static func figures(_ report: MemoryReport) -> [(label: String, bytes: Int64)] {
        let compressed = max(0, min(report.usedBytes, report.compressedBytes))
        let wired = max(0, report.wiredBytes ?? 0)
        let app = max(0, report.usedBytes - compressed - wired)
        return [("App memory", app), ("Wired", wired), ("Compressed", compressed), ("Swap used", max(0, report.swapUsedBytes))]
    }
}

extension RoomTokens {
    enum Memory2 {
        static let curveHeight: CGFloat = 150
        static let curveStroke: CGFloat = 1.6
        static let nowDot: CGFloat = 9
        static let nowHalo: CGFloat = 4
        static let figuresGap: CGFloat = 44
    }
}

/// The live curve: memory in use, one sample a second while Memory is open. It changes only when a sample arrives.
struct RoomMemoryCurve: View {
    let samples: [Int64]
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        Canvas { context, size in
            let points = Self.points(samples, size: size)
            guard let first = points.first, let last = points.last else { return }
            // Smoothed through the midpoints like the mockup's curve (`Q` to each midpoint), so a busy minute reads
            // as a swell rather than a saw.
            var line = Path()
            line.move(to: first)
            if points.count > 2 {
                for index in 1..<(points.count - 1) {
                    let point = points[index], next = points[index + 1]
                    line.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
                }
            }
            line.addLine(to: last)
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(accent.wash))
            context.stroke(line, with: .color(RoomTokens.Ink.graphite),
                           style: StrokeStyle(lineWidth: RoomTokens.Memory2.curveStroke, lineCap: .round, lineJoin: .round))
            let d = RoomTokens.Memory2.nowDot, halo = RoomTokens.Memory2.nowHalo
            context.fill(Path(ellipseIn: CGRect(x: last.x - d / 2 - halo, y: last.y - d / 2 - halo, width: d + halo * 2, height: d + halo * 2)),
                         with: .color(accent.wash))
            context.fill(Path(ellipseIn: CGRect(x: last.x - d / 2, y: last.y - d / 2, width: d, height: d)), with: .color(accent.text))
        }
        .opacity(hide.masksNow ? 0.35 : 1)
        .accessibilityElement()
        .accessibilityLabel("Memory in use over the last few minutes")
    }

    /// The mockup's scale: the samples sit in the middle third with room above and below (a 9 GB band over 16 GB).
    static func points(_ samples: [Int64], size: CGSize) -> [CGPoint] {
        guard samples.count >= 2, let low = samples.min(), let high = samples.max() else { return [] }
        let range = max(Double(high - low), 3e9)
        let bottom = Double(low) - range, top = Double(high) + range * 0.5
        let step = size.width / CGFloat(samples.count - 1)
        return samples.enumerated().map { index, value in
            let y = size.height * (1 - CGFloat((Double(value) - bottom) / (top - bottom)))
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

struct RoomMemoryFigures: View {
    let report: MemoryReport

    var body: some View {
        HStack(alignment: .top, spacing: RoomTokens.Memory2.figuresGap) {
            ForEach(RoomMemoryWords.figures(report), id: \.label) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    RoomMaskable(RoomFormat.memory(figure.bytes))
                        .font(RoomTokens.Screen2.figure)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                    Text(figure.label).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A running app's real icon; Hide shows a blank tile; a process without an app shows a quiet tile.
struct RoomProcessIcon: View {
    let pid: Int32
    var name: String? = nil
    var size: CGFloat = RoomTokens.Screen2.icon
    @Environment(\.roomHide) private var hide

    var body: some View {
        Group {
            if hide.masksNow {
                RoundedRectangle(cornerRadius: RoomTokens.Screen2.iconRadius).fill(RoomTokens.Surface.tile)
            } else if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoomThingIcon(path: nil, name: name, fallback: .window, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
