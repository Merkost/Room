import AppKit
import SwiftUI

struct RoomRootView: View {
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    @Bindable var rooms: RoomRoomsModel
    @Bindable var navigation: RoomWindowNavigation
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    #endif
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @AppStorage(RoomOverviewPrivacy.key) private var overviewSizesHidden = false
    @Environment(\.openSettings) private var openSettings
    @State private var developer = RoomDeveloperModel()
    @State private var sheet: RoomSheet?

    private var destination: RoomDestination { navigation.destination }
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    private var screenActions: RoomScreenActions {
        switch destination {
        case .overview:
            RoomScreenActions(destination: .overview, canRescan: true, rescan: insights.refreshDiskCapacity,
                              overviewSizesHidden: overviewSizesHidden, toggleOverviewSizes: { overviewSizesHidden.toggle() })
        case .clean:
            RoomScreenActions(destination: .clean, canRescan: model.canRescanFromMenu, isScanning: model.isScanning,
                              rescan: model.rescanFromMenu, stop: model.cancelScan)
        case .disk:
            RoomScreenActions(destination: .disk, canRescan: insights.canRescanDisk, isScanning: insights.isScanningDisk,
                              rescan: insights.rescanDisk, stop: insights.cancelDiskScan,
                              canEnclose: insights.canGoUpInApprovedMap, enclose: insights.encloseApprovedDiskFolder)
        case .developer:
            RoomScreenActions(destination: .developer, canRescan: developer.canScan, isScanning: developer.isScanning,
                              rescan: developer.scan, stop: developer.stop)
        case .memory:
            RoomScreenActions(destination: .memory, canRescan: true, isScanning: insights.isScanningMemory,
                              rescan: insights.scanMemory)
        case .activity:
            RoomScreenActions(destination: .activity)
        }
    }

    var body: some View {
        ZStack {
            if destination == .overview {
                RoomTokens.Surface.canvas.ignoresSafeArea()
            } else {
                RoomAmbientBackground()
            }
            if destination == .disk {
                RoomDiskMapView(insights: insights)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch destination {
                        case .overview:
                            RoomOverviewView(insights: insights, navigate: navigation.select, refresh: insights.refreshDiskCapacity,
                                             cacheModel: model, hidden: overviewSizesHidden)
                        case .clean:
                            RoomCachesView(model: model, review: { sheet = .review },
                                inspect: { sheet = .source($0) }, showKept: { sheet = .protectedSources },
                                showScanNotes: { sheet = .scanIssues }, restore: restoreFromCaches)
                        case .memory:
                            RoomMemoryView(insights: insights, memoryActions: memoryActions)
                        case .disk:
                            EmptyView()
                        case .developer:
                            #if ROOM_APP_STORE
                            RoomDeveloperView(model: developer)
                            #else
                            RoomDeveloperView(model: developer, agentWork: agentWork, memoryReport: insights.memoryReport)
                            #endif
                        case .activity:
                            RoomActivityView(model: model)
                                .task { await model.refreshHistory() }
                        }
                    }
                    .padding(.horizontal, destination == .overview ? RoomTokens.Density.calm.gutter : 28)
                    .padding(.top, RoomTokens.Density.calm.topInset)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 1120, minHeight: destination == .overview ? RoomTokens.Density.calm.firstScreenMinHeight : nil,
                           alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 800, minHeight: 650)
        .preferredColorScheme(colorScheme)
        .focusedSceneValue(\.roomScreen, screenActions)
        .toolbar {
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
            ToolbarItem(placement: .principal) {
                RoomNavigationBar(selection: Binding(get: { destination }, set: navigation.select))
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                if destination == .overview { RoomOverviewHideControl(hidden: $overviewSizesHidden) }
                if destination == .clean, model.hasReport {
                    Button(action: model.rescanFromMenu) {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.canRescanFromMenu || model.isScanning)
                    .help("Check caches again")
                }
                Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $sheet) { selected in
            switch selected {
            case .review: RoomCleanupReviewSheet(model: model)
            case .source(let source): RoomSourceSheet(source: source, model: model)
            case .welcome:
                RoomOnboardingView {
                    navigation.dismissWelcome()
                    sheet = nil
                }
            case .protectedSources: RoomProtectedSheet(model: model)
            case .scanIssues: RoomScanIssuesSheet(issues: model.scanIssues)
            #if ROOM_APP_STORE
            case .restore(let record): RoomStoreRestoreSheet(model: model, record: record)
            #endif
            }
        }
        .alert("Room couldn’t complete that", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onAppear { if navigation.needsWelcome { sheet = .welcome } }
        .onChange(of: developer.accessRevision) { _, _ in developer.accessChanged() }
        #if ROOM_APP_STORE
        .onChange(of: model.storeAccessRevision) { _, _ in model.storeAccessChanged() }
        #endif
        .onChange(of: insights.requestedDestination, initial: true) { _, _ in
            navigation.consumeRequest(from: insights)
        }
        .onChange(of: insights.requestedSettings, initial: true) { _, requested in
            guard requested else { return }
            openSettings()
            insights.requestedSettings = false
        }
        .onChange(of: insights.requestedWelcome, initial: true) { _, requested in
            guard requested else { return }
            sheet = .welcome
            insights.requestedWelcome = false
        }
    }

    private func restoreFromCaches(_ record: RoomActivity) {
        #if ROOM_APP_STORE
        sheet = .restore(record)
        #else
        Task { await model.restore(record: record) }
        #endif
    }
}

private enum RoomSheet: Identifiable {
    case review, source(RoomSource), welcome, protectedSources, scanIssues
    #if ROOM_APP_STORE
    case restore(RoomActivity)
    #endif
    var id: String {
        switch self {
        case .review: "review"
        case .source(let source): "source-\(source.id)"
        case .welcome: "welcome"
        case .protectedSources: "protected"
        case .scanIssues: "issues"
        #if ROOM_APP_STORE
        case .restore(let record): "restore-\(record.id)"
        #endif
        }
    }
}
