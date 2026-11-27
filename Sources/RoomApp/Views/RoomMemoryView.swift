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

    @State private var showingDetail = false

    private var words: RoomMemoryWords {
        RoomMemoryWords.make(usedBytes: insights.memoryReport?.usedBytes, totalBytes: insights.memoryReport?.totalBytes,
                             pressureRaw: insights.memoryReport?.pressure.rawValue)
    }

    var body: some View {
        let now = Date()
        let words = words
        let level = insights.memoryReport.flatMap { RoomPressureLevel(memoryPressureRaw: $0.pressure.rawValue) }
        let series = range.series(in: insights.pressureHistory)
        let finding = pressureFinding(series: series, now: now)
        RoomScreenFrame(headline: words.headline, supporting: words.supporting,
                        note: "Sampled once a second while this is open", scrollsEvidence: true) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                RoomMemoryCurve(samples: insights.memorySamples.values)
                    .frame(height: RoomTokens.Memory2.curveHeight)
                if let report = insights.memoryReport {
                    RoomMemoryFigures(report: report)
                    // Suggestions come before any long list of processes (DESIGN.md).
                    if !report.recommendations.isEmpty { recommendations(report) }
                    #if ROOM_APP_STORE
                    storeMeasuredProcesses(report)
                    #else
                    applicationsSection
                    if !memoryActions.results.isEmpty { quitResults }
                    #endif
                }
                DisclosureGroup("More detail", isExpanded: $showingDetail) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
                        Text(finding).font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        RoomPressureTimeline(series: series, now: now, level: level, finding: finding, range: $range)
                        #if !ROOM_APP_STORE
                        if let report = insights.memoryReport { otherProcesses(report) }
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
                                if !report.issues.isEmpty {
                                    Button("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")") { showingIssues = true }
                                        .roomLink(accent)
                                }
                            }
                            .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                        }
                        if let status = insights.statusMessage {
                            Text(status).font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                        }
                    }
                    .padding(.top, RoomTokens.Space.row)
                }
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
            }
        } action: {
            EmptyView()
        }
        .roomDock(dockMain)
        .animation(animation, value: memoryActions.selectedCount)
        .task {
            memoryActions.refresh(from: insights.memoryReport)
            if insights.memoryReport == nil { insights.scanMemory() }
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

    private var dockMain: RoomDockAction {
        #if !ROOM_APP_STORE
        let count = memoryActions.selectedCount
        if count > 0 {
            return RoomDockAction(title: "Quit \(count) \(count == 1 ? "app" : "apps")…", enabled: !memoryActions.isApplying,
                                  hint: "Opens a review. Nothing is forced to close",
                                  identifier: "RoomMemoryQuit", stamp: memoryActions.selection.sorted().map(String.init).joined(separator: ",")) {
                quitReview = memoryActions.review()
            }
        }
        #endif
        return RoomDockAction(title: "Refresh", symbol: "arrow.clockwise", filled: false, enabled: !insights.isScanningMemory,
                              identifier: "RoomMemoryRefresh", perform: insights.scanMemory)
    }

    private func updateMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let visible = primary?.occlusionState.contains(.visible) ?? true
        insights.setMemoryActive(scenePhase == .active && visible)
    }

    #if ROOM_APP_STORE
    @ViewBuilder private func storeMeasuredProcesses(_ report: MemoryReport) -> some View {
        if !report.processes.isEmpty {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Text("Apps using the most").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
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
        }
    }
    #endif

    private func recommendations(_ report: MemoryReport) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            ForEach(report.recommendations) { recommendation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title).font(RoomTokens.Typography.bodyStrong)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                    Text(recommendation.detail)
                        .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }

    #if !ROOM_APP_STORE
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps using the most").font(RoomTokens.Typography.section)
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
                if memoryActions.selectedCount > 0 {
                    HStack(spacing: 12) {
                        Text("\(memoryActions.selectedCount) selected").font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                        Button("Clear") { memoryActions.clearSelection() }
                            .buttonStyle(.plain).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    }
                }
            }
            if let message = memoryActions.statusMessage {
                Text(message).font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func otherProcesses(_ report: MemoryReport) -> some View {
        let selectable = Set(memoryActions.applications.map(\.id))
        let other = report.processes.filter { !selectable.contains($0.id) }
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

    private func pressureFinding(series: RoomPressureSeries, now: Date) -> String {
        if insights.memoryReport?.pressure == .unknown {
            return "Room can't read memory pressure right now. Activity Monitor can."
        }
        return RoomPressureFinding.sentence(series, now: now, rangeName: "last " + range.title) {
            $0.formatted(date: .omitted, time: .shortened)
        }
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
