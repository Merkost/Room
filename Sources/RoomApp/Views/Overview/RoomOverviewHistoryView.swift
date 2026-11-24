import Accessibility
import Charts
import RoomCore
import SwiftUI

/// The whole-volume change since a day. It includes things Room did not do (builds, the sleep image, Time Machine),
/// so it never says "freed" or "made": only the ledger-backed receipt line may claim Room's work (REVIEW §2.9).
nonisolated enum RoomOverviewHistoryCopy {
    static func volumeLine(bytes: Int64, since date: String, amount: String) -> String {
        if bytes > 0 { return "Since \(date): \(amount) used." }
        if bytes < 0 { return "\(amount) more free than \(date)." }
        return "No change since \(date)."
    }
}

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
            let amount = RoomFormat.gb(abs(bytes))
            let result = RoomOverviewHistoryCopy.volumeLine(bytes: bytes, since: date, amount: amount)
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
    @State private var transition: RoomOverviewHistoryTransition?

    private let chartHeight: CGFloat = 200

    var body: some View {
        let history = RoomOverviewHistory(log: log, range: range, now: now, calendar: .autoupdatingCurrent)
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text("Your week").font(RoomDisplayType.chapter).tracking(RoomDisplayType.chapterTracking).accessibilityHeading(.h1)
            HStack(spacing: RoomTokens.Space.inner) {
                Picker("Time range", selection: Binding(get: { range }, set: { changePlot(range: $0, metric: metric) })) {
                    ForEach(RoomOverviewHistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .focused($rangeFocused)
                Picker("Storage metric", selection: Binding(get: { metric }, set: { changePlot(range: range, metric: $0) })) {
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
                RoomMaskable("Goal: keep \(RoomFormat.gb(goal)) free")
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
            notes(history)
        }
        .padding(RoomTokens.Space.group)
        .frame(width: 520)
        .task { rangeFocused = true }
        .onChange(of: log) { _, _ in transition = nil }
        .onChange(of: goal) { _, _ in transition = nil }
        .onChange(of: motion) { _, _ in transition = nil }
        .task(id: transition?.start) {
            guard let transition else { return }
            try? await ContinuousClock().sleep(until: transition.start.advanced(by: .seconds(transition.duration)))
            guard !Task.isCancelled, self.transition?.start == transition.start else { return }
            self.transition = nil
        }
    }

    private func chart(_ history: RoomOverviewHistory) -> some View {
        let points = history.points
        let domain = bounds(history)
        let selection = hovering ?? keyboard
        let xLabels = points.filter { point in
            switch range {
            case .day: point.id.isMultiple(of: 4)
            case .week: true
            case .twelveWeeks: (points.count - 1 - point.id).isMultiple(of: 2)
            }
        }.map { Double($0.id) }
        let plot = RoomOverviewHistoryPlot(history: history, range: range, metric: metric,
            domain: domain, now: now, selected: selection)
        return Chart {
            // Keep explicit axes mounted in Free Space even when there are no native marks.
            RuleMark(y: .value("Plot boundary", domain.lowerBound))
                .foregroundStyle(Color.clear)
                .accessibilityHidden(true)
            if metric == .change {
                RuleMark(y: .value("No change", 0)).foregroundStyle(RoomTokens.Surface.line2)
            } else if range == .twelveWeeks, let goal {
                goalMarks(points, goal: goal, selected: selection, latest: history.latest(for: .freeSpace)?.sample)
            }
            if let selection, points.indices.contains(selection) {
                RuleMark(x: .value("Selected", Double(selection)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(RoomTokens.Ink.secondary)
                if let bytes = points[selection].value(for: metric) {
                    PointMark(x: .value("Selected", Double(selection)), y: .value("Measurement", gb(bytes)))
                        .symbol {
                            Circle().strokeBorder(accent.text, lineWidth: 1.5)
                                .frame(width: RoomTokens.Space.inner, height: RoomTokens.Space.inner)
                        }
                }
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: RoomTokens.Space.breath2, alignment: .trailing)
                    }
                }
            }
        }
        .chartPlotStyle { area in
            area.background {
                RoomOverviewHistoryPlotView(plot: plot, transition: transition).equatable()
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

    @ChartContentBuilder private func goalMarks(_ points: [RoomOverviewHistoryPoint], goal: Int64,
                                                  selected: Int?, latest: RoomVolumeSample?) -> some ChartContent {
        ForEach(points) { point in
            if let bytes = point.sample?.freeBytes {
                let width = selected == point.id ? 0.29 : 0.18
                RectangleMark(xStart: .value("Start", Double(point.id) - width),
                              xEnd: .value("End", Double(point.id) + width),
                              yStart: .value("Lower", gb(min(bytes, goal))),
                              yEnd: .value("Upper", gb(max(bytes, goal))))
                    .foregroundStyle(bytes < goal ? RoomTokens.Status.elevated : accent.fill)
            }
        }
        RuleMark(y: .value("Goal", gb(goal)))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle((latest?.freeBytes ?? goal) < goal ? RoomTokens.Status.elevated : accent.text)
    }

    private func changePlot(range nextRange: RoomOverviewHistoryRange, metric nextMetric: RoomOverviewHistoryMetric) {
        guard nextRange != range || nextMetric != metric else { return }
        let instant = ContinuousClock.now
        let calendar = Calendar.autoupdatingCurrent
        let source: [RoomOverviewHistoryTransition.Layer]
        if let transition {
            source = transition.layers(at: instant)
        } else {
            let old = RoomOverviewHistory(log: log, range: range, now: now, calendar: calendar)
            let plot = RoomOverviewHistoryPlot(history: old, range: range, metric: metric,
                domain: bounds(old), now: now, selected: hovering ?? keyboard)
            source = [.init(plot: plot, opacity: 1)]
        }
        let next = RoomOverviewHistory(log: log, range: nextRange, now: now, calendar: calendar)
        let target = RoomOverviewHistoryPlot(history: next, range: nextRange, metric: nextMetric,
            domain: bounds(next, range: nextRange, metric: nextMetric), now: now, selected: nil)
        transition = RoomOverviewHistoryTransition(source: source, target: target, morphs: motion.isFull, start: instant)
        range = nextRange
        metric = nextMetric
        hovering = nil
        keyboard = nil
    }

    @ViewBuilder private func notes(_ history: RoomOverviewHistory) -> some View {
        if let receipt = latestReceipt, let start = history.points.first?.bucket,
           (start...now).contains(receipt.lastChangedAt) {
            let date = receipt.lastChangedAt.formatted(.dateTime.weekday(.abbreviated))
            let caption = RoomMakeRoomCopy.headline(receipt, format: RoomFormat.gb)
            RoomMaskable("\(date): \(caption)")
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
        }
        if let growth, let goal, let latest = history.latest(for: .freeSpace)?.sample, latest.freeBytes < goal,
           let start = history.points.first?.bucket, (start...now).contains(growth.measuredAt), !hide.masksNow {
            let bytes = RoomFormat.gb(growth.bytes)
            Text("\(growth.name) grew by \(bytes) between maps.")
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
        }
        if range == .twelveWeeks, metric == .freeSpace {
            if let months = history.monthsUntilGoal(goal) {
                RoomMaskable("At this pace, free space could fall to your goal in about \(months) \(months == 1 ? "month" : "months").")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private func bounds(_ history: RoomOverviewHistory) -> ClosedRange<Double> {
        bounds(history, range: range, metric: metric)
    }

    private func bounds(_ history: RoomOverviewHistory, range: RoomOverviewHistoryRange,
                        metric: RoomOverviewHistoryMetric) -> ClosedRange<Double> {
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
        let amount = RoomFormat.gb(abs(value))
        switch metric {
        case .freeSpace: return "\(label): \(amount) free"
        case .change where value > 0: return "\(label): \(amount) used"
        case .change where value < 0: return "\(label): \(amount) more free"
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
            transition = nil
            hovering = nil
            keyboard = index
        }
    }

    private func gb(_ bytes: Int64) -> Double { Double(bytes) / RoomOverviewHistoryPlot.gigabyte }
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
            return AXDataPoint(x: Double(point.id), y: Double(value) / RoomOverviewHistoryPlot.gigabyte)
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
