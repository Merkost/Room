import AppKit
import SwiftUI

struct RoomRootView: View {
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    #endif
    @AppStorage("RoomOnboardingVersion") private var onboardingVersion = 0
    @AppStorage("RoomAppearance") private var appearance = "system"
    @State private var developer = RoomDeveloperModel()
    @State private var destination = RoomDestination.clean
    @State private var sheet: RoomSheet?
    @State private var expanded = false
    @State private var category: RoomCategory?
    @State private var sourceFilter: RoomSourceFilter = .all
    @State private var query = ""
    @State private var requestedReviewPath: String?
    var motion = RoomMotionPolicy()

    private var animate: Animation? { motion.selection }
    private var selectedCount: Int { model.sources.filter { model.selection.contains($0.id) && $0.isAvailable }.count }
    private var matchingSources: [RoomSource] {
        model.sources.filter { source in
            (category == nil || source.category == category) &&
            (sourceFilter == .all || (sourceFilter == .clearable ? source.isAvailable :
                source.bytes > source.eligibleBytes || !source.heldReasons.isEmpty || source.blockedReason != nil || source.isPartial)) &&
            (query.isEmpty || (source.name + " " + source.subtitle + " " + source.path).localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            if lhs.eligibleBytes != rhs.eligibleBytes { return lhs.eligibleBytes > rhs.eligibleBytes }
            return lhs.bytes > rhs.bytes
        }
    }
    private var visibleSources: [RoomSource] {
        expanded || category != nil || sourceFilter != .all || !query.isEmpty
            ? matchingSources : Array(matchingSources.prefix(8))
    }
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    private func refreshCurrentView() {
        switch destination {
        case .clean: if model.isScanning { model.cancelScan() } else { model.scan() }
        case .memory: insights.scanMemory()
        case .disk:
            if insights.isScanningDisk { insights.cancelDiskScan() }
            else if let url = insights.diskURL { insights.scanDisk(url: url) }
        case .developer: if developer.isScanning { developer.stop() } else { developer.scan() }
        case .activity: break
        #if !ROOM_APP_STORE
        case .agentWork: if agentWork.isScanning || agentWork.verifyingID != nil { agentWork.stop() } else { agentWork.scan() }
        #endif
        }
    }

    var body: some View {
        presentedWorkspace
            .task { await prepareInitialPresentation() }
            .onChange(of: developer.accessRevision) { _, _ in developer.accessChanged() }
            .onChange(of: model.configurationRevision, initial: true) { _, _ in
                insights.updateCacheConfiguration(model.inspectionConfiguration)
            }
            .onChange(of: insights.requestedCleanPath) { _, path in handleCleanReviewRequest(path) }
            .onChange(of: model.lastScanned) { _, date in resolvePendingCleanReview(scannedAt: date) }
            #if ROOM_APP_STORE
            .onChange(of: model.storeAccessRevision) { _, _ in model.storeAccessChanged() }
            #endif
            .onChange(of: insights.requestedDestination, initial: true) { _, requested in
                handleInsightDestination(requested)
            }
    }

    private var presentedWorkspace: some View {
        workspace
            .animation(animate, value: destination)
            .animation(animate, value: expanded)
            .animation(animate, value: category)
            .sheet(item: $sheet) { selected in sheetContent(for: selected) }
            .alert("Room couldn’t complete that", isPresented: isShowingError) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private var workspace: some View {
        ZStack {
            RoomAmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { pageContent }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            // Each destination opens at its heading instead of inheriting another
            // task's long history or process-list scroll offset.
            .id(destination)
        }
        .frame(minWidth: 800, minHeight: 650)
        .preferredColorScheme(colorScheme)
        .toolbar { toolbarContent }
    }

    @ViewBuilder private var pageContent: some View {
        switch destination {
        case .clean:
            overview.transition(motion.pageTransition)
        case .memory:
            #if ROOM_APP_STORE
            RoomMemoryView(insights: insights, memoryActions: memoryActions)
                .transition(motion.pageTransition)
            #else
            RoomMemoryView(insights: insights, memoryActions: memoryActions, agentWork: agentWork,
                           onShowAgentWork: showAgentWork)
                .transition(motion.pageTransition)
            #endif
        case .disk:
            RoomDiskMapView(insights: insights).transition(motion.pageTransition)
        case .developer:
            RoomDeveloperView(model: developer).transition(motion.pageTransition)
        case .activity:
            #if ROOM_APP_STORE
            RoomActivityView(model: model).transition(motion.pageTransition)
            #else
            RoomActivityView(model: model, agentWork: agentWork).transition(motion.pageTransition)
            #endif
        #if !ROOM_APP_STORE
        case .agentWork:
            RoomAgentWorkView(model: agentWork, memoryReport: insights.memoryReport, onShowActivity: showActivity)
                .transition(motion.pageTransition)
        #endif
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                RoomMark().fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text("Room").font(RoomType.heading(15))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) { RoomNavigationBar(selection: $destination) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3") }
                .help("Settings")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
        }
    }

    @ViewBuilder private func sheetContent(for selected: RoomSheet) -> some View {
        switch selected {
        case .review: RoomReviewSheet(model: model)
        case .source(let source): sourceSheet(for: source)
        case .settings: RoomSettingsSheet(model: model, insights: insights, showWelcome: showWelcome)
        case .welcome: RoomOnboardingView(onFinish: finishOnboarding)
        case .protectedSources: RoomProtectedSheet(model: model)
        case .scanIssues: RoomScanIssuesSheet(issues: model.scanIssues)
        }
    }

    @ViewBuilder private func sourceSheet(for snapshot: RoomSource) -> some View {
        if !model.isScanning, let current = model.sources.first(where: { $0.id == snapshot.id }) {
            RoomSourceSheet(source: current, model: model)
        } else {
            RoomSheetLayout(title: snapshot.name,
                            subtitle: model.isScanning ? "Measuring this source again" : "Source no longer in these results") {
                RoomStatusNotice(message: model.isScanning
                    ? "The previous measurements are being replaced. Item selection returns when the new scan finishes."
                    : "This source is absent from the latest scan. Its previous cleanup selection is no longer available.")
                RoomPathLabel(path: snapshot.path)
            } actions: {
                Spacer()
                Button("Done") { sheet = nil }
                    .roomAction(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil && sheet == nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private func prepareInitialPresentation() async {
        if onboardingVersion < 1 { sheet = .welcome }
        await model.refreshHistory()
    }

    private func showWelcome() { sheet = .welcome }
    private func showActivity() { destination = .activity }
    #if !ROOM_APP_STORE
    private func showAgentWork() { destination = .agentWork }
    #endif

    private func finishOnboarding(_ task: RoomOnboardingTask?) {
        onboardingVersion = 1
        switch task {
        case .storage: destination = .clean
        case .memory: destination = .memory
        case .disk: destination = .disk
        case .developer: destination = .developer
        case nil: break
        }
        sheet = nil
    }

    private func handleCleanReviewRequest(_ path: String?) {
        guard let path else { return }
        requestedReviewPath = path
        destination = .clean
        category = nil
        sourceFilter = .all
        query = ""
        if let source = model.source(containing: path) {
            sheet = .source(source)
            requestedReviewPath = nil
        }
        insights.requestedCleanPath = nil
    }

    private func resolvePendingCleanReview(scannedAt date: Date?) {
        guard date != nil, destination == .clean, let path = requestedReviewPath,
              let source = model.source(containing: path) else { return }
        sheet = .source(source)
        requestedReviewPath = nil
    }

    private func handleInsightDestination(_ requested: RoomInsightDestination?) {
        guard let requested else { return }
        switch requested {
        case .clean: destination = .clean
        case .memory: destination = .memory
        case .disk: destination = .disk
        case .settings: sheet = .settings
        }
        insights.requestedDestination = nil
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoomPageHeader(title: model.isScanning ? "Measuring storage" : "Storage overview", subtitle: heroSubtitle) {
                scanActions
            }
            scanScopePicker
            if model.isScopeChangePending, let measuredScope = model.resultsScope {
                RoomStatusNotice(title: "\(measuredScope.title) results", message: "The measurements below belong to the previous scope. Run \(model.scanScope.title.lowercased()) to update them before cleanup.", tone: .information)
            }
            if let path = requestedReviewPath {
                RoomContentGroup {
                    RoomStatusNotice(title: "Find its cleanup source", message: "Scan known sources to check this item’s actual eligibility. Suggestions never authorize a change.", systemImage: "arrow.turn.down.right")
                    RoomPathLabel(path: path)
                    Button("Dismiss") { requestedReviewPath = nil }.buttonStyle(.plain)
                }
            }

            if model.lastScanned != nil || !model.sources.isEmpty {
                storageSummary
            }
            #if ROOM_APP_STORE
            if !model.isScanning, let coverage = model.npmDiscovery {
                RoomContentGroup {
                    RoomSectionHeader(title: "npm prefix review", detail: "Batch \(model.npmBatchNumber)") {
                        if coverage.hasMore {
                            Button("Next npm batch") { model.continueNPMScan() }
                                .buttonStyle(.glass)
                                .disabled(!model.canScan)
                                .accessibilityIdentifier("RoomNPMContinueButton")
                                .help("Replaces the current scan and selection with the next bounded prefix batch. No files move.")
                        }
                    }
                    Text("\(coverage.inspectedBuckets) prefix folders inspected in this batch. \(coverage.hasMore ? "More prefixes remain. The next batch replaces these results and their selection." : "Prefix discovery reached the end of this approved scope.") Object verification and inspection limits still apply.")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
            }
            #endif

            if model.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("\(model.scannedLocationCount) of \(model.scanLocationCount) \(model.scanLocationCount == 1 ? "location" : "locations")")
                            .fixedSize()
                        Text(model.currentScanPath)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.currentScanPath)
                    }
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
                    ProgressView(value: model.scanProgress).tint(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            sourceSection

            HStack(alignment: .center, spacing: 12) {
                Button { sheet = .protectedSources } label: {
                    Label("What stays", systemImage: "lock.shield")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("See the data Room protects")
                if model.hasPartialMeasurements && !model.isScanning {
                    Text("Some sizes are lower bounds")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if model.isScanning {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("Measuring…")
                    }
                } else if !model.scanIssues.isEmpty {
                    Button("\(model.scanIssues.count) scan \(model.scanIssues.count == 1 ? "note" : "notes")") { sheet = .scanIssues }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else if let lastScanned = model.lastScanned {
                    Text("Scanned \(lastScanned, style: .relative) ago")
                        .foregroundStyle(.secondary)
                }
                if model.availableBytes > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(RoomFormat.bytes(model.availableBytes)) available")
                        .foregroundStyle(.secondary)
                }
            }
            .font(RoomTypography.caption)

            if let message = model.statusMessage, !message.isEmpty, !model.isScanning {
                Text(message)
                    .font(RoomTypography.body)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var storageSummary: some View {
        RoomContentGroup {
            HStack(alignment: .center, spacing: RoomSpace.section) {
                RoomMetric(label: model.isScanning ? "Measured so far" : "Measured storage", bytes: model.totalBytes,
                           lowerBound: model.hasPartialMeasurements)
                summaryMetric("Clearable", bytes: model.clearableBytes)
                summaryMetric("Held", bytes: model.heldBytes, lowerBound: model.hasPartialMeasurements)
            }
        }
    }

    private func summaryMetric(_ title: String, bytes: Int64, lowerBound: Bool = false) -> some View {
        RoomMetric(label: title, bytes: bytes, maximumSize: 22, lowerBound: lowerBound)
    }

    @ViewBuilder private var scanScopePicker: some View {
        #if ROOM_APP_STORE
        HStack(spacing: 12) {
            Label(model.approvedStoreFolderCount == 0 ? "No folders approved" : "\(model.approvedStoreFolderCount) approved \(model.approvedStoreFolderCount == 1 ? "folder" : "folders")", systemImage: "folder.badge.checkmark")
                .font(RoomTypography.caption).foregroundStyle(.secondary)
                .fixedSize()
            Button("Manage access") { sheet = .settings }
                .buttonStyle(.glass).controlSize(.large)
                .disabled(model.isWorking || model.isScanning)
                .accessibilityIdentifier("RoomStoreManageFolderAccess")
        }
        .frame(minHeight: 36)
        #else
        Picker("Scan scope", selection: Binding(get: { model.scanScope }, set: { model.setScanScope($0) })) {
            ForEach(RoomCacheScanScope.allCases) { scope in Text(scope.title).tag(scope) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .font(RoomTypography.bodyEmphasis)
        .frame(width: 228)
        .frame(minHeight: 36)
        .accessibilityLabel("Scan scope")
        .accessibilityIdentifier("RoomCacheScanScopePicker")
        .disabled(model.isScanning || model.isWorking)
        .help("Full scan includes developer stores, app and hidden caches, logs, and your temporary folder. Quick scan checks the core catalogue.")
        #endif
    }

    private var scanActions: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: refreshCurrentView) {
                Label(scanButtonTitle, systemImage: model.isScanning ? "stop.fill" : "magnifyingglass")
                    .font(RoomTypography.bodyEmphasis)
                    .padding(.horizontal, 4)
            }
            .roomAction(model.canReviewCleanup ? .secondary : .primary)
            .controlSize(.large)
            .frame(minHeight: 36)
            .disabled(!model.canScan)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("RoomCacheScanButton")

            if model.canReviewCleanup {
                Button { sheet = .review } label: {
                    Label("Review \(RoomFormat.bytes(model.selectedBytes))", systemImage: "arrow.right")
                        .font(RoomTypography.bodyEmphasis)
                        .padding(.horizontal, 4)
                }
                .roomAction(.primary)
                .controlSize(.large)
                .frame(minHeight: 36)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var scanButtonTitle: String {
        if model.isScanning { return "Stop scan" }
        #if ROOM_APP_STORE
        if model.approvedStoreFolderCount == 0 { return "Choose folder & scan" }
        #endif
        return "Scan caches"
    }

    private var heroSubtitle: String {
        if model.isScanning { return "Measured so far. Your apps can stay open." }
        if model.isPartialScan { return "Partial measurements. Scan again to finish." }
        #if ROOM_APP_STORE
        if model.lastScanned == nil { return "Choose folders to inspect supported developer storage." }
        #else
        if model.lastScanned == nil { return "Caches, developer stores, and temporary files." }
        #endif
        if model.totalBytes == 0 { return "No cache data measured. Check scan notes for access issues." }
        if model.clearableBytes == 0 { return "Found on disk. Inspect each source to see what is held and why." }
        if selectedCount == 0 { return "Choose the sources you want to move to Trash." }
        return "\(selectedCount) \(selectedCount == 1 ? "source" : "sources") selected. \(RoomFormat.bytes(model.selectedBytes)) ready for review."
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    sourceSectionTitle
                    Spacer(minLength: 12)
                    if !model.sources.isEmpty { sourceFilters }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sourceSectionTitle
                    if !model.sources.isEmpty { sourceFilters }
                }
            }
            .padding(.bottom, 2)

            if !model.sources.isEmpty {
                HStack(spacing: RoomSpace.compact) {
                    Text("\(model.selectedEntryIDs.count) \(model.selectedEntryIDs.count == 1 ? "item" : "items") selected")
                        .font(RoomTypography.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 12)
                    Button("Select eligible") { model.selectRecommended() }.buttonStyle(.plain)
                    Button("Deselect all") { model.clearSelection() }.buttonStyle(.plain)
                }
                .font(RoomTypography.caption)
                .disabled(!model.canEditSelection)
            }

            if model.sources.isEmpty {
                sourceEmptyState
            } else if visibleSources.isEmpty {
                RoomEmptyState(title: "No matching sources", message: sourceFilter == .clearable ? "Open Held to see why files are protected." : "Try another category or filter.", systemImage: "line.3.horizontal.decrease") {
                    Button("Reset filters") { query = ""; category = nil; sourceFilter = .all }.buttonStyle(.glass)
                }
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(visibleSources) { source in
                        RoomSourceRow(source: source,
                                      selected: model.selection.contains(source.id),
                                      partiallySelected: model.partiallySelectedSource(source.id),
                                      selectedCount: model.selectedCount(for: source.id),
                                      disabled: !model.canEditSelection,
                                      toggle: { model.toggleSelection(id: source.id) },
                                      inspect: { sheet = .source(source) })
                    }
                }
            }

            if model.sources.count > 8 && category == nil && sourceFilter == .all && query.isEmpty {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? "Show less" : "Show all \(model.sources.count) sources")
                        Image(systemName: "chevron.down")
                            .font(RoomTypography.meta)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(RoomTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceSectionTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("Sources").font(RoomTypography.sectionTitle).accessibilityAddTraits(.isHeader)
            if !model.sources.isEmpty {
                Text(matchingSources.count == model.sources.count ? "\(model.sources.count)" : "\(matchingSources.count) of \(model.sources.count)")
                    .font(RoomTypography.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .fixedSize()
    }

    private var sourceFilters: some View {
        HStack(spacing: 12) {
            sourceSearch
            Picker("Show sources", selection: $sourceFilter) {
                Text("All").tag(RoomSourceFilter.all)
                Text("Clearable").tag(RoomSourceFilter.clearable)
                Text("Held").tag(RoomSourceFilter.held)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Show sources")
            .frame(width: 220)
            sourceCategoryMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sourceEmptyState: some View {
        RoomEmptyState(
            title: model.isScanning ? "Preparing locations" : model.isPartialScan ? "Scan again to finish" : model.lastScanned == nil ? "Ready for a scan" : "No sources measured",
            message: model.isScanning ? "Results appear as each source is measured." : model.lastScanned == nil ? "A scan measures storage before you review any changes." : "Check scan notes for access or inspection limits.",
            systemImage: model.isScanning ? "magnifyingglass" : "externaldrive")
    }

    private var sourceSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a source", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 130)
                .accessibilityLabel("Find a cache source")
        }
        .font(RoomTypography.body)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
    }

    private var sourceCategoryMenu: some View {
        Menu {
            Button("All sources") { category = nil }
            ForEach(RoomCategory.allCases) { item in
                Button(item.title) { category = item }
            }
        } label: {
            Text(category?.title ?? "All categories").font(RoomTypography.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isWorking)
    }

}

private struct RoomSourceRow: View {
    let source: RoomSource
    let selected: Bool
    let partiallySelected: Bool
    let selectedCount: Int
    let disabled: Bool
    let toggle: () -> Void
    let inspect: () -> Void
    @State private var hovering = false

    private var statusLabel: String {
        if source.isInspectionOnly { return "Inspect only" }
        if source.isAvailable { return "\(RoomFormat.bytes(source.eligibleBytes)) clearable" }
        return source.isPartial ? "Partial" : "Held"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoomSelectionCheckbox(state: partiallySelected ? .mixed : selected ? .on : .off,
                                  label: "\(source.name), \(selectedCount) of \(source.selectableCount) eligible items selected",
                                  isEnabled: !disabled && !source.isInspectionOnly && source.isAvailable,
                                  action: toggle)
                .frame(width: 18)
                .help(source.blockedReason ?? (source.isInspectionOnly ? "This source is available for inspection only." : source.isAvailable ? "Include this source in the cleanup review." : "This source is held and cannot be selected."))

            Image(systemName: source.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Button(action: inspect) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .font(RoomTypography.bodyEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(source.subtitle)
                            .font(RoomTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(source.isPartial ? "≥ " : "")\(RoomFormat.bytes(source.bytes))")
                            .font(RoomTypography.bodyEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(statusLabel)
                            .font(RoomTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 112, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.right")
                        .font(RoomTypography.meta)
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0.65)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(source.blockedReason ?? source.subtitle)
            .accessibilityLabel("Inspect \(source.name), \(source.isPartial ? "at least " : "")\(RoomFormat.bytes(source.bytes)) measured, \(statusLabel)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? RoomSurface.selection : hovering ? RoomSurface.hover : Color.clear, in: RoundedRectangle(cornerRadius: RoomRadius.row))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Inspect source", action: inspect)
        }
    }
}

private enum RoomSourceFilter: Hashable { case all, clearable, held }

private enum RoomSheet: Identifiable {
    case review, source(RoomSource), settings, welcome, protectedSources, scanIssues
    var id: String {
        switch self {
        case .review: "review"
        case .source(let source): "source-\(source.id)"
        case .settings: "settings"
        case .welcome: "welcome"
        case .protectedSources: "protected"
        case .scanIssues: "issues"
        }
    }
}
