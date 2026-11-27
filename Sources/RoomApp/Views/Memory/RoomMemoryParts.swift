import AppKit
import RoomCore
import SwiftUI

/// Memory's headline and supporting line (nav-v3): "9 of 16 GB in use", "Pressure is normal".
nonisolated struct RoomMemoryWords: Equatable, Sendable {
    let headline: RoomHeadline
    let supporting: String

    static func make(usedBytes: Int64?, totalBytes: Int64?, pressureRaw: String?) -> RoomMemoryWords {
        guard let used = usedBytes, used > 0, let total = totalBytes, total > 0 else {
            return RoomMemoryWords(headline: .words("Reading memory"), supporting: "Pressure shows in a moment")
        }
        let usedText = RoomFormat.memory(used), totalText = RoomFormat.memory(total)
        // "9 of 16 GB": one unit when both are in GB, so the number leads.
        let figure = usedText.hasSuffix(" GB") && totalText.hasSuffix(" GB") ? String(usedText.dropLast(3)) : usedText
        let level = pressureRaw.flatMap(RoomPressureLevel.init(memoryPressureRaw:))
        let supporting = level.map { "Pressure is \($0.word.lowercased())" } ?? "Pressure is unknown right now"
        return RoomMemoryWords(headline: RoomHeadline(figure: figure, words: "of \(totalText) in use"), supporting: supporting)
    }

    /// The four figures under the curve, in order. A reading that failed is nil, never zero.
    static func figures(used: Int64, compressed: Int64, wired: Int64?, swap: Int64?) -> [(label: String, bytes: Int64?)] {
        let measured = used > 0
        let compressedBytes = max(0, min(used, compressed))
        let wiredBytes = wired.map { max(0, $0) }
        let app = wiredBytes.map { max(0, used - compressedBytes - $0) }
        return [("App memory", measured ? app : nil), ("Wired", measured ? wiredBytes : nil),
                ("Compressed", measured ? compressedBytes : nil), ("Swap used", swap.map { max(0, $0) })]
    }
}

extension RoomTokens {
    enum Memory2 {
        static let curveHeight: CGFloat = 130
        static let curveStroke: CGFloat = 1.6
        static let nowDot: CGFloat = 9
        static let nowHalo: CGFloat = 4
        static let figuresGap: CGFloat = 44
        static let columnsGap: CGFloat = 34
        static let columnsBreak: CGFloat = 560
        static let rowIcon: CGFloat = 20
        static let rowHeight: CGFloat = 32
    }
}

/// Memory in use over the chosen range. It changes only when a reading arrives.
struct RoomMemoryCurve: View {
    let samples: [RoomMemorySampleRing.Sample]
    let range: RoomMemoryRange
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        Canvas { context, size in
            // Room for the now-dot's halo at the right edge.
            let inset = RoomTokens.Memory2.nowDot / 2 + RoomTokens.Memory2.nowHalo
            let runs = RoomMemoryPage.runs(samples, range: range,
                                           size: CGSize(width: max(0, size.width - inset), height: size.height))
            for points in runs {
                guard let first = points.first, let last = points.last, points.count > 1 else { continue }
                // Smoothed through the midpoints, so a busy minute reads as a swell rather than a saw.
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
            }
            guard let now = runs.last?.last else { return }
            let d = RoomTokens.Memory2.nowDot, halo = RoomTokens.Memory2.nowHalo
            context.fill(Path(ellipseIn: CGRect(x: now.x - d / 2 - halo, y: now.y - d / 2 - halo,
                                                width: d + halo * 2, height: d + halo * 2)), with: .color(accent.wash))
            context.fill(Path(ellipseIn: CGRect(x: now.x - d / 2, y: now.y - d / 2, width: d, height: d)),
                         with: .color(accent.text))
        }
        .opacity(hide.masksNow ? 0.35 : 1)
        .accessibilityElement()
        .accessibilityLabel("Memory in use, \(range.title)")
        .accessibilityValue(RoomMemoryPage.pressureSentence(RoomMemoryPage.window(samples, range: range)))
    }
}

struct RoomMemoryFigures: View {
    let report: MemoryReport

    var body: some View {
        let figures = RoomMemoryWords.figures(used: report.usedBytes, compressed: report.compressedBytes,
                                              wired: report.wiredBytes,
                                              swap: RoomMonitorPresentation.measuredSwap(report))
        HStack(alignment: .top, spacing: RoomTokens.Memory2.figuresGap) {
            ForEach(figures, id: \.label) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    RoomMaskable(figure.bytes.map(RoomFormat.memory) ?? "—")
                        .font(RoomTokens.Screen2.figure)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                    Text(figure.label).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(figure.label): \(figure.bytes.map(RoomFormat.memory) ?? "not measured")")
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
