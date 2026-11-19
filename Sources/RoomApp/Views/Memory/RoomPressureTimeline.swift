import Charts
import SwiftUI

enum RoomMemoryRange: String, CaseIterable {
    case day, week

    var title: String { self == .day ? "24 hours" : "7 days" }
    var intervalTitle: String { self == .day ? "every 15 minutes" : "every 2 hours" }
    var keyboardJump: Int { self == .day ? 4 : 12 }

    func series(in history: RoomPressureHistory) -> RoomPressureSeries {
        self == .day ? history.day : history.week
    }
}

struct RoomPressureTimeline: View {
    let series: RoomPressureSeries
    let now: Date
    let level: RoomPressureLevel?
    @Binding var range: RoomMemoryRange
    @Environment(\.roomMotion) private var motion
    @State private var selection: Date?
    @State private var keyboardSelection = false

    private var columns: [RoomPressureBucket?] { series.columns(now: now) }
    private var firstIndex: Int64 { series.bucketIndex(now) - Int64(series.capacity) + 1 }
    private var selectedIndex: Int? {
        selection.map { min(series.capacity - 1, max(0, Int(series.bucketIndex($0) - firstIndex))) }
    }
    private var selectedLevel: RoomPressureLevel? {
        guard let selectedIndex else { return level }
        return columns[selectedIndex]?.worst
    }
    private var firstDate: Date { series.start(of: firstIndex) }
    private var endDate: Date { series.start(of: firstIndex + Int64(series.capacity)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pressure").font(RoomTokens.Typography.title)
                Text(range.intervalTitle).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Pressure history range", selection: $range) {
                    ForEach(RoomMemoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            chart
                .frame(height: 210)
                .focusable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pressure timeline")
                .accessibilityValue(readout)
                .accessibilityHint("Use left and right arrow keys to move by one bucket. Hold Option to jump.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(by: 1)
                    case .decrement: move(by: -1)
                    @unknown default: break
                    }
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                    let jump = press.modifiers.contains(.option) ? range.keyboardJump : 1
                    move(by: press.key == .leftArrow ? -jump : jump)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard selection != nil else { return .ignored }
                    selection = nil
                    return .handled
                }
            HStack(spacing: 8) {
                RoomPocketScrubber(level: selectedLevel, size: 26)
                    .animation(motion.isFull && !keyboardSelection ? RoomTokens.Motion.standard : nil, value: selectedLevel)
                Text(readout).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }.accessibilityHidden(true)
        }
        .onChange(of: range) { _, _ in selection = nil }
    }

    private var chart: some View {
        Chart {
            ForEach(RoomPressureLevel.allCases, id: \.self) { level in
                RectangleMark(xStart: .value("From", firstDate), xEnd: .value("To", endDate),
                              yStart: .value("Lane", Double(level.rawValue) - 0.45),
                              yEnd: .value("Lane", Double(level.rawValue) + 0.45))
                    .foregroundStyle(RoomPocketScrubber.color(level).opacity(RoomTokens.Status.pressureLaneOpacity))
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Pressure", point.level.rawValue),
                         series: .value("Continuous samples", point.run))
                    .interpolationMethod(.stepStart)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, bucket in
                if let level = bucket?.worst, level != .normal {
                    let start = series.start(of: firstIndex + Int64(index))
                    let end = start.addingTimeInterval(Double(series.bucketSeconds))
                    let y = Double(level.rawValue)
                    RectangleMark(xStart: .value("From", start), xEnd: .value("To", end),
                                  yStart: .value("Cap", y + 0.03), yEnd: .value("Cap", y + 0.11))
                        .foregroundStyle(RoomPocketScrubber.color(level))
                }
            }
            if let selectedIndex {
                RuleMark(x: .value("Selected", series.start(of: firstIndex + Int64(selectedIndex)) +
                                    Double(series.bucketSeconds) / 2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: firstDate...endDate)
        .chartYScale(domain: -0.5...2.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2]) { value in
                AxisValueLabel {
                    if let number = value.as(Int.self), let level = RoomPressureLevel(rawValue: number) {
                        Text(level.word).font(RoomTokens.Typography.micro)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background {
                Canvas { context, size in
                    let width = size.width / Double(series.capacity)
                    var lines = Path()
                    for (index, bucket) in columns.enumerated() where bucket == nil {
                        let x = Double(index) * width
                        for y in stride(from: -width, to: size.height, by: 6) {
                            let x1 = x + max(0, -y)
                            let x2 = x + min(width, size.height - y)
                            guard x2 > x1 else { continue }
                            lines.move(to: CGPoint(x: x1, y: y + x1 - x))
                            lines.addLine(to: CGPoint(x: x2, y: y + x2 - x))
                        }
                    }
                    context.stroke(lines, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
                }.help("Room wasn’t running in the gaps")
            }
        }
        .chartXSelection(value: Binding(get: { selection }, set: {
            keyboardSelection = false
            selection = $0
        }))
    }

    private var readout: String {
        guard let selectedIndex else { return level.map { "\($0.word) · now" } ?? "Pressure unavailable · now" }
        let date = series.start(of: firstIndex + Int64(selectedIndex))
        let label = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return RoomPressureFinding.readout(columns, at: selectedIndex, bucketSeconds: series.bucketSeconds, label: label)
    }

    private func move(by delta: Int) {
        keyboardSelection = true
        let index = min(series.capacity - 1, max(0, (selectedIndex ?? series.capacity - 1) + delta))
        selection = series.start(of: firstIndex + Int64(index)) + Double(series.bucketSeconds) / 2
    }

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let level: RoomPressureLevel
        let run: Int
    }

    private var points: [Point] {
        let columns = columns
        var result: [Point] = []
        var run = 0
        for (index, bucket) in columns.enumerated() {
            guard let bucket else { continue }
            if index == 0 || columns[index - 1] == nil { run += 1 }
            let start = series.start(of: bucket.index)
            result.append(Point(id: index * 2, date: start, level: bucket.worst, run: run))
            if index == columns.count - 1 || columns[index + 1] == nil {
                result.append(Point(id: index * 2 + 1, date: start + Double(series.bucketSeconds),
                                    level: bucket.worst, run: run))
            }
        }
        return result
    }
}
