import RoomCore
import SwiftUI

struct RoomMemoryView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    #endif
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingIssues = false
    #if !ROOM_APP_STORE
    @State private var quitReview: MemoryQuitReview?
    @State private var showingAllApps = false
    @State private var section: MemorySection = .apps
    #endif

    private var animation: Animation? {
        motionEnabled && !reduceMotion ? .smooth(duration: 0.25) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let report = insights.memoryReport {
                memorySummary(report)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memory overview").font(RoomType.heading(22))
                    Text(memoryIntroduction)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if insights.isScanningMemory {
                        ProgressView("Reading memory…").controlSize(.small)
                    } else {
                        Button("Scan memory") { insights.scanMemory() }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            }

            #if ROOM_APP_STORE
            if let report = insights.memoryReport {
                if !report.recommendations.isEmpty { recommendations(report) }
                storeMeasuredProcesses(report)
            }
            #else
            Picker("Memory view", selection: $section) {
                Text("Apps").tag(MemorySection.apps)
                Text("Agent work").tag(MemorySection.agentWork)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Memory view")
            .accessibilityIdentifier("RoomMemorySectionPicker")
            .frame(width: 270)
            .disabled(memoryActions.isApplying)

            if section == .apps {
                if let report = insights.memoryReport {
                    applicationsSection(report)
                    if !memoryActions.results.isEmpty { quitResults }
                    if !report.recommendations.isEmpty { recommendations(report) }
                }
            } else {
                RoomAgentWorkView(model: agentWork, memoryReport: insights.memoryReport)
            }
            #endif

            if let report = insights.memoryReport {
                HStack(alignment: .top, spacing: 20) {
                    #if ROOM_APP_STORE
                    Text("Current measurements describe pressure and workload. No RAM saving is assumed.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #else
                    if section == .apps {
                        Text("Resident memory includes shared pages. App rows show the main process only; helpers are not added.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                    #endif
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("Scanned \(report.scannedAt, style: .relative) ago").fixedSize()
                        if !report.issues.isEmpty {
                            Button("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")") { showingIssues = true }.buttonStyle(.plain)
                        }
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let status = insights.statusMessage {
                Text(status).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .animation(animation, value: insights.memoryReport?.usedBytes)
        .animation(animation, value: memoryActions.selectedCount)
        #if !ROOM_APP_STORE
        .animation(animation, value: section)
        #endif
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
                        .font(.system(size: 13))
                    }
                    Text("Resident memory can include shared pages. These values are not added as a system total.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }
            .font(.system(size: 14))
        }
    }
    #endif

    private func recommendations(_ report: MemoryReport) -> some View {
        DisclosureGroup("Suggestions (\(report.recommendations.count))") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(report.recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.title).font(.system(size: 14, weight: .medium))
                        Text(recommendation.detail)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
        }
        .font(.system(size: 14))
    }

    #if !ROOM_APP_STORE
    private func applicationsSection(_ report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps you can close").font(.system(size: 15, weight: .medium))
                Spacer()
                Button("Activity Monitor") { insights.openActivityMonitor() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if memoryActions.applications.isEmpty {
                Text("No eligible user apps are available. System apps and Room stay protected.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
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
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if memoryActions.selectedCount > 0 {
                        Text("\(memoryActions.selectedCount) selected").font(.system(size: 14)).foregroundStyle(.secondary)
                        Button("Clear") { memoryActions.clearSelection() }
                            .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
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
                                .font(.system(size: 13)).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Inspect \(process.name) in Activity Monitor")
                        }
                    }
                    .padding(.horizontal, 5).padding(.top, 5)
                }
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            if let message = memoryActions.statusMessage {
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var quitResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quit requests").font(.system(size: 14, weight: .medium))
            ForEach(memoryActions.results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.status == .closed ? "checkmark.circle" : result.status == .pending ? "clock" : "info.circle")
                        .foregroundStyle(result.status == .closed ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name).font(.system(size: 14, weight: .medium))
                        Text(result.message).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    #endif

    private func memorySummary(_ report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memory overview").font(RoomType.heading(22)).tracking(-0.4)
                    if countersUnavailable(report) {
                        Text("Unavailable").font(RoomType.figure(34))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            RoomByteMetric(bytes: report.usedBytes, maximumSize: 52, memory: true)
                                .fixedSize(horizontal: true, vertical: false)
                            Text("in use").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(RoomFormat.memoryBytes(report.totalBytes)) physical memory")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Memory pressure")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Label(pressureTitle(report), systemImage: "circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(pressureColor(report))
                }
                .frame(minWidth: 130, alignment: .leading)
                .padding(16)
                .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .glassEffect(reduceTransparency ? .identity : .regular,
                             in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if !countersUnavailable(report) {
                GeometryReader { geometry in
                    let total = Double(max(1, report.totalBytes))
                    let compressed = min(total, Double(max(0, report.compressedBytes)))
                    let used = min(total, Double(max(0, report.usedBytes)))
                    HStack(spacing: 0) {
                        Rectangle().fill(pressureColor(report).opacity(0.7))
                            .frame(width: geometry.size.width * max(0, used - compressed) / total)
                        Rectangle().fill(pressureColor(report).opacity(0.38))
                            .frame(width: geometry.size.width * min(used, compressed) / total)
                        Rectangle().fill(Color.primary.opacity(0.065))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                .accessibilityLabel("\(RoomFormat.memoryBytes(report.usedBytes)) in use, including \(RoomFormat.memoryBytes(report.compressedBytes)) compressed")

                HStack(alignment: .top, spacing: 24) {
                    memoryCounter("Available / reclaimable", bytes: report.availableBytes)
                    memoryCounter("Compressed", bytes: report.compressedBytes)
                    memoryCounter("Swap used", bytes: RoomMonitorPresentation.measuredSwap(report))
                        .foregroundStyle(pressureColor(report))
                }
            }
        }
    }

    private func memoryCounter(_ title: String, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bytes.map(RoomFormat.memoryBytes) ?? "Unavailable")
                .font(RoomType.figure(20)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func countersUnavailable(_ report: MemoryReport) -> Bool {
        report.totalBytes > 0 && report.usedBytes == 0 && report.availableBytes == 0
    }

    private func pressureTitle(_ report: MemoryReport) -> String {
        switch report.pressure { case .normal: "Normal"; case .elevated: "Elevated"; case .critical: "High"; case .unknown: "Unavailable" }
    }
    private func pressureColor(_ report: MemoryReport) -> Color {
        switch report.pressure { case .normal: .green; case .elevated: .orange; case .critical: .red; case .unknown: .secondary }
    }
}

#if !ROOM_APP_STORE
private enum MemorySection: Hashable { case apps, agentWork }

private struct MemoryApplicationRow: View {
    let application: MemoryApplication
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
                Text(application.name).font(.system(size: 14)).lineLimit(1)
                Spacer(minLength: 10)
                if let resident = application.residentBytes {
                    Text("≈ \(RoomFormat.memoryBytes(resident))").font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("Not in this sample").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? Color.accentColor.opacity(0.065) : Color.clear,
                in: RoundedRectangle(cornerRadius: 13))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain).disabled(disabled)
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
                    Text("A little breathing room.").font(RoomType.heading(25))
                    Text("Review \(review.count) \(review.count == 1 ? "app" : "apps") before requesting a normal quit.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "power.circle").font(.system(size: 31, weight: .light)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(review.applications) { application in
                        HStack(spacing: 12) {
                            if let icon = application.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                            Text(application.name).font(.system(size: 14))
                            Spacer()
                            if let resident = application.residentBytes {
                                Text("≈ \(RoomFormat.memoryBytes(resident))").font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 230)
            VStack(alignment: .leading, spacing: 8) {
                if review.residentBytes > 0 {
                    Text("About \(RoomFormat.memoryBytes(review.residentBytes)) resident in this sample")
                        .font(.system(size: 14, weight: .medium))
                }
                if review.unmeasuredCount > 0 {
                    Text("\(review.unmeasuredCount) \(review.unmeasuredCount == 1 ? "app is" : "apps are") outside the current process sample.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text("Apps may ask you to save unsaved work or cancel. Nothing is forced to close. Resident sizes include shared pages and exclude helpers; they are not a promise of freed RAM.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
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
