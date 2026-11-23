import AppKit
import RoomCore
import SwiftUI

struct RoomMemoryView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("RoomMemoryRange") private var range = RoomMemoryRange.day
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var showingIssues = false
    #if !ROOM_APP_STORE
    @State private var quitReview: MemoryQuitReview?
    @State private var showingAllApps = false
    #endif

    private var animation: Animation? {
        motion.animation(RoomTokens.Motion.standard, fallback: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
            HStack(spacing: RoomTokens.Space.group) {
                Text("Memory pressure, compression, and swap on your Mac.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { insights.scanMemory() } label: {
                    Label(insights.isScanningMemory ? "Reading…" : insights.memoryReport == nil ? "Scan memory" : "Refresh",
                          systemImage: "arrow.clockwise")
                }
                .roomSecondary()
                .fixedSize()
                .disabled(insights.isScanningMemory)
                .accessibilityIdentifier("RoomMemoryRefreshButton")
            }

            let now = Date()
            let level = insights.memoryReport.flatMap { RoomPressureLevel(memoryPressureRaw: $0.pressure.rawValue) }
            let series = range.series(in: insights.pressureHistory)
            let finding = pressureFinding(series: series, now: now)
            pressureOverview(level: level, finding: finding)
            // "In use" first, then the history: the current answer before the record of how it got here.
            if let report = insights.memoryReport, countersAvailable(report) {
                memorySummary(report, now: now)
                    .transition(.opacity)
            }
            RoomPressureTimeline(series: series, now: now, level: level, finding: finding, range: $range)
            #if ROOM_APP_STORE
            if let report = insights.memoryReport {
                if !report.recommendations.isEmpty { recommendations(report) }
                storeMeasuredProcesses(report)
            }
            #else
            if let report = insights.memoryReport, !report.recommendations.isEmpty { recommendations(report) }

            if let report = insights.memoryReport {
                applicationsSection(report)
                if !memoryActions.results.isEmpty { quitResults }
            }
            #endif

            if let report = insights.memoryReport {
                HStack(alignment: .top, spacing: 20) {
                    #if ROOM_APP_STORE
                    Text("Current measurements describe pressure and workload. No RAM saving is assumed.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #else
                    Text("Resident memory includes shared pages. App rows show the main process only; helpers are not added.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #endif
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("Scanned \(report.scannedAt, style: .relative) ago").fixedSize()
                        if !report.issues.isEmpty {
                            Button("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")") { showingIssues = true }.buttonStyle(.plain)
                        }
                    }
                }
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }
            if let status = insights.statusMessage {
                Text(status).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
            }
        }
        .animation(animation, value: insights.memoryReport?.usedBytes)
        .animation(animation, value: memoryActions.selectedCount)
        .task {
            memoryActions.refresh(from: insights.memoryReport)

        }
        .onChange(of: scenePhase, initial: true) { _, _ in updateMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == RoomApplicationDelegate.primaryWindowID else { return }
            updateMonitoring(in: window)
        }
        .onDisappear { insights.setMemoryActive(false) }
        .onChange(of: insights.memoryReport?.id) { _, _ in memoryActions.refresh(from: insights.memoryReport) }
        .sheet(isPresented: $showingIssues) { RoomScanIssuesSheet(issues: insights.memoryReport?.issues ?? []) }
        #if !ROOM_APP_STORE
        .sheet(item: $quitReview) { review in
            MemoryQuitReviewSheet(review: review, isApplying: memoryActions.isApplying,
                cancel: { quitReview = nil }, request: {
                    Task {
                        await memoryActions.apply(review: review)
                        quitReview = nil
                        insights.scanMemory()
                    }
                })
            .interactiveDismissDisabled(memoryActions.isApplying)
        }
        #endif
    }

    private func updateMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let visible = primary?.occlusionState.contains(.visible) ?? true
        insights.setMemoryActive(scenePhase == .active && visible)
    }

    #if ROOM_APP_STORE
    @ViewBuilder private func storeMeasuredProcesses(_ report: MemoryReport) -> some View {
        if !report.processes.isEmpty {
            DisclosureGroup("Apps using the most") {
                VStack(spacing: 12) {
                    ForEach(Array(report.processes.prefix(8))) { process in
                        HStack(spacing: 16) {
                            Text(process.name).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(RoomFormat.memory(process.residentBytes)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(RoomTokens.Typography.body)
                    }
                    Text("Resident memory can include shared pages. These values are not added as a system total.")
                        .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }
            .font(RoomTokens.Typography.body)
        }
    }
    #endif

    private func recommendations(_ report: MemoryReport) -> some View {
        DisclosureGroup("Suggestions (\(report.recommendations.count))") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(report.recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.title).font(RoomTokens.Typography.bodyStrong)
                        Text(recommendation.detail)
                            .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
        }
        .font(RoomTokens.Typography.body)
    }

    #if !ROOM_APP_STORE
    private func applicationsSection(_ report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps using the most").font(RoomTokens.Typography.title)
                Spacer()
                Button("Activity Monitor") { insights.openActivityMonitor() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if memoryActions.applications.isEmpty {
                Text("No eligible user apps are available. System apps and Room stay protected.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(memoryActions.applications.prefix(showingAllApps ? .max : 7))) { application in
                        MemoryApplicationRow(application: application,
                            maximumBytes: memoryActions.applications.first?.residentBytes ?? 0,
                            selected: memoryActions.selection.contains(application.id), disabled: memoryActions.isApplying,
                            toggle: { memoryActions.toggleSelection(id: application.id) })
                    }
                }
                if memoryActions.applications.count > 7 {
                    Button(showingAllApps ? "Show fewer apps" : "Show all \(memoryActions.applications.count) apps") {
                        showingAllApps.toggle()
                    }
                    .buttonStyle(.plain).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if memoryActions.selectedCount > 0 {
                        Text("\(memoryActions.selectedCount) selected").font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                        Button("Clear") { memoryActions.clearSelection() }
                            .buttonStyle(.plain).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Quit apps…") {
                        quitReview = memoryActions.review()
                    }
                    .buttonStyle(.glassProminent).controlSize(.regular)
                    .disabled(memoryActions.selectedCount == 0 || memoryActions.isApplying)
                }
                .padding(.top, 5)
            }
            let selectablePIDs = Set(memoryActions.applications.map(\.id))
            let other = report.processes.filter { !selectablePIDs.contains($0.id) }
            if !other.isEmpty {
                DisclosureGroup("Other measured processes") {
                    VStack(spacing: 3) {
                        ForEach(Array(other.prefix(6))) { process in
                            Button { insights.openActivityMonitor() } label: {
                                HStack(spacing: 12) {
                                    Text(process.name).lineLimit(1)
                                    Spacer()
                                    Text(RoomFormat.memory(process.residentBytes)).monospacedDigit().foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                                }
                                .font(RoomTokens.Typography.body).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Inspect \(process.name) in Activity Monitor")
                        }
                    }
                    .padding(.horizontal, 5).padding(.top, 5)
                }
                .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            if let message = memoryActions.statusMessage {
                Text(message).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var quitResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quit requests").font(RoomTokens.Typography.bodyStrong)
            ForEach(memoryActions.results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.status == .closed ? "checkmark.circle" : result.status == .pending ? "clock" : "info.circle")
                        .foregroundStyle(result.status == .closed ? RoomTokens.Status.normal : RoomTokens.Ink.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name).font(RoomTokens.Typography.bodyStrong)
                        Text(result.message).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    #endif

    private func pressureOverview(level: RoomPressureLevel?, finding: String) -> some View {
        HStack(alignment: .top, spacing: 25) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Memory pressure").font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    RoomPocketScrubber(level: level, size: 34)
                        .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: level)
                    Text(level?.word ?? RoomFormat.notMeasured).font(RoomTokens.Typography.figure)
                        .foregroundStyle(RoomPocketScrubber.color(level))
                }.accessibilityElement(children: .combine)
                Text(finding)
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if insights.memoryReport?.pressure == .unknown {
                    Button("Open Activity Monitor") { insights.openActivityMonitor() }
                        .roomLink(accent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("What is memory pressure?").font(RoomTokens.Typography.section)
                Text("It shows how hard macOS is working to meet memory demand. A large amount of memory in use can be normal.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(width: 225, alignment: .leading).padding(16)
                .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
        }
    }

    private func pressureFinding(series: RoomPressureSeries, now: Date) -> String {
        if insights.memoryReport?.pressure == .unknown {
            return "Room can't read memory pressure right now. Activity Monitor can."
        }
        return RoomPressureFinding.sentence(series, now: now, rangeName: "last " + range.title) {
            $0.formatted(date: .omitted, time: .shortened)
        }
    }

    private func memorySummary(_ report: MemoryReport, now: Date) -> some View {
        let samples = insights.memorySamples.samples
        let average = RoomMemoryInUse.average(samples.map { ($0.at, $0.bytes) }, now: now)
        let window = samples.filter { $0.at <= now && now.timeIntervalSince($0.at) <= 3_600 }.map(\.bytes)
        let compressed = max(0, min(report.usedBytes, report.compressedBytes))
        let appAndWired = max(0, report.usedBytes - compressed)
        let wired = max(0, min(appAndWired, report.wiredBytes ?? 0))
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(average.map { "In use · \($0.caption)" } ?? "In use")
                        .font(RoomTokens.Typography.title)
                    HStack(spacing: 20) {
                        memoryCounter("Current", bytes: report.usedBytes, font: RoomTokens.Typography.figure, hero: true)
                        memoryCounter("Average", bytes: average?.bytes, font: RoomTokens.Typography.figure)
                    }
                    Text("of \(RoomFormat.memory(report.totalBytes))")
                        .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let average {
                    VStack(alignment: .trailing, spacing: 5) {
                        usageSparkline(window, average: average.bytes).frame(width: 150, height: 40)
                        Text("dashed: average").font(RoomTokens.Typography.micro).foregroundStyle(.secondary)
                    }.accessibilityHidden(true)
                }
            }
            Text("Where it goes").font(RoomTokens.Typography.title)
            GeometryReader { geometry in
                let scale = geometry.size.width / Double(max(1, report.totalBytes))
                HStack(spacing: 0) {
                    if report.wiredBytes != nil {
                        usageSegment("App", appAndWired - wired, color: RoomTokens.Surface.used, scale: scale)
                        usageSegment("Wired", wired, color: RoomTokens.Ink.secondary, scale: scale)
                    } else {
                        usageSegment("App and wired", appAndWired, color: RoomTokens.Surface.used, scale: scale)
                    }
                    usageSegment("Compressed", compressed, color: RoomTokens.Surface.line2, scale: scale)
                    usageSegment("Available", max(0, report.availableBytes), color: RoomTokens.Surface.track, scale: scale)
                }.clipShape(.capsule)
            }.frame(height: 12)
            HStack(alignment: .top, spacing: 18) {
                memoryCounter("App and wired", bytes: appAndWired)
                memoryCounter("Compressed", bytes: compressed)
                memoryCounter("Swap used", bytes: RoomMonitorPresentation.measuredSwap(report))
            }
        }
    }

    private func usageSegment(_ title: String, _ bytes: Int64, color: Color, scale: Double) -> some View {
        let label = "\(title) · \(RoomFormat.memory(bytes))"
        return Rectangle().fill(color)
            .frame(width: Double(bytes) * scale)
            .focusable(bytes > 0)
            .accessibilityLabel(label)
            .help(label)
    }

    private func usageSparkline(_ values: [Int64], average: Int64) -> some View {
        Canvas { context, size in
            let points = RoomSparkline.points(values + [average], width: size.width, height: size.height)
            guard let averagePoint = points.last, !values.isEmpty else { return }
            var mean = Path()
            mean.move(to: CGPoint(x: 0, y: averagePoint.y))
            mean.addLine(to: CGPoint(x: size.width, y: averagePoint.y))
            context.stroke(mean, with: .color(RoomTokens.Ink.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var line = Path()
            for (index, point) in points.dropLast().enumerated() {
                let x = size.width * Double(index) / Double(max(1, values.count - 1))
                let position = CGPoint(x: x, y: point.y)
                if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
            }
            context.stroke(line, with: .color(accent.fill), lineWidth: 1.5)
        }
    }

    private func memoryCounter(_ title: String, bytes: Int64?, font: Font = RoomTokens.Typography.counter,
                               hero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            Text(bytes.map { RoomFormat.memory($0, hero: hero) } ?? RoomFormat.notMeasured)
                .font(bytes == nil ? RoomTokens.Typography.body : font).monospacedDigit()
                .foregroundStyle(bytes == nil ? RoomTokens.Ink.secondary : RoomTokens.Ink.graphite)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.accessibilityElement(children: .combine)
    }

    private func countersAvailable(_ report: MemoryReport) -> Bool {
        report.totalBytes > 0 && (report.usedBytes > 0 || report.availableBytes > 0)
    }
}

private struct RoomMemoryProcessBar: View {
    let bytes: Int64
    let maximum: Int64

    var body: some View {
        Capsule().fill(RoomTokens.Surface.used)
            .frame(width: 60 * Double(max(0, min(bytes, maximum))) / Double(max(1, maximum)), height: 4)
            .frame(width: 60, alignment: .leading)
            .accessibilityHidden(true)
    }
}

#if !ROOM_APP_STORE
private struct MemoryApplicationRow: View {
    let application: MemoryApplication
    let maximumBytes: Int64
    let selected: Bool
    let disabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 13) {
                if let icon = application.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 29, height: 29)
                } else {
                    Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                        .frame(width: 29, height: 29)
                }
                Text(application.name).font(RoomTokens.Typography.body).lineLimit(1)
                Spacer(minLength: 10)
                if let resident = application.residentBytes {
                    Text("≈ \(RoomFormat.memory(resident))").font(RoomTokens.Typography.body).monospacedDigit().foregroundStyle(.secondary)
                    RoomMemoryProcessBar(bytes: resident, maximum: maximumBytes)
                } else {
                    Text("Not in this sample").font(RoomTokens.Typography.caption).foregroundStyle(.tertiary)
                }
                RoomChangingSymbol(name: selected ? "checkmark.circle.fill" : "circle",
                                   color: selected ? .accentColor : .secondary.opacity(0.55))
                    .font(.system(size: 18))
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? Color.accentColor.opacity(0.065) : Color.clear,
                in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
            .contentShape(RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.group)).disabled(disabled)
        .accessibilityLabel("\(selected ? "Deselect" : "Select") \(application.name)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct MemoryQuitReviewSheet: View {
    let review: MemoryQuitReview
    let isApplying: Bool
    let cancel: () -> Void
    let request: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("A little breathing room.").font(RoomType.heading(24))
                    Text("Review \(review.count) \(review.count == 1 ? "app" : "apps") before requesting a normal quit.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "power.circle").font(.system(size: 31, weight: .light)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(review.applications) { application in
                        HStack(spacing: 12) {
                            if let icon = application.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                            Text(application.name).font(RoomTokens.Typography.body)
                            Spacer()
                            if let resident = application.residentBytes {
                                Text("≈ \(RoomFormat.memory(resident))").font(RoomTokens.Typography.body).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 230)
            VStack(alignment: .leading, spacing: 8) {
                if review.residentBytes > 0 {
                    Text("About \(RoomFormat.memory(review.residentBytes)) resident in this sample")
                        .font(RoomTokens.Typography.bodyStrong)
                }
                if review.unmeasuredCount > 0 {
                    Text("\(review.unmeasuredCount) \(review.unmeasuredCount == 1 ? "app is" : "apps are") outside the current process sample.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                }
                Text("Apps may ask you to save unsaved work or cancel. Nothing is forced to close. Resident sizes include shared pages and exclude helpers; they are not a promise of freed RAM.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if isApplying { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).disabled(isApplying)
                Button("Request Quit", action: request)
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(isApplying)
            }
        }
        .padding(28).frame(width: 500)
    }
}

#endif
