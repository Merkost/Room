import Accessibility
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

/// How the pressure history is laid out (REVIEW §3 Memory): one quiet strip while the whole range is Normal,
/// the three lanes only when the range holds Elevated or Critical, or while the person hovers or opens it.
nonisolated enum RoomPressureLayout {
    static func showsLanes(_ columns: [RoomPressureBucket?], hovering: Bool, pinnedOpen: Bool) -> Bool {
        hovering || pinnedOpen || columns.contains { ($0?.worst ?? .normal) != .normal }
    }

    /// Changes once per new sample, so the now-dot pulses once per sample and never at rest.
    static func sampleKey(_ columns: [RoomPressureBucket?]) -> Int64? {
        guard let last = columns.last(where: { $0 != nil }) ?? nil else { return nil }
        return last.index &* 10_000 &+ Int64(last.count)
    }
}

/// The line draws on once per launch, the first time the Memory screen opens.
@MainActor enum RoomPressureDrawOn {
    static var played = false
}

struct RoomPressureTimeline: View {
    let series: RoomPressureSeries
    let now: Date
    let level: RoomPressureLevel?
    let finding: String
    @Binding var range: RoomMemoryRange
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var selection: Date?
    @State private var keyboardSelection = false
    @State private var hovering = false
    @State private var pinnedOpen = false
    @State private var drawn = RoomPressureDrawOn.played

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
        let lanes = RoomPressureLayout.showsLanes(columns, hovering: hovering, pinnedOpen: pinnedOpen)
        let calm = !RoomPressureLayout.showsLanes(columns, hovering: false, pinnedOpen: false)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pressure").font(RoomTokens.Typography.title).accessibilityHeading(.h2)
                Text(range.intervalTitle).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                Spacer()
                if calm {
                    Button(pinnedOpen ? "Show less" : "Show lanes") { pinnedOpen.toggle() }
                        .roomLink(accent)
                        .font(RoomTokens.Typography.caption)
                        .accessibilityHint("Shows the Normal, Elevated and Critical lanes")
                }
                Picker("Pressure history range", selection: $range) {
                    ForEach(RoomMemoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Group {
                if lanes {
                    lanesChart.transition(.opacity)
                } else {
                    strip.transition(.opacity)
                }
            }
            .onHover { inside in
                withAnimation(motion.animation(RoomTokens.Motion.standard, fallback: RoomTokens.Motion.fade)) { hovering = inside }
            }
            .onAppear {
                guard !drawn else { return }
                RoomPressureDrawOn.played = true
                withAnimation(motion.animation(RoomDS.Motion.timed(.slow), fallback: nil)) { drawn = true }
            }
            HStack(spacing: 8) {
                RoomPocketScrubber(level: selectedLevel, size: 26)
                    .animation(motion.isFull && !keyboardSelection ? RoomTokens.Motion.standard : nil, value: selectedLevel)
                Text(readout).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }.accessibilityHidden(true)
        }
        .onChange(of: range) { _, _ in selection = nil }
    }

