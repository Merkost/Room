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
    @Environment(\.openSettings) private var openSettings
    @Environment(\.roomMotion) private var motion
    @State private var developer = RoomDeveloperModel()
    @State private var sheet: RoomSheet?
    @AppStorage(RoomOverviewPrivacy.key) private var overviewSizesHidden = false

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
        RoomShellView(navigation: navigation, rooms: rooms, insights: insights, selectRoom: openPinnedRoom) {
            RoomScreenScaffold(title: screenActions.title, subtitle: screenSubtitle, scrolls: destination != .disk) {
                screenContent
                    .frame(minHeight: destination == .overview ? RoomTokens.Density.calm.firstScreenMinHeight : nil, alignment: .topLeading)
            }
        }
        .preferredColorScheme(colorScheme)
        .focusedSceneValue(\.roomScreen, screenActions)
        .toolbar {
            if destination == .overview {
                ToolbarItem(placement: .primaryAction) { RoomOverviewHideControl(hidden: $overviewSizesHidden) }
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
        .onChange(of: insights.requestedPinnedRoom, initial: true) { _, id in
            guard let id else { return }
            openPinnedRoom(id)
            insights.requestedPinnedRoom = nil
        }
        .onChange(of: navigation.route) { _, route in
            guard case .room(let id) = route, let url = rooms.url(for: id) else { return }
            insights.openDiskMap(rootURL: url, requestNavigation: false)
        }
        .onChange(of: rooms.rooms.map(\.id)) { old, new in
            for removed in Set(old).subtracting(new) { navigation.removeRoute(.room(removed)) }
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

    private var screenSubtitle: String? {
        switch destination {
        case .overview: nil
        case .disk: insights.diskURL?.lastPathComponent
        case .clean, .memory, .developer, .activity: nil
        }
    }

    private func openPinnedRoom(_ id: UUID) {
        guard rooms.url(for: id) != nil else {
            rooms.chooseFolder(replacingApprovalFor: id)
            return
        }
        navigation.select(.room(id), origin: .pointer)
    }

    @ViewBuilder private var screenContent: some View {
        switch destination {
        case .overview:
            RoomOverviewView(insights: insights, rooms: rooms, navigate: navigation.select, refresh: insights.refreshDiskCapacity,
                             cacheModel: model, hidden: overviewSizesHidden)
        case .clean:
            RoomCachesView(model: model, review: { sheet = .review },
                inspect: { sheet = .source($0) }, showKept: { sheet = .protectedSources },
                showScanNotes: { sheet = .scanIssues }, restore: restoreFromCaches)
        case .memory:
            RoomMemoryView(insights: insights, memoryActions: memoryActions)
        case .disk:
            RoomDiskMapView(insights: insights)
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
