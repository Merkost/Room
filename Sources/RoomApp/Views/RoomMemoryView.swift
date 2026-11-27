import AppKit
import RoomCore
import SwiftUI

struct RoomMemoryView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("RoomMemoryRange") private var range = RoomMemoryRange.now
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var showingIssues = false
    @State private var sideBySide = true
    @State private var showingAllBackground = false
    #if !ROOM_APP_STORE
    @State private var quitReview: MemoryQuitReview?
    @State private var showingAllApps = false
    #endif

    var body: some View {
        let words = RoomMemoryWords.make(usedBytes: insights.memoryReport?.usedBytes,
                                         totalBytes: insights.memoryReport?.totalBytes,
                                         pressureRaw: insights.memoryReport?.pressure.rawValue)
        RoomScreenFrame(headline: words.headline, supporting: words.supporting,
                        note: "Sampled every 20 seconds while this is open", scrollsEvidence: true) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                history
                if let report = insights.memoryReport {
                    RoomMemoryFigures(report: report)
                    // Suggestions come before any long list of processes (DESIGN.md).
                    advice(report)
                    columns(report)
                    notes(report)
                }
                if let status = insights.statusMessage {
                    Text(status).font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width >= RoomTokens.Memory2.columnsBreak } action: { sideBySide = $0 }
        } action: {
            EmptyView()
        }
        .roomDock(dockMain)
        .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: memoryActions.selectedCount)
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
        #if ROOM_APP_STORE
        return RoomDockAction(title: "Refresh", symbol: "arrow.clockwise", filled: false, enabled: !insights.isScanningMemory,
                              identifier: "RoomMemoryRefresh", perform: insights.scanMemory)
        #else
        let count = memoryActions.selectedCount
        return RoomDockAction(title: count == 0 ? "Quit apps…" : "Quit \(count) \(count == 1 ? "app" : "apps")…",
                              enabled: count > 0 && !memoryActions.isApplying,
                              hint: count == 0 ? "Tick an app first" : "Opens a review. Nothing is forced to close",
                              identifier: "RoomMemoryQuit",
                              stamp: memoryActions.selection.sorted().map(String.init).joined(separator: ",")) {
            quitReview = memoryActions.review()
        }
        #endif
    }

    private func updateMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let visible = primary?.occlusionState.contains(.visible) ?? true
        insights.setMemoryActive(scenePhase == .active && visible)
    }

    private var history: some View {
        let samples = insights.memorySamples.samples
        let window = RoomMemoryPage.window(samples, range: range)
        return VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.row) {
                Picker("Time range", selection: $range) {
                    ForEach(RoomMemoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer(minLength: 0)
                Text(RoomMemoryPage.pressureSentence(window))
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
            RoomMemoryCurve(samples: samples, range: range)
                .frame(height: RoomTokens.Memory2.curveHeight)
        }
    }

    @ViewBuilder private func advice(_ report: MemoryReport) -> some View {
        let advice = RoomMemoryPage.advice(report.recommendations)
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                ForEach(advice) { recommendation in
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
    }

    @ViewBuilder private func columns(_ report: MemoryReport) -> some View {
        let layout = sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: RoomTokens.Memory2.columnsGap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: RoomTokens.Space.group))
        layout {
            #if ROOM_APP_STORE
            processList(title: "Using the most", trailing: "view only", processes: report.processes)
            #else
            applications.frame(maxWidth: .infinity, alignment: .topLeading)
            processList(title: "Background", trailing: "view only",
                        processes: RoomMemoryPage.background(report.processes, apps: Set(memoryActions.applications.map(\.id))))
            #endif
        }
    }

    private func processList(title: String, trailing: String, processes: [MemoryProcess]) -> some View {
        let limit = showingAllBackground ? RoomMemoryPage.expandedRows : RoomMemoryPage.visibleRows
        let expandable = min(processes.count, RoomMemoryPage.expandedRows) - RoomMemoryPage.visibleRows
        return VStack(alignment: .leading, spacing: 0) {
            RoomMemoryColumnHeader(title: title) {
                HStack(spacing: RoomTokens.Space.row) {
                    Text(trailing)
                    Button("Activity Monitor") { insights.openActivityMonitor() }.roomLink(accent)
                }
            }
            ForEach(Array(processes.prefix(limit))) { process in
                RoomMemoryProcessRow(pid: process.id, name: process.name, bytes: process.residentBytes,
                                     maximum: processes.first?.residentBytes ?? 0)
                    .accessibilityElement(children: .combine)
            }
            if processes.isEmpty {
                Text("No process sizes were measured.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .padding(.top, RoomTokens.Space.row)
            }
            if expandable > 0 {
                Button(showingAllBackground ? "Show fewer" : "\(expandable) more") { showingAllBackground.toggle() }
                    .roomLink(accent).font(RoomTokens.Typography.caption)
                    .padding(.top, RoomTokens.Space.tight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func notes(_ report: MemoryReport) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
            #if ROOM_APP_STORE
            Text("Sizes include shared pages, so they don’t add up.")
            #else
            Text("Sizes include shared pages, so they don’t add up. Apps count their main process only.")
            #endif
            Spacer(minLength: 0)
            if !report.issues.isEmpty {
                Button(report.issues.count == 1 ? "1 reading failed" : "\(report.issues.count) readings failed") {
                    showingIssues = true
                }
                .roomLink(accent)
            }
        }
        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
    }

    #if !ROOM_APP_STORE
    private var applications: some View {
        let apps = memoryActions.applications
        let expandable = apps.count - RoomMemoryPage.visibleRows
        // A ticked app stays on screen when the list folds back.
        let shown = apps.enumerated()
            .filter { showingAllApps || $0.offset < RoomMemoryPage.visibleRows || memoryActions.selection.contains($0.element.id) }
            .map(\.element)
        return VStack(alignment: .leading, spacing: 0) {
            RoomMemoryColumnHeader(title: "Apps") {
                if memoryActions.selectedCount > 0 {
                    HStack(spacing: RoomTokens.Space.row) {
                        Text("\(memoryActions.selectedCount) ticked")
                        Button("Clear") { memoryActions.clearSelection() }.roomLink(accent)
                    }
                } else {
                    Text("tick to quit")
                }
            }
            ForEach(shown) { application in
                let selected = memoryActions.selection.contains(application.id)
                Button { memoryActions.toggleSelection(id: application.id) } label: {
                    RoomMemoryProcessRow(pid: application.id, name: application.name, bytes: application.residentBytes,
                                         maximum: apps.first?.residentBytes ?? 0, selected: selected)
                }
                .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.group))
                .disabled(memoryActions.isApplying)
                .accessibilityLabel("\(selected ? "Deselect" : "Select") \(application.name)")
                .accessibilityValue(application.residentBytes.map(RoomFormat.memory) ?? "Not measured")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            if apps.isEmpty {
                Text("No apps to quit. System apps and Room stay protected.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .padding(.top, RoomTokens.Space.row)
            }
            if expandable > 0 {
                Button(showingAllApps ? "Show fewer" : "\(expandable) more") { showingAllApps.toggle() }
                    .roomLink(accent).font(RoomTokens.Typography.caption)
                    .padding(.top, RoomTokens.Space.tight)
            }
            if let message = memoryActions.statusMessage {
                Text(message).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RoomTokens.Space.row)
            }
            if !memoryActions.results.isEmpty { quitResults.padding(.top, RoomTokens.Space.row) }
        }
    }

    private var quitResults: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            ForEach(memoryActions.results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.status == .closed ? "checkmark.circle" : result.status == .pending ? "clock" : "info.circle")
                        .foregroundStyle(result.status == .closed ? RoomTokens.Status.normal : RoomTokens.Ink.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name).font(RoomTokens.Typography.bodyStrong)
                        Text(result.message).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    #endif
}
