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
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var developer = RoomDeveloperModel()
    @State private var destination = RoomDestination.clean
    @State private var sheet: RoomSheet?
    @State private var expanded = false
    @State private var category: RoomCategory?
    @State private var sourceFilter: RoomSourceFilter = .all
    @State private var query = ""

    private var animate: Animation? { motionEnabled && !reduceMotion ? .smooth(duration: 0.24) : nil }
    private var selectedCount: Int { model.sources.filter { model.selection.contains($0.id) && $0.isAvailable }.count }
    private var visibleSources: [RoomSource] {
        let sources = model.sources.filter { source in
            (category == nil || source.category == category) &&
            (sourceFilter == .all || (sourceFilter == .clearable ? source.isAvailable :
                source.bytes > source.eligibleBytes || !source.heldReasons.isEmpty || source.blockedReason != nil || source.isPartial)) &&
            (query.isEmpty || (source.name + " " + source.subtitle + " " + source.path).localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            if lhs.eligibleBytes != rhs.eligibleBytes { return lhs.eligibleBytes > rhs.eligibleBytes }
            return lhs.bytes > rhs.bytes
        }
        return expanded || category != nil || sourceFilter != .all || !query.isEmpty ? sources : Array(sources.prefix(8))
    }
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    private var canStopScan: Bool {
        switch destination { case .clean: model.isScanning; case .disk: insights.isScanningDisk; default: false }
    }
    private var refreshLabel: String {
        switch destination {
        case .clean: model.isScanning ? "Stop cache scan" : "Scan caches (⌘R)"
        case .memory: "Scan memory (⌘R)"
        case .disk: insights.isScanningDisk ? "Stop folder scan" : "Rescan folder (⌘R)"
        case .developer: developer.isScanning ? "Stop developer review" : "Scan developer resources (⌘R)"
        case .activity: "Refresh"
        }
    }
    private var refreshDisabled: Bool {
        model.isWorking || (destination == .memory && insights.isScanningMemory) ||
        (destination == .disk && insights.diskURL == nil && !insights.isScanningDisk)
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
        }
    }

    var body: some View {
        ZStack {
            RoomAmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch destination {
                    case .clean:
                        overview
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                    case .memory:
                        #if ROOM_APP_STORE
                        RoomMemoryView(insights: insights, memoryActions: memoryActions)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                        #else
                        RoomMemoryView(insights: insights, memoryActions: memoryActions, agentWork: agentWork)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                        #endif
                    case .disk:
                        RoomDiskMapView(insights: insights)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                    case .developer:
                        RoomDeveloperView(model: developer)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 6)))
                    case .activity:
                        RoomActivityView(model: model)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 18)
                .padding(.bottom, 25)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 800, minHeight: 650)
        .preferredColorScheme(colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    RoomMark().stroke(.secondary, style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
                        .frame(width: 23, height: 23)
                    Text("Room").font(RoomType.heading(15))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .principal) {
                RoomNavigationBar(selection: $destination)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                if destination == .memory {
                    Button(action: refreshCurrentView) {
                        Image(systemName: canStopScan ? "stop" : "arrow.clockwise")
                    }
                    .help(refreshLabel)
                    .accessibilityLabel(refreshLabel)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refreshDisabled)
                }

                Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .animation(animate, value: destination)
        .animation(animate, value: expanded)
        .animation(animate, value: category)
        .animation(animate, value: model.selectedBytes)
        .animation(animate, value: model.totalBytes)
        .animation(animate, value: model.isScanning)
        .sheet(item: $sheet) { selected in
            switch selected {
            case .review: RoomReviewSheet(model: model)
            case .source(let source): RoomSourceSheet(source: source, model: model)
            case .settings: RoomSettingsSheet(model: model, insights: insights, showWelcome: { sheet = .welcome })
            case .welcome:
                RoomOnboardingView { onboardingVersion = 1; sheet = nil }
            case .protectedSources: RoomProtectedSheet(model: model)
            case .scanIssues: RoomScanIssuesSheet(issues: model.scanIssues)
            }
        }
        .alert("Room couldn’t complete that", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task {
            if onboardingVersion < 1 { sheet = .welcome }
            await model.refreshHistory()
        }
        .onChange(of: developer.accessRevision) { _, _ in developer.accessChanged() }
        #if ROOM_APP_STORE
        .onChange(of: model.storeAccessRevision) { _, _ in model.storeAccessChanged() }
        #endif
        .onChange(of: insights.requestedDestination, initial: true) { _, requested in
            guard let requested else { return }
            switch requested {
            case .clean: destination = .clean
            case .memory: destination = .memory
            case .disk: destination = .disk
            }
            insights.requestedDestination = nil
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.isScanning ? "Measuring storage." : "Storage overview")
                        .font(RoomType.heading(22))
                        .tracking(-0.4)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if model.hasPartialMeasurements {
                            Text("≥").font(RoomType.figure(25)).foregroundStyle(.secondary)
                        }
                        RoomByteMetric(bytes: model.totalBytes, maximumSize: 56)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("found").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.hasPartialMeasurements ? "At least " : "")\(RoomFormat.bytes(model.totalBytes)) found across scanned storage locations")

                    Text(heroSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.totalBytes > 0 && !model.isScanning {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryMetric("Clearable", bytes: model.clearableBytes)
                        summaryMetric("Held", bytes: model.heldBytes, lowerBound: model.hasPartialMeasurements)
                    }
                    .frame(width: 120, alignment: .leading)
                }

                RoomStorageVisual(selectionCount: selectedCount, isScanning: model.isScanning, motionEnabled: motionEnabled)
            }
            .frame(minHeight: 152)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    scanScopePicker
                    scanActions
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 14) {
                    scanScopePicker
                    scanActions
                }
            }

            if model.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("\(model.scannedLocationCount) of \(model.scanLocationCount) locations")
                            .fixedSize()
                        Text(model.currentScanPath)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.currentScanPath)
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
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
                    Button("\(model.scanIssues.count) scan notes") { sheet = .scanIssues }
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
            .font(.system(size: 12))

            if let message = model.statusMessage, !message.isEmpty, !model.isScanning {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func summaryMetric(_ title: String, bytes: Int64, lowerBound: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(lowerBound ? "≥ " : "")\(RoomFormat.bytes(bytes))")
                .font(RoomType.figure(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var scanScopePicker: some View {
        #if ROOM_APP_STORE
        HStack(spacing: 12) {
            Label(model.approvedStoreFolderCount == 0 ? "Choose folders" : "\(model.approvedStoreFolderCount) approved \(model.approvedStoreFolderCount == 1 ? "folder" : "folders")", systemImage: "folder.badge.checkmark")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize()
            Button("Manage access") { sheet = .settings }
                .buttonStyle(.glass).controlSize(.large)
                .disabled(model.isWorking || model.isScanning)
                .accessibilityIdentifier("RoomStoreManageFolderAccess")
        }
        .frame(minHeight: 40)
        #else
        Picker("Scan scope", selection: Binding(get: { model.scanScope }, set: { model.setScanScope($0) })) {
            ForEach(RoomCacheScanScope.allCases) { scope in Text(scope.title).tag(scope) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .font(.system(size: 13, weight: .medium))
        .frame(width: 228)
        .padding(4)
        .glassEffect(reduceTransparency ? .identity : .regular, in: Capsule())
        .frame(minHeight: 40)
        .accessibilityLabel("Scan scope")
        .accessibilityIdentifier("RoomCacheScanScopePicker")
        .disabled(model.isScanning || model.isWorking)
        .help("Full scan includes developer stores, app and hidden caches, logs, and your temporary folder. Quick scan checks the core catalogue.")
        #endif
    }

    private var scanActions: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: refreshCurrentView) {
                Label(model.isScanning ? "Stop scan" : "Scan caches", systemImage: model.isScanning ? "stop.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(red: 0.60, green: 0.79, blue: 0.91))
            .controlSize(.large)
            .disabled(!model.canScan)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("RoomCacheScanButton")

            if model.canReviewCleanup {
                Button { sheet = .review } label: {
                    Label("Review \(RoomFormat.bytes(model.selectedBytes))", systemImage: "arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("Sources").font(.system(size: 15, weight: .semibold))
                    if !model.sources.isEmpty {
                        Text("\(model.sources.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()

                Spacer(minLength: 12)

                if expanded { sourceSearch }

                if !model.sources.isEmpty {
                    Picker("Show sources", selection: $sourceFilter) {
                        Text("All").tag(RoomSourceFilter.all)
                        Text("Clearable").tag(RoomSourceFilter.clearable)
                        Text("Held").tag(RoomSourceFilter.held)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Show sources")
                    .frame(width: 220)
                }

                sourceCategoryMenu
            }
            .padding(.bottom, 2)

            if model.sources.isEmpty {
                Text(model.isScanning ? "Preparing locations. Results appear as each source is measured." : "Start a scan to inspect storage locations.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else if visibleSources.isEmpty {
                ContentUnavailableView("No matching sources", systemImage: "line.3.horizontal.decrease", description: Text(sourceFilter == .clearable ? "Open Held to see why files are protected." : "Try another category or filter."))
                    .frame(height: 130)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(visibleSources) { source in
                        RoomSourceRow(source: source,
                                      selected: model.selection.contains(source.id),
                                      disabled: model.isScanning || model.isPartialScan || model.isWorking,
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
                            .font(.system(size: 11, weight: .medium))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a source", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 120)
                .accessibilityLabel("Find a cache source")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
    }

    private var sourceCategoryMenu: some View {
        Menu {
            Button("All sources") { category = nil }
            ForEach(RoomCategory.allCases) { item in
                Button(item.title) { category = item }
            }
            Divider()
            Button("Select recommended") { model.selectRecommended() }
            Button("Deselect all") { model.clearSelection() }
        } label: {
            Text(category?.title ?? "All sources").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isWorking)
    }

}

private struct RoomSourceRow: View {
    let source: RoomSource
    let selected: Bool
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
            Toggle(source.name, isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(disabled || source.isInspectionOnly || !source.isAvailable)
                .accessibilityLabel("Select \(source.name)")
                .frame(width: 18)

            Image(systemName: source.symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Button(action: inspect) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(source.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(source.isPartial ? "≥ " : "")\(RoomFormat.bytes(source.bytes))")
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(statusLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 112, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0.4)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(source.blockedReason ?? source.subtitle)
            .accessibilityLabel("Inspect \(source.name), \(RoomFormat.bytes(source.eligibleBytes)) available")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
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
