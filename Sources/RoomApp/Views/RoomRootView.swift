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
    @AppStorage(RoomOverviewPreferences.densityKey) private var overviewDensity = RoomTokens.Density.calm
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @Environment(\.roomHide) private var hide
    @Environment(\.openSettings) private var openSettings
    @Environment(\.roomMotion) private var motion
    @State private var developer = RoomDeveloperModel(unreferencedStore: .init(writer: .shared))
    @State private var sheet: RoomSheet?
    @State private var showingCustomise = false
    @State private var editingRoom: UUID?
    @State private var leftOverviewAt: ContinuousClock.Instant?

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
        var actions = RoomScreenActions(destination: .disk, canRescan: insights.canRescanDisk,
            isScanning: insights.isScanningDisk, rescan: insights.rescanDisk, stop: insights.cancelDiskScan,
            canEnclose: insights.canGoUpInApprovedMap, enclose: insights.encloseApprovedDiskFolder)
        if insights.diskMap.current != nil {
            actions.showDiskInspector = { insights.toggleDiskInspector() }
        }
        if let title = diskComparisonTitle {
            actions.comparisonTitle = title
            actions.compareDiskMap = { insights.compareDiskMap() }
        }
        return actions
    }

    var body: some View {
        RoomShellView(navigation: navigation, rooms: rooms, insights: insights, selectRoom: openPinnedRoom) {
            RoomScreenScaffold(title: screenActions.title, subtitle: screenSubtitle, scrolls: destination != .disk,
                               requestedDensity: destination == .overview ? overviewDensity : nil) {
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
                RoomGlobalHideButton(control: .shared, globalCoverage: true)
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
            case .source(let source): RoomSourceSheet(source: source, model: model)
            case .welcome:
                RoomOnboardingView(capacity: insights.volumeCapacity, isWorking: isOnboardingBusy(),
                                   openPrivacySettings: insights.openPrivacySettings, onFinish: finishWelcome)
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
        .onChange(of: navigation.route) { _, route in
            if destination != .overview { showingCustomise = false }
            RoomHideControl.shared.cancelPeek()
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

    private func finishWelcome(_ choice: RoomOnboardingChoice?) {
        guard choice == nil || !isOnboardingBusy() else { return }
        #if ROOM_APP_STORE
        let edition = RoomOnboardingEdition.store
        #else
        let edition = RoomOnboardingEdition.direct
        #endif
        let effects = choice.map { RoomOnboardingFlow.effects($0, edition: edition) } ?? RoomOnboardingFlow.skipEffects
        onboardingFollowUp = effects.filter { $0 != .markSeen && $0 != .close }
        if effects.contains(.markSeen) { navigation.dismissWelcome() }
        if effects.contains(.close) { sheet = nil }
    }

    private func performOnboardingFollowUp() {
        let effects = onboardingFollowUp
        onboardingFollowUp = []
        for effect in effects {
            switch effect {
            case .markSeen, .close: break
            case .navigate(let raw):
                if let destination = RoomDestination(rawValue: raw) { navigation.select(destination) }
            case .chooseHomeAccess, .chooseDiskFolder: insights.chooseDiskFolder()
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
        case .disk: insights.diskURL.map { RoomHideSpeech.value($0.lastPathComponent, hide: hide) }
        case .clean: model.cachesStatus
        case .memory, .developer: nil
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
                             cacheModel: model, editingRoom: showingCustomise ? editingRoom : nil,
                             showAllRooms: { showingCustomise = true }, restoreRecent: restoreFromCaches,
                             animatesArrival: overviewArrival)
                .onDisappear { leftOverviewAt = .now }
        case .clean:
            RoomCachesView(model: model, review: { sheet = .review },
                inspect: { sheet = .source($0) }, showKept: { sheet = .protectedSources },
                showScanNotes: { sheet = .scanIssues }, restore: restoreFromCaches)
        case .memory:
            RoomMemoryView(insights: insights, memoryActions: memoryActions)
        case .disk:
            RoomDiskMapView(insights: insights, rooms: rooms)
        case .developer:
            #if ROOM_APP_STORE
            RoomDeveloperView(model: developer)
            #else
            RoomDeveloperView(model: developer, agentWork: agentWork, memoryReport: insights.memoryReport)
            #endif
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

private enum RoomSheet: Identifiable {
    case review, source(RoomSource), welcome, protectedSources, scanIssues, history
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
        case .history: "history"
        #if ROOM_APP_STORE
        case .restore(let record): "restore-\(record.id)"
        #endif
        }
    }
}