    /// One line while the range is all Normal: measured time in the Normal tint, the honest hatch where Room wasn't running.
    private var strip: some View {
        HStack(spacing: RoomTokens.Space.row) {
            Text(RoomPressureLevel.normal.word).font(RoomTokens.Typography.micro).foregroundStyle(.secondary)
            Canvas { context, size in
                let width = size.width / Double(series.capacity)
                var measured = Path()
                var gaps = Path()
                for (index, bucket) in columns.enumerated() {
                    let rect = CGRect(x: Double(index) * width, y: 0, width: width, height: size.height)
                    if bucket == nil {
                        for y in stride(from: -width, to: size.height, by: 6) {
                            gaps.move(to: CGPoint(x: rect.minX, y: y + width))
                            gaps.addLine(to: CGPoint(x: rect.maxX, y: y))
                        }
                    } else {
                        measured.addRect(rect)
                    }
                }
                let reveal = CGRect(x: 0, y: 0, width: size.width * (drawn ? 1 : 0), height: size.height)
                context.clip(to: Path(reveal))
                context.fill(measured, with: .color(RoomTokens.Status.normal.opacity(RoomTokens.Status.pressureLaneOpacity * 3)))
                context.stroke(gaps, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
            }
            .clipShape(Capsule())
            .frame(height: RoomTokens.Map.kindBarHeight)
            .help("Room wasn’t running in the gaps")
        }
        .frame(height: RoomTokens.Map.readoutHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finding)
        .accessibilityHint("Pressure stayed Normal. Use Show lanes to see the full chart.")
    }

    private var lanesChart: some View {
            chart
                .frame(height: 210)
                .animation(motion.animation(RoomTokens.Motion.fade, fallback: nil), value: range)
                .accessibilityChartDescriptor(RoomPressureChartAccessibility(series: series, now: now, finding: finding))
                .focusable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(finding)
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
                    AccessibilityNotification.Announcement(readout).post()
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard selection != nil else { return .ignored }
                    selection = nil
                    return .handled
                }
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
        .chartOverlay { proxy in
            nowDot(proxy)
        }
        .chartPlotStyle { plot in
            plot.mask(alignment: .leading) {
                // Draw-on, left to right, once per launch (Reduce Motion: already drawn).
                GeometryReader { geometry in
                    Rectangle().frame(width: geometry.size.width * (drawn ? 1 : 0))
                }
            }
            .background {
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
            if $0 == nil && selection != nil { AccessibilityNotification.Announcement(readout).post() }
            selection = $0
        }))
    }

    /// The "now" dot: one pulse per new sample, still at rest.
    private func nowDot(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let level, let plot = proxy.plotFrame, let x = proxy.position(forX: now),
               let y = proxy.position(forY: Double(level.rawValue)) {
                let origin = geometry[plot].origin
                RoomNowDot(color: RoomPocketScrubber.color(level),
                           trigger: motion.isFull ? RoomPressureLayout.sampleKey(columns) : nil)
                    .position(x: origin.x + x, y: origin.y + y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// One ring leaves the dot when a new sample lands (trigger changes), then nothing moves until the next one.
private struct RoomNowDot: View {
    let color: Color
    let trigger: Int64?

    private enum Pulse: CaseIterable { case rest, start, end }

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .phaseAnimator(Pulse.allCases, trigger: trigger) { ring, phase in
                    ring.scaleEffect(phase == .end ? 2.4 : 1).opacity(phase == .start ? 0.8 : 0)
                } animation: { phase in
                    phase == .end ? RoomDS.Motion.timed(.slow) : RoomTokens.Motion.quick
                }
            Circle().fill(color).frame(width: 6, height: 6)
        }
    }
}

nonisolated struct RoomPressureChartAccessibility: AXChartDescriptorRepresentable {
    let series: RoomPressureSeries
    let now: Date
    let finding: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let first = series.bucketIndex(now) - Int64(series.capacity) + 1
        let x = AXNumericDataAxisDescriptor(title: "Time", range: 0...Double(series.capacity - 1), gridlinePositions: []) { offset in
            series.start(of: first + Int64(offset.rounded()))
                .formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        let y = AXNumericDataAxisDescriptor(title: "Pressure", range: 0...2, gridlinePositions: [0, 1, 2]) { value in
            RoomPressureLevel(rawValue: Int(value.rounded()))?.word ?? "Pressure unavailable"
        }
        let columns = series.columns(now: now)
        let lanes = RoomPressureLevel.allCases.map { level in
            let points = columns.enumerated().compactMap { index, bucket -> AXDataPoint? in
                guard bucket?.worst == level else { return nil }
                return AXDataPoint(x: Double(index), y: Double(level.rawValue))
            }
            return AXDataSeriesDescriptor(name: level.word, isContinuous: false, dataPoints: points)
        }
        return AXChartDescriptor(title: "Memory pressure", summary: finding,
                                 xAxis: x, yAxis: y, additionalAxes: [], series: lanes)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let next = makeChartDescriptor()
        descriptor.summary = next.summary
        descriptor.xAxis = next.xAxis
        descriptor.yAxis = next.yAxis
        descriptor.series = next.series
    }
}
