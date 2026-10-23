import Charts
import RoomCore
import SwiftUI

struct RoomMemoryView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    let onShowAgentWork: () -> Void
    #endif
    @State private var showingIssues = false
    #if !ROOM_APP_STORE
    @State private var quitReview: MemoryQuitReview?
    @State private var showingAllApps = false
    #endif

    var motion = RoomMotionPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoomPageHeader(title: "Memory", subtitle: memoryIntroduction) {
                Button { insights.scanMemory() } label: {
                    Label(insights.isScanningMemory ? "Reading…" : insights.memoryReport == nil ? "Scan memory" : "Refresh",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass).controlSize(.large)
                .disabled(insights.isScanningMemory)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("RoomMemoryRefreshButton")
            }

            if let report = insights.memoryReport {
                memorySummary(report)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if insights.isScanningMemory {
                        ProgressView("Reading memory…").controlSize(.small)
                    } else {
                        Text("Ready to read your Mac’s current memory.")
                            .font(RoomTypography.body).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }

            if let report = insights.memoryReport {
                recommendations(report)
                memoryHistory
                #if ROOM_APP_STORE
                storeMeasuredProcesses(report)
                #else
                applicationsSection(report)
                if !memoryActions.results.isEmpty { quitResults }
                RoomSectionHeader(title: "Agent work", detail: "Worktrees and observed processes") {
                    Button("Review worktrees", action: onShowAgentWork)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("RoomMemoryAgentWorkLink")
                }
                if let report = agentWork.report {
                    Text("\(report.items.count) worktrees in the latest review. Process links are observations, not proof that work is finished.")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                #endif
            }

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
                .font(RoomTypography.caption).foregroundStyle(.secondary)
            }
            if let status = insights.memoryStatusMessage {
                RoomStatusNotice(message: status)
            }
        }
        .animation(motion.selection, value: memoryActions.selectedCount)
        .task {
            memoryActions.refresh(from: insights.memoryReport)
            if insights.memoryReport == nil && !insights.isScanningMemory { insights.scanMemory() }
        }
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

    private var memoryIntroduction: String {
        #if ROOM_APP_STORE
        "Memory pressure, compression, and swap on your Mac."
        #else
        "Memory pressure, apps, and agent work on your Mac."
        #endif
    }

    #if ROOM_APP_STORE
    @ViewBuilder private func storeMeasuredProcesses(_ report: MemoryReport) -> some View {
        if !report.processes.isEmpty {
            DisclosureGroup("Measured processes") {
                VStack(spacing: 12) {
                    ForEach(Array(report.processes.prefix(8))) { process in
                        HStack(spacing: 16) {
                            Text(process.name).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(RoomFormat.memoryBytes(process.residentBytes)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(RoomTypography.body)
                    }
                    Text("Resident memory can include shared pages. These values are not added as a system total.")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }
            .font(RoomTypography.body)
        }
    }
    #endif

    @ViewBuilder private func recommendations(_ report: MemoryReport) -> some View {
        let needsAttention = report.pressure == .elevated || report.pressure == .critical
        if needsAttention, let first = report.recommendations.first {
            RoomStatusNotice(title: first.title, message: first.detail, tone: .warning)
            if report.recommendations.count > 1 {
                DisclosureGroup("More suggestions (\(report.recommendations.count - 1))") {
                    recommendationRows(Array(report.recommendations.dropFirst()))
                }.font(RoomTypography.bodyEmphasis)
            }
        } else if report.pressure == .normal {
            RoomStatusNotice(message: "Memory pressure is normal. No action is needed.", systemImage: "checkmark.circle")
        } else if !report.recommendations.isEmpty {
            DisclosureGroup("Suggestions (\(report.recommendations.count))") {
                recommendationRows(report.recommendations)
            }.font(RoomTypography.bodyEmphasis)
        }
    }

    private func recommendationRows(_ recommendations: [MemoryRecommendation]) -> some View {
        LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
            ForEach(recommendations) { recommendation in
                RoomStatusNotice(title: recommendation.title, message: recommendation.detail)
            }
        }.padding(.top, RoomSpace.compact)
    }

    private var memoryHistory: some View {
        RoomContentGroup {
            RoomSectionHeader(title: "Recent memory", detail: "\(insights.memoryHistory.count) actual readings")
            if insights.memoryHistory.isEmpty {
                RoomStatusNotice(message: "A successful memory reading starts the history.")
            } else {
                Chart(insights.memoryHistory) { sample in
                    let percentage = Double(sample.usedBytes) / Double(max(1, sample.totalBytes)) * 100
                    if insights.memoryHistory.count == 1 {
                        PointMark(x: .value("Time", sample.scannedAt), y: .value("Physical memory in use (%)", percentage))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        LineMark(x: .value("Time", sample.scannedAt), y: .value("Physical memory in use (%)", percentage))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.linear)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percentage = value.as(Double.self) {
                                Text(percentage / 100, format: .percent.precision(.fractionLength(0)))
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: .dateTime.hour().minute()) } }
                .frame(height: 120)
                .accessibilityLabel("Physical memory in use, as a percentage, over the latest \(insights.memoryHistory.count) actual readings")
                if insights.memoryHistory.count == 1 {
                    Text("One reading. Refresh or leave the monitor running to build a history.")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    #if !ROOM_APP_STORE
    private func applicationsSection(_ report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RoomSectionHeader(title: "Apps you can close") {
                Button("Activity Monitor") { insights.openActivityMonitor() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if memoryActions.applications.isEmpty {
                Text("No eligible user apps are available. System apps and Room stay protected.")
                    .font(RoomTypography.body).foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(memoryActions.applications.prefix(showingAllApps ? .max : 7))) { application in
                        MemoryApplicationRow(application: application,
                            selected: memoryActions.selection.contains(application.id), disabled: memoryActions.isApplying,
                            toggle: { memoryActions.toggleSelection(id: application.id) })
                    }
                }
                if memoryActions.applications.count > 7 {
                    Button(showingAllApps ? "Show fewer apps" : "Show all \(memoryActions.applications.count) apps") {
                        showingAllApps.toggle()
                    }
                    .buttonStyle(.plain).font(RoomTypography.body).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if memoryActions.selectedCount > 0 {
                        Text("\(memoryActions.selectedCount) selected").font(RoomTypography.body).foregroundStyle(.secondary)
                        Button("Clear") { memoryActions.clearSelection() }
                            .buttonStyle(.plain).font(RoomTypography.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(memoryActions.selectedCount > 0 ? "Review \(memoryActions.selectedCount) \(memoryActions.selectedCount == 1 ? "app" : "apps")" : "Review apps") {
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
                                    Text(RoomFormat.memoryBytes(process.residentBytes)).monospacedDigit().foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                                }
                                .font(RoomTypography.body).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open Activity Monitor to review processes")
                            .accessibilityLabel("Open Activity Monitor to review processes. \(process.name), \(RoomFormat.memoryBytes(process.residentBytes)) resident memory")
                        }
                    }
                    .padding(.horizontal, 5).padding(.top, 5)
                }
                .font(RoomTypography.body).foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            if let message = memoryActions.statusMessage { RoomStatusNotice(message: message) }
        }
    }

    private var quitResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quit requests").font(RoomTypography.bodyEmphasis)
            ForEach(memoryActions.results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.status == .closed ? "checkmark.circle" : result.status == .pending ? "clock" : "info.circle")
                        .foregroundStyle(result.status == .closed ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name).font(RoomTypography.bodyEmphasis)
                        Text(result.message).font(RoomTypography.body).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    #endif

    private func memorySummary(_ report: MemoryReport) -> some View {
        RoomContentGroup(spacing: 18) {
            HStack(alignment: .center, spacing: RoomSpace.section) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In use").font(RoomTypography.bodyEmphasis).foregroundStyle(.secondary)
                    if countersUnavailable(report) {
                        Text("Unavailable").font(RoomType.figure(34))
                    } else {
                        RoomByteMetric(bytes: report.usedBytes, maximumSize: 40, memory: true)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text("\(RoomFormat.memoryBytes(report.totalBytes)) physical memory")
                        .font(RoomTypography.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Memory pressure").font(RoomTypography.caption).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Circle().fill(pressureColor(report)).frame(width: 7, height: 7)
                        Text(pressureTitle(report)).font(RoomTypography.bodyEmphasis)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
            }

            if !countersUnavailable(report) {
                let total = Double(max(1, report.totalBytes))
                let used = min(total, Double(max(0, report.usedBytes)))
                let compressed = min(used, Double(max(0, report.compressedBytes)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.065))
                    Rectangle().fill(pressureColor(report).opacity(0.38))
                        .scaleEffect(x: used / total, y: 1, anchor: .leading)
                    Rectangle().fill(pressureColor(report).opacity(0.7))
                        .scaleEffect(x: max(0, used - compressed) / total, y: 1, anchor: .leading)
                }
                .clipShape(Capsule())
                .frame(height: 10)
                .animation(motion.measurement, value: report.usedBytes)
                .accessibilityLabel("\(RoomFormat.memoryBytes(report.usedBytes)) in use, including \(RoomFormat.memoryBytes(report.compressedBytes)) compressed")

                HStack(alignment: .top, spacing: 24) {
                    memoryCounter("Available / reclaimable", bytes: report.availableBytes)
                    memoryCounter("Compressed", bytes: report.compressedBytes)
                    memoryCounter("Swap used", bytes: RoomMonitorPresentation.measuredSwap(report))
                }
            }
        }
    }

    private func memoryCounter(_ title: String, bytes: Int64?) -> some View {
        RoomMetric(label: title, bytes: bytes, memory: true, maximumSize: 20)
    }

    private func countersUnavailable(_ report: MemoryReport) -> Bool {
        report.totalBytes <= 0 || (report.usedBytes == 0 && report.availableBytes == 0)
    }

    private func pressureTitle(_ report: MemoryReport) -> String {
        RoomPressureTone(report.pressure).title
    }
    private func pressureColor(_ report: MemoryReport) -> Color {
        RoomPressureTone(report.pressure).color
    }
}

#if !ROOM_APP_STORE
private struct MemoryApplicationRow: View {
    let application: MemoryApplication
    let selected: Bool
    let disabled: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: RoomSpace.compact) {
            RoomSelectionCheckbox(state: selected ? .on : .off, label: "Select \(application.name)", isEnabled: !disabled, action: toggle)
                .frame(width: 18)
                .accessibilityIdentifier("RoomMemorySelect-\(application.id)")
            if let icon = application.icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 29, height: 29).accessibilityHidden(true)
            } else {
                Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                    .frame(width: 29, height: 29).accessibilityHidden(true)
            }
            Button(action: toggle) {
                HStack(spacing: RoomSpace.compact) {
                    Text(application.name).font(RoomTypography.body).lineLimit(1)
                    Spacer(minLength: 10)
                    if let resident = application.residentBytes {
                        Text("≈ \(RoomFormat.memoryBytes(resident))").font(RoomTypography.body).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Text("Not in this sample").font(RoomTypography.caption).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel("\(selected ? "Deselect" : "Select") \(application.name)")
        }
        .padding(.horizontal, RoomSpace.compact).padding(.vertical, 8)
        .background(selected ? RoomSurface.selection : Color.clear, in: RoundedRectangle(cornerRadius: RoomRadius.row))
        .accessibilityElement(children: .contain)
    }
}

private struct MemoryQuitReviewSheet: View {
    let review: MemoryQuitReview
    let isApplying: Bool
    let cancel: () -> Void
    let request: () -> Void

    var body: some View {
        RoomSheetLayout(title: "Review app quit", subtitle: "Review \(review.count) \(review.count == 1 ? "app" : "apps") before requesting a normal quit.", width: 560) {
            LazyVStack(spacing: RoomSpace.standard) {
                ForEach(review.applications) { application in
                    HStack(spacing: RoomSpace.compact) {
                        if let icon = application.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                        Text(application.name).font(RoomTypography.bodyEmphasis)
                        Spacer()
                        if let resident = application.residentBytes {
                            Text("≈ \(RoomFormat.memoryBytes(resident))").font(RoomTypography.body).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if review.residentBytes > 0 {
                Text("About \(RoomFormat.memoryBytes(review.residentBytes)) resident in this sample")
                    .font(RoomTypography.bodyEmphasis)
            }
            if review.unmeasuredCount > 0 {
                RoomStatusNotice(message: "\(review.unmeasuredCount) \(review.unmeasuredCount == 1 ? "app is" : "apps are") outside the current process sample.")
            }
            RoomStatusNotice(message: "Apps may ask you to save unsaved work or cancel. Nothing is forced to close. Resident sizes include shared pages and exclude helpers; they are not a promise of freed RAM.", systemImage: "info.circle")
        } actions: {
            if isApplying { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).disabled(isApplying)
            Button("Request Quit", action: request)
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(isApplying)
        }
    }
}

#endif
