import Accessibility
import Charts
import RoomCore
import SwiftUI

struct RoomOverviewHistoryLink: View {
    let log: RoomVolumeSampleLog
    let goal: Int64?
    let latestReceipt: RoomMakeRoomEntry?
    let earlierMap: RoomStoredTree?
    let currentMap: RoomStoredTree?

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @FocusState private var linkFocused: Bool
    @State private var showsHistory = false
    @State private var clock = Date.now

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let change = log.change(now: clock, calendar: calendar)
        let growth = RoomOverviewHistoryGrowth.between(earlierMap, currentMap,
            volume: log.latest?.volumeID, now: clock, calendar: calendar)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.inner) { line(change, growth: growth); link(growth: growth) }
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) { line(change, growth: growth); link(growth: growth) }
        }
        .font(RoomTokens.Typography.body)
        .onChange(of: log.latest?.at, initial: true) { _, _ in clock = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in clock = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in clock = .now }
    }

    @ViewBuilder private func line(_ change: RoomVolumeChange, growth: RoomOverviewHistoryGrowth?) -> some View {
        if case .since(let date, let bytes) = change {
            let amount = RoomFormat.overviewBytes(abs(bytes))
            let result = if bytes > 0 { "Since \(date): \(amount) used." }
                else if bytes < 0 { "Since \(date): \(amount) freed." }
                else { "No change since \(date)." }
            if date == "Monday", bytes > 0, let growth, growth.bytes > bytes / 2, !hide.masksNow {
                Text("Since \(date): \(amount) used, mostly \(growth.name).")
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                RoomMaskable(result).foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private func link(growth: RoomOverviewHistoryGrowth?) -> some View {
        Button { showsHistory = true } label: {
            Label("Your week", systemImage: "chart.xyaxis.line")
        }
        .roomLink(accent)
        .focused($linkFocused)
        .accessibilityIdentifier("RoomOverviewYourWeek")
        .popover(isPresented: $showsHistory, arrowEdge: .bottom) {
            RoomOverviewHistoryPopover(log: log, goal: goal, latestReceipt: latestReceipt, growth: growth, now: clock)
        }
        .onChange(of: showsHistory) { _, showing in if !showing { linkFocused = true } }
    }
}

private struct RoomOverviewHistoryPopover: View {
    let log: RoomVolumeSampleLog
    let goal: Int64?
    let latestReceipt: RoomMakeRoomEntry?
    let growth: RoomOverviewHistoryGrowth?
    let now: Date

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @FocusState private var rangeFocused: Bool
    @State private var range = RoomOverviewHistoryRange.week
    @State private var metric = RoomOverviewHistoryMetric.change
    @State private var hovering: Int?
    @State private var keyboard: Int?

    private let chartHeight: CGFloat = 200
    private let bytesPerGB: Double = 1_000_000_000

    var body: some View {
        let history = RoomOverviewHistory(log: log, range: range, now: now, calendar: .autoupdatingCurrent)
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text("Your week").font(RoomTokens.Typography.title).accessibilityHeading(.h1)
            HStack(spacing: RoomTokens.Space.inner) {
                Picker("Time range", selection: $range) {
                    ForEach(RoomOverviewHistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .focused($rangeFocused)
                Picker("Storage metric", selection: $metric) {
                    ForEach(RoomOverviewHistoryMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let chart = chart(history)
            if hide.masksNow {
                chart
            } else {
                chart.accessibilityChartDescriptor(
                    RoomOverviewHistoryChartAccessibility(history: history, range: range,
                        metric: metric, domain: bounds(history), summary: readout(history))
                )
            }
            Text(readout(history))
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .accessibilityHidden(true)
            if let goal, metric == .freeSpace, range == .twelveWeeks {
                RoomMaskable("Goal: keep \(RoomFormat.overviewBytes(goal)) free")
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
            notes(history)
        }
        .padding(RoomTokens.Space.group)
        .frame(width: 520)
        .task { rangeFocused = true }
        .onChange(of: range) { _, _ in hovering = nil; keyboard = nil }
        .onChange(of: metric) { _, _ in hovering = nil; keyboard = nil }
    }

    private func chart(_ history: RoomOverviewHistory) -> some View {
        let points = history.points
        let domain = bounds(history)
        let selection = hovering ?? keyboard
        let xLabels = points.filter { range != .day || $0.id.isMultiple(of: 4) }.map { Double($0.id) }
        return Chart {
            if metric == .change {
                RuleMark(y: .value("No change", 0)).foregroundStyle(RoomTokens.Surface.line2)
                ForEach(points) { point in
                    if let bytes = point.usedChange {
                        changeMarks(point, bytes: bytes, selected: selection == point.id)
                    }
                }
            } else {
                ForEach(points) { point in
                    if let bytes = point.sample?.freeBytes {
                        freeSpaceMarks(point, bytes: bytes, isLatest: history.latest(for: .freeSpace)?.id == point.id,
                                       selected: selection == point.id, floor: domain.lowerBound)
                    }
                }
                if range == .twelveWeeks, let goal {
                    RuleMark(y: .value("Goal", gb(goal)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle((history.latest(for: .freeSpace)?.sample?.freeBytes ?? goal) < goal
                                         ? RoomTokens.Status.elevated : accent.text)
                }
            }
            if let selection {
                RuleMark(x: .value("Selected", Double(selection)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .chartXScale(domain: -0.5...(Double(points.count) - 0.5))
        .chartYScale(domain: domain)
        .chartYAxisLabel("GB")
        .chartXAxis {
            AxisMarks(values: xLabels) { value in
                AxisValueLabel {
                    if let index = value.as(Double.self).map(Int.init), points.indices.contains(index) {
                        Text(range.label(at: points[index].bucket)).font(RoomTokens.Typography.micro)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(RoomTokens.Surface.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(hide.masksNow ? "••" : number.formatted(.number.precision(.fractionLength(0...1))))
                            .font(RoomTokens.Typography.micro)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background {
                Canvas { context, size in
                    let width = size.width / Double(points.count)
                    var hatch = Path()
                    for point in points where point.value(for: metric) == nil && point.bucket <= now {
                        let x = Double(point.id) * width
                        for y in stride(from: -width, to: size.height, by: 6) {
                            let start = max(0, -y)
                            let end = min(width, size.height - y)
                            guard start < end else { continue }
                            hatch.move(to: CGPoint(x: x + start, y: y + start))
                            hatch.addLine(to: CGPoint(x: x + end, y: y + end))
                        }
                    }
                    context.stroke(hatch, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let anchor = proxy.plotFrame else {
                            hovering = nil
                            return
                        }
                        let frame = geometry[anchor]
                        guard frame.contains(location),
                              let value = proxy.value(atX: location.x - frame.minX, as: Double.self) else {
                            hovering = nil
                            return
                        }
                        hovering = min(points.count - 1, max(0, Int(value.rounded())))
                    }
            }
        }
        .frame(height: chartHeight)
        .animation(motion.animation(RoomTokens.Motion.morph, fallback: RoomTokens.Motion.fade), value: range)
        .animation(motion.animation(RoomTokens.Motion.morph, fallback: RoomTokens.Motion.fade), value: metric)
        .focusable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage history, \(range.title), \(metric.title)")
        .accessibilityValue(hide.masksNow ? "Size hidden" : readout(history))
        .accessibilityHint("Use the arrow keys, Home or End to select a measurement.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: moveSelection(history, by: 1)
            case .decrement: moveSelection(history, by: -1)
            @unknown default: break
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end], phases: [.down, .repeat]) { press in
            switch press.key {
            case .leftArrow: moveSelection(history, by: -1)
            case .rightArrow: moveSelection(history, by: 1)
            case .home: setSelection(0)
            case .end: setSelection(points.count - 1)
            default: return .ignored
            }
            AccessibilityNotification.Announcement(hide.masksNow ? "Size hidden" : readout(history)).post()
            return .handled
        }
    }

    @ChartContentBuilder private func changeMarks(_ point: RoomOverviewHistoryPoint, bytes: Int64, selected: Bool) -> some ChartContent {
        let count = Int(abs(gb(bytes)).rounded())
        if range == .week, count > 0, count <= 32 {
            ForEach(1...count, id: \.self) { index in
                let value = Double(index) * (bytes > 0 ? 1 : -1)
                PointMark(x: .value("Period", Double(point.id)), y: .value("Change", value))
                    .symbolSize(selected ? 28 : 18)
                    .symbol {
                        if bytes > 0 {
                            Circle().fill(accent.fill).frame(width: selected ? 7.5 : 6, height: selected ? 7.5 : 6)
                        } else {
                            Circle().strokeBorder(accent.text, lineWidth: 1.2)
                                .frame(width: selected ? 7.5 : 6, height: selected ? 7.5 : 6)
                        }
                    }
            }
        } else if bytes == 0 {
            PointMark(x: .value("Period", Double(point.id)), y: .value("No change", 0))
                .symbolSize(selected ? 24 : 12)
                .foregroundStyle(RoomTokens.Ink.secondary)
        } else {
            BarMark(x: .value("Period", Double(point.id)), y: .value("Change", gb(bytes)),
                    width: .ratio(selected ? 0.84 : 0.67))
                .foregroundStyle(bytes > 0 ? accent.fill : RoomTokens.Surface.used)
        }
    }

    @ChartContentBuilder private func freeSpaceMarks(_ point: RoomOverviewHistoryPoint, bytes: Int64,
                                                     isLatest: Bool, selected: Bool, floor: Double) -> some ChartContent {
        if range == .twelveWeeks {
            AreaMark(x: .value("Period", Double(point.id)), yStart: .value("Floor", floor),
                     yEnd: .value("Free space", gb(bytes)), series: .value("Continuous samples", point.run))
                .foregroundStyle(accent.wash)
            if let goal, let delta = point.sample.map({ $0.freeBytes - goal }) {
                let width = selected ? 0.29 : 0.18
                RectangleMark(xStart: .value("Start", Double(point.id) - width),
                              xEnd: .value("End", Double(point.id) + width),
                              yStart: .value("Goal", gb(goal)), yEnd: .value("Free space", gb(bytes)))
                    .foregroundStyle(delta < 0 ? RoomTokens.Status.elevated : accent.fill)
            }
        }
        LineMark(x: .value("Period", Double(point.id)), y: .value("Free space", gb(bytes)),
                 series: .value("Continuous samples", point.run))
            .foregroundStyle(accent.text)
            .lineStyle(StrokeStyle(lineWidth: 2))
        PointMark(x: .value("Period", Double(point.id)), y: .value("Free space", gb(bytes)))
            .foregroundStyle(accent.text)
            .symbolSize(isLatest || selected ? 45 : 12)
    }

    @ViewBuilder private func notes(_ history: RoomOverviewHistory) -> some View {
        if let receipt = latestReceipt, let start = history.points.first?.bucket,
           (start...now).contains(receipt.lastChangedAt) {
            let date = receipt.lastChangedAt.formatted(.dateTime.weekday(.abbreviated))
            let caption = RoomMakeRoomCopy.headline(receipt, format: RoomFormat.overviewBytes)
            RoomMaskable("\(date): \(caption)")
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
        }
        if let growth, let goal, let latest = history.latest(for: .freeSpace)?.sample, latest.freeBytes < goal,
           let start = history.points.first?.bucket, (start...now).contains(growth.measuredAt), !hide.masksNow {
            let bytes = RoomFormat.overviewBytes(growth.bytes)
            Text("\(growth.name) grew by \(bytes) between maps.")
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
        }
        if range == .twelveWeeks, metric == .freeSpace {
            let history = RoomOverviewHistory(log: log, range: .twelveWeeks, now: now, calendar: .autoupdatingCurrent)
            if let months = history.monthsUntilGoal(goal) {
                RoomMaskable("At this pace, about \(months) \(months == 1 ? "month" : "months") to your free-space goal.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private func bounds(_ history: RoomOverviewHistory) -> ClosedRange<Double> {
        var values = history.points.compactMap { $0.value(for: metric) }.map(gb)
        if metric == .change { values.append(0) }
        else if range == .twelveWeeks, let goal { values.append(gb(goal)) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max(1, (high - low) * 0.1)
        return (metric == .freeSpace ? max(0, low - pad) : low - pad)...(high + pad)
    }

    private func readout(_ history: RoomOverviewHistory) -> String {
        let selection = (hovering ?? keyboard).flatMap { history.points.indices.contains($0) ? history.points[$0] : nil }
        guard let point = selection ?? history.latest(for: metric) else {
            return metric == .change ? "More measurements are needed to show a change." : "No measurements in this range."
        }
        let label = range.label(at: point.bucket)
        guard let value = point.value(for: metric) else {
            return point.bucket > now ? "\(label): upcoming" : "\(label): no comparable measurement"
        }
        guard !hide.masksNow else { return "\(label): size hidden" }
        let amount = RoomFormat.overviewBytes(abs(value))
        switch metric {
        case .freeSpace: return "\(label): \(amount) free"
        case .change where value > 0: return "\(label): \(amount) used"
        case .change where value < 0: return "\(label): \(amount) freed"
        case .change: return "\(label): no change"
        }
    }

    private func moveSelection(_ history: RoomOverviewHistory, by delta: Int) {
        let current = keyboard ?? hovering ?? history.latest(for: metric)?.id ?? history.points.count - 1
        setSelection(min(history.points.count - 1, max(0, current + delta)))
    }

    private func setSelection(_ index: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hovering = nil
            keyboard = index
        }
    }

    private func gb(_ bytes: Int64) -> Double { Double(bytes) / bytesPerGB }
}

nonisolated private struct RoomOverviewHistoryChartAccessibility: AXChartDescriptorRepresentable {
    let history: RoomOverviewHistory
    let range: RoomOverviewHistoryRange
    let metric: RoomOverviewHistoryMetric
    let domain: ClosedRange<Double>
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = history.points.map(\.bucket)
        let x = AXNumericDataAxisDescriptor(title: "Time", range: 0...Double(dates.count - 1), gridlinePositions: []) { value in
            let index = min(dates.count - 1, max(0, Int(value.rounded())))
            return range.label(at: dates[index])
        }
        let y = AXNumericDataAxisDescriptor(title: metric.title, range: domain, gridlinePositions: []) { value in
            "\(value.formatted(.number.precision(.fractionLength(0...1)))) gigabytes"
        }
        let samples = history.points.compactMap { point -> AXDataPoint? in
            guard let value = point.value(for: metric) else { return nil }
            return AXDataPoint(x: Double(point.id), y: Double(value) / 1_000_000_000)
        }
        let series = AXDataSeriesDescriptor(name: metric.title, isContinuous: false, dataPoints: samples)
        return AXChartDescriptor(title: "Your week", summary: summary, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [series])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let next = makeChartDescriptor()
        descriptor.summary = next.summary
        descriptor.xAxis = next.xAxis
        descriptor.yAxis = next.yAxis
        descriptor.series = next.series
    }
}
