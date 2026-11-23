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
    var isOnboardingBusy: () -> Bool = { false }
    var enableOnboardingMonitor: () -> Void = {}
    var showOnboardingMonitor: () -> Void = {}
    @State private var onboardingFollowUp: [RoomOnboardingEffect] = []
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @Environment(\.roomHide) private var hide
    @Environment(\.openSettings) private var openSettings
    @Environment(\.roomMotion) private var motion
    #if DEBUG
    @State private var developer = RoomDeveloperModel.debugFixture()
        ?? RoomDeveloperModel(unreferencedStore: .init(writer: .shared), activityCenter: .shared)
    #else
    @State private var developer = RoomDeveloperModel(unreferencedStore: .init(writer: .shared), activityCenter: .shared)
    #endif
    @State private var sheet: RoomSheet?
    @State private var showingCustomise = false
    @State private var editingRoom: UUID?
    @State private var leftOverviewAt: ContinuousClock.Instant?
    @State private var savedViews = RoomSavedViewsStore()
    @State private var openedSavedView: RoomSavedViewDisplay?
    @State private var savedViewRetry = UUID()

    private struct SavedViewRequest: Equatable {
        let route: RoomRoute
        let retry: UUID
    }

    private var savedViewDisplay: RoomSavedViewDisplay? {
        guard case .savedView(let id) = navigation.route,
              let view = savedViews.entries.first(where: { $0.id == id }) else { return nil }
        if let openedSavedView, openedSavedView.view.id == id {
            return RoomSavedViewDisplay(requestID: openedSavedView.requestID, view: view, result: openedSavedView.result)
        }
        return RoomSavedViewDisplay(requestID: savedViewRetry, view: view, result: nil)
    }

    private var destination: RoomDestination { navigation.destination }
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    private var screenActions: RoomScreenActions {
        var commands = destinationActions
        commands.showHistory = { sheet = .history }
        return commands
    }

    private var destinationActions: RoomScreenActions {
        switch destination {
        case .overview:
            RoomScreenActions(destination: .overview, canRescan: true, rescan: {
                insights.refreshDiskCapacity()
                rooms.measureNext()
            }, customise: { showingCustomise.toggle() })
        case .clean:
            RoomScreenActions(destination: .clean, canRescan: model.canRescanFromMenu, isScanning: model.isScanning,
                              rescan: model.rescanFromMenu, stop: model.cancelScan)
        case .disk:
            diskActions
        case .developer:
            RoomScreenActions(destination: .developer, canRescan: developer.canScan, isScanning: developer.isScanning,
                              rescan: developer.scan, stop: developer.stop)
        case .memory:
            RoomScreenActions(destination: .memory, canRescan: true, isScanning: insights.isScanningMemory,
                              rescan: insights.scanMemory)
        }
    }

    private var diskActions: RoomScreenActions {
        let mayUseMap = savedViewDisplay?.showsMap ?? true
        var actions = RoomScreenActions(destination: .disk, canRescan: mayUseMap && insights.canRescanDisk,
            isScanning: insights.isScanningDisk, rescan: insights.rescanDisk, stop: insights.cancelDiskScan,
            canEnclose: mayUseMap && insights.canGoUpInApprovedMap, enclose: insights.encloseApprovedDiskFolder)
        guard mayUseMap else { return actions }
        if insights.diskMap.current != nil {
            actions.showDiskInspector = { insights.toggleDiskInspector() }
            actions.diskInspectorVisible = insights.diskInspectorVisible
        }
        if let title = diskComparisonTitle {
            actions.comparisonTitle = title
            actions.compareDiskMap = { insights.compareDiskMap() }
        }
        return actions
    }

    var body: some View {
        RoomShellView(navigation: navigation, rooms: rooms, insights: insights, selectRoom: openPinnedRoom,
                      savedViews: savedViews, selectSavedView: openSavedView) {
            RoomScreenScaffold(title: screenActions.title, subtitle: screenSubtitle, scrolls: destination != .disk) {
                screenContent
            }
        }
        .preferredColorScheme(colorScheme)
        .focusedSceneValue(\.roomScreen, screenActions)
        .toolbar {
            ToolbarItem(placement: .principal) {
                RoomActivityPill(stop: stopActivity, restore: restoreActivity, showHistory: { sheet = .history },
                                 prefersQuietIdleLabel: destination == .overview)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                RoomHistoryButton(model: model, show: { sheet = .history }, restore: restoreFromCaches)
                if destination == .overview {
                    Button { showingCustomise.toggle() } label: {
                        Label("Customise", systemImage: "slider.horizontal.3")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Customise Overview")
                    .accessibilityIdentifier("RoomCustomiseOverview")
                    .popover(isPresented: $showingCustomise) {
                        RoomCustomisePopover(rooms: rooms, capacityBytes: insights.volumeCapacity?.capacityBytes ?? 210_000_000_000,
                            selected: $editingRoom, hidden: hide.masksNow,
                            canChoosePlanStyle: RoomOverviewStyle.isAvailable(homeKinds: insights.homeKinds),
                            hasRecentReceipts: model.makeRoomStore != nil)
                    }
                }
            }
        }
        .sheet(item: $sheet, onDismiss: performOnboardingFollowUp) { selected in
            switch selected {
            case .review: RoomCleanupReviewSheet(model: model)
            case .mapCleanup(let context):
                RoomCleanupReviewSheet(model: model, mapCleanup: context.request, canAccessMapCleanup: {
                    canAccessMapCleanup(context)
                })
            case .source(let source): RoomSourceSheet(source: source, model: model)
            case .welcome:
                RoomOnboardingView(capacity: insights.volumeCapacity, isWorking: isOnboardingBusy(),
                                   needsPicker: !insights.hasRememberedHomeAccess, onFinish: finishWelcome)
                    .modifier(RoomMotionRoot())
                    .modifier(RoomAccentRoot())
                    .preferredColorScheme(colorScheme)
            case .protectedSources: RoomWhatStaysSheet(model: model)
            case .scanIssues: RoomScanIssuesSheet(issues: model.scanIssues)
            case .history: RoomHistorySheet(model: model)
            #if ROOM_APP_STORE
            case .restore(let record): RoomStoreRestoreSheet(model: model, record: record)
            #endif
            }
        }
        .alert(model.operationAlert?.title ?? "Room couldn’t complete that",
               isPresented: Binding(get: { model.operationAlert != nil || model.errorMessage != nil }, set: { if !$0 { dismissAlert() } })) {
            if let alert = model.operationAlert {
                Button(alert.primary.rawValue) { performAlertAction(alert.primary) }
                if let secondary = alert.secondary { Button(secondary, role: .cancel, action: dismissAlert) }
            } else {
                Button("OK", action: dismissAlert)
            }
        } message: { Text(model.operationAlert?.message ?? model.errorMessage ?? "") }
        .onAppear { if navigation.needsWelcome { sheet = .welcome } }
        .onReceive(NotificationCenter.default.publisher(for: .roomSavedHistoryForgotten)) { _ in
            developer.clearUnreferencedHistory()
        }
        .onChange(of: developer.accessRevision) { _, _ in developer.accessChanged() }
        .onChange(of: model.configurationRevision, initial: true) { _, _ in
            insights.updateCacheConfiguration(model.inspectionConfiguration)
        }
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
        .onChange(of: insights.diskMap.current) { _, map in
            if let map, let root = insights.diskMap.rootURL { rooms.applyMap(map, root: root) }
        }
        .onChange(of: navigation.route, initial: true) { _, route in
            if destination != .overview { showingCustomise = false }
            RoomHideControl.shared.cancelPeek()
            guard case .room(let id) = route, let url = rooms.url(for: id) else { return }
            insights.openDiskMap(rootURL: url, requestNavigation: false)
        }
        .task { await savedViews.load() }
        .task(id: SavedViewRequest(route: navigation.route, retry: savedViewRetry)) {
            openedSavedView = nil
            guard case .savedView(let id) = navigation.route else { return }
            await savedViews.load()
            guard !Task.isCancelled, let view = savedViews.visible.first(where: { $0.id == id }) else { return }
            let outcome = await insights.openSavedDiskView(view)
            guard !Task.isCancelled, navigation.route == .savedView(id) else { return }
            openedSavedView = RoomSavedViewDisplay(requestID: UUID(), view: view, result: outcome)
        }
        .onChange(of: savedViews.entries.map(\.id)) { old, new in
            for removed in Set(old).subtracting(new) { navigation.removeRoute(.savedView(removed)) }
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

    /// The welcome's effects (RoomOnboardingFlow). Skip always closes; a choice waits while work is running.
    private func finishWelcome(_ effects: [RoomOnboardingEffect]) -> Bool {
        guard effects == RoomOnboardingFlow.skipEffects || !isOnboardingBusy() else { return false }
        onboardingFollowUp = effects.filter { $0 != .markSeen && $0 != .close }
        if effects.contains(.markSeen) { navigation.dismissWelcome() }
        if effects.contains(.close) { sheet = nil }
        return true
    }

    private func performOnboardingFollowUp() {
        let effects = onboardingFollowUp
        onboardingFollowUp = []
        for effect in effects {
            switch effect {
            case .markSeen, .close: break
            case .navigate(let raw):
                if let destination = RoomDestination(rawValue: raw) { navigation.select(destination) }
            case .scanHome(let confirmed): insights.scanHome(confirmed: confirmed)
            case .chooseStoreCachesFolder:
                #if ROOM_APP_STORE
                model.chooseStoreFolder(scanAfterApproval: true)
                #endif
            case .startCachesCheck:
                #if !ROOM_APP_STORE
                model.scan()
                #endif
            case .enableMenuBar: enableOnboardingMonitor()
            case .showMonitorOnce: showOnboardingMonitor()
            }
        }
    }

    private var diskComparisonTitle: String? {
        guard let date = insights.diskMap.comparison?.date else { return nil }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return String(localized: "menu.disk.compareDate", defaultValue: "Compare with \(day)")
    }

    private var screenSubtitle: String? {
        switch destination {
        case .overview: nil
        case .disk: nil
        case .clean: model.cachesStatus
        case .memory, .developer: nil
        }
    }

    private func openPinnedRoom(_ id: UUID) {
        guard insights.canChooseDiskLocation else { return }
        guard rooms.url(for: id) != nil else {
            rooms.chooseFolder(replacingApprovalFor: id)
            return
        }
        navigation.select(.room(id), origin: .controlActivation)
    }

    @ViewBuilder private var screenContent: some View {
        switch destination {
        case .overview:
            RoomOverviewView(insights: insights, rooms: rooms,
                             navigate: { navigation.select(.screen($0), origin: .controlActivation) }, refresh: insights.refreshDiskCapacity,
                             cacheModel: model, editingRoom: showingCustomise ? editingRoom : nil,
                             showAllRooms: { showingCustomise = true }, restoreRecent: restoreFromCaches,
                             animatesArrival: overviewArrival)
                .onDisappear { leftOverviewAt = .now }
        case .clean:
            RoomCachesView(model: model, review: { sheet = .review },
                inspect: { sheet = .source($0) }, showKept: { sheet = .protectedSources },
                showScanNotes: { sheet = .scanIssues }, restore: restoreFromCaches)
                .roomPanelArrival(enabled: navigation.selectionOrigin == .pointer, from: RoomTokens.Space.tight)
        case .memory:
            RoomMemoryView(insights: insights, memoryActions: memoryActions)
        case .disk:
            RoomDiskMapView(insights: insights, rooms: rooms, savedViews: savedViews,
                savedViewDisplay: savedViewDisplay, openSavedView: openSavedView,
                canInspectCacheSource: { cacheSource(for: $0) != nil },
                inspectCacheSource: inspectCacheSource, cleanupAction: mapCleanupAction,
                activateCleanup: activateMapCleanup)
        case .developer:
            #if ROOM_APP_STORE
            RoomDeveloperView(model: developer)
            #else
            RoomDeveloperView(model: developer, agentWork: agentWork, memoryReport: insights.memoryReport)
            #endif
        }
    }

    private func cacheSource(for url: URL) -> RoomSource? {
        guard !hide.masksNow, model.hasReport, !model.isScanning, !model.isWorking,
              insights.approvedMapScope(for: url) != nil else { return nil }
        return model.source(containing: url.path)
    }

    private func inspectCacheSource(_ url: URL) {
        guard let source = cacheSource(for: url) else { return }
        navigation.select(.screen(.clean), origin: .controlActivation)
        sheet = .source(source)
    }

    private func mapCleanupAction(_ target: RoomMapCleanupTarget) -> RoomMapCleanupAction? {
        guard !hide.masksNow, !insights.isScanningDisk, insights.approvedMapFolder(for: target.url) != nil else { return nil }
        return model.mapCleanupAction(at: target.url, includesContents: target.includesContents)
    }

    private func activateMapCleanup(_ target: RoomMapCleanupTarget) {
        guard insights.diskMap.cleanupTarget == target,
              let folder = insights.approvedMapFolder(for: target.url) else { return }
        switch mapCleanupAction(target) {
        case .check, .empty: model.scan()
        case .review:
            if let request = model.makeMapCleanup(at: target.url, includesContents: target.includesContents) {
                sheet = .mapCleanup(RoomMapCleanupContext(request: request, target: target, route: navigation.route,
                                                        approvalID: folder.id))
            }
        case .checking, nil: break
        }
    }

    private func canAccessMapCleanup(_ context: RoomMapCleanupContext) -> Bool {
        !hide.masksNow && !insights.isScanningDisk && navigation.route == context.route
            && insights.diskMap.cleanupTarget == context.target
            && insights.approvedMapFolder(for: context.target.url)?.id == context.approvalID
    }

    private func openSavedView(_ id: UUID) {
        guard insights.canChooseDiskLocation, savedViews.visible.contains(where: { $0.id == id }) else { return }
        if navigation.route == .savedView(id) {
            savedViewRetry = UUID()
        } else {
            navigation.select(.savedView(id), origin: .controlActivation)
        }
    }

    private var overviewArrival: Bool {
        guard navigation.selectionOrigin != .keyboard, !navigation.needsWelcome else { return false }
        guard let leftOverviewAt else { return true }
        return leftOverviewAt.duration(to: .now) >= .seconds(600)
    }

    private func restoreFromCaches(_ record: RoomActivity) {
        #if ROOM_APP_STORE
        sheet = .restore(record)
        #else
        Task { await model.restore(record: record) }
        #endif
    }

    private func restoreActivity(_ id: UUID) {
        guard !model.isScanning, !model.isWorking, let receipt = model.activity.first(where: { $0.id == id && $0.canRestore }) else { return }
        restoreFromCaches(receipt)
    }

    private func stopActivity(_ tool: RoomActivityPillState.Tool) {
        switch tool {
        case .caches: model.cancelScan()
        case .diskMap: insights.cancelDiskScan()
        case .developer: developer.stop()
        }
    }

    private func dismissAlert() {
        model.operationAlert = nil
        model.errorMessage = nil
    }

    private func performAlertAction(_ action: RoomActionAlert.Primary) {
        dismissAlert()
        switch action {
        case .checkAgain: model.scan()
        case .reviewAgain: if model.canReviewCleanup { sheet = .review }
        case .showSkipped, .showWhy: sheet = .history
        case .showInTrash: model.openTrash()
        case .ok: break
        }
    }
}

private struct RoomMapCleanupContext {
    let request: RoomMapCleanup
    let target: RoomMapCleanupTarget
    let route: RoomRoute
    let approvalID: String
}

private enum RoomSheet: Identifiable {
    case review, source(RoomSource), welcome, protectedSources, scanIssues, history
    case mapCleanup(RoomMapCleanupContext)
    #if ROOM_APP_STORE
    case restore(RoomActivity)
    #endif
    var id: String {
        switch self {
        case .review: "review"
        case .mapCleanup: "map-cleanup"
        case .source(let source): "source-\(source.id)"
        case .welcome: "welcome"
        case .protectedSources: "protected"
        case .scanIssues: "issues"
        case .history: "history"
        #if ROOM_APP_STORE
        case .restore(let record): "restore-\(record.id)"
        #endif
        }
    }
}
