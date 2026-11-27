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
    /// Screens drawn with `RoomScreenFrame` (headline, evidence, footer) manage their own scrolling.
    static let framedDestinations: Set<RoomDestination> = [.overview, .clean, .memory, .developer, .disk, .history, .settings]
    @State private var rowActivity = RoomPlaceActivity()
    /// Make room: the bytes the review chose (for "Moving 7 of 22 GB") and the toast after it lands.
    @State private var makeRoomTotal: Int64 = 0
    @State private var madeToast: RoomMadeToastState?
    @State private var folderTrash = RoomFolderTrashModel()
    @State private var showsGoTo = false
    /// The cleanup review, drawn in the window over a scrim (mockup `.sheet`).
    @State private var review: RoomReviewKind?
    @State private var reviewByKeyboard = false
    @State private var goToByKeyboard = false
    @State private var scanEverything = RoomScanEverything()

    private var commandItems: [RoomCommandBar.Item] {
        RoomCommandBar.items(values: dockValues, developerRooms: RoomDeveloperSection.allCases.map(\.rawValue))
    }

    /// Every receipt: cache moves and, in Direct, folders moved from the Disk Map.
    private var allActivity: [RoomActivity] { (model.activity + folderTrash.activity).sorted { $0.date > $1.date } }
    @State private var toastTask: Task<Void, Never>?

    private var isMakingRoom: Bool { model.isWorking && !model.cleanupProgress.isEmpty }
    private var makeRoomMoved: Int64 { RoomMakeRoomProgress.movedBytes(model.cleanupProgress, totalBytes: makeRoomTotal) }

    /// What each engine is doing, for the sidebar rows (ring, sentence, counted dots, finished, failed).
    private var rowSignals: [RoomDestination: RoomRowSignal] {
        [.overview: RoomRowSignals.makeRoom(isMoving: isMakingRoom, movedBytes: makeRoomMoved, totalBytes: makeRoomTotal,
                                            madeBytes: model.movedReceipt?.bytes,
                                            failed: RoomMakeRoomProgress.failed(model.cleanupProgress)),
         .clean: RoomRowSignals.caches(isScanning: model.isScanning, checked: model.scannedLocationCount,
                                       of: model.scanLocationCount, clearableBytes: model.clearableBytes,
                                       unreadable: model.scanIssues.count),
         .developer: RoomRowSignals.developer(isScanning: developer.isScanning, progress: developer.progress,
                                              totalBytes: developer.headline.total,
                                              projects: developer.report?.projects.count ?? 0,
                                              error: developer.errorMessage),
         .disk: RoomRowSignals.diskMap(isScanning: insights.isScanningDisk,
                                       mapped: insights.diskMap.blueprint?.measuredCount ?? 0,
                                       of: insights.diskProgress?.topLevelTotal)]
    }

    private func stopPlace(_ place: RoomDestination) {
        switch place {
        case .clean: model.cancelScan()
        case .developer: developer.stop()
        case .disk: insights.cancelDiskScan()
        default: return
        }
        rowActivity.stop(place)
    }

    private var dockValues: RoomPlaceValue.Input {
        RoomPlaceValue.Input(freeBytes: insights.volumeCapacity?.freeBytes,
                               mappedBytes: insights.diskMap.current?.tree.allocatedBytes,
                               cachesChecked: model.hasReport && !model.isScanning,
                               cachesReclaimableBytes: model.clearableBytes,
                               developerBytes: developerHeadlineBytes,
                               memoryUsedBytes: insights.memoryReport?.usedBytes,
                               receipts: allActivity.count)
    }

    /// The Developer row shows the figure the Developer screen's headline shows for the room it opens on.
    private var developerHeadlineBytes: Int64 {
        #if ROOM_APP_STORE
        developer.headlineBytes(for: developer.section)
        #else
        developer.headlineBytes(for: developer.section,
                                worktreesBytes: agentWork.report?.items.reduce(Int64(0)) { $0 + $1.allocatedBytes } ?? 0)
        #endif
    }

    /// What Make room would give back: the cache moves a completed check found eligible.
    private var couldGoBytes: Int64 {
        guard model.hasReport else { return 0 }
        return max(0, model.clearableBytes - (isMakingRoom ? makeRoomMoved : 0))
    }
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    private var screenActions: RoomScreenActions {
        var commands = destinationActions
        commands.showHistory = { navigation.select(.screen(.history), origin: .controlActivation) }
        commands.openGoTo = { openGoTo(keyboard: true) }
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
        case .history: RoomScreenActions(destination: .history)
        case .settings: RoomScreenActions(destination: .settings)
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
        RoomShellView(navigation: navigation, insights: insights, dockValues: dockValues,
                      activity: rowActivity.rows, stopPlace: stopPlace,
                      openGoTo: { openGoTo(keyboard: $0) }) {
            RoomScreenScaffold(title: screenActions.title, subtitle: screenSubtitle,
                               scrolls: !Self.framedDestinations.contains(destination), chip: AnyView(topBar)) {
                screenContent
                    .environment(\.roomEnter, RoomEnterContext(animated: navigation.selectionOrigin == .pointer,
                                                                at: navigation.changedAt))
            }
            .overlay {
                if let madeToast, !madeToast.restored {
                    RoomReceiptDots().id(madeToast.receiptID)
                }
            }
            .overlay(alignment: .bottom) {
                if let madeToast {
                    RoomMadeToast(state: madeToast,
                                  canRestore: allActivity.first { $0.id == madeToast.receiptID }?.canRestore == true
                                    && !model.isWorking && !model.isScanning,
                                  restore: restoreFromToast)
                        .padding(.bottom, RoomTokens.Screen2.toastBottom)
                        .transition(.roomToast(motion))
                }
            }
            .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: madeToast)
        }
        .overlay {
            if showsGoTo {
                RoomCommandBarView(items: commandItems, close: { closeGoTo(keyboard: true) }, run: runCommand,
                                   animated: !goToByKeyboard)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(colorScheme)
        .focusedSceneValue(\.roomScreen, screenActions)
        .roomSheetOverlay(isPresented: review != nil, animated: !reviewByKeyboard) {
            switch review {
            case .caches:
                RoomCleanupReviewSheet(model: model, close: closeReview)
            case .map(let context):
                RoomCleanupReviewSheet(model: model, mapCleanup: context.request, canAccessMapCleanup: {
                    canAccessMapCleanup(context)
                }, close: closeReview)
            case nil:
                EmptyView()
            }
        }
        .sheet(item: $sheet, onDismiss: performOnboardingFollowUp) { selected in
            switch selected {
            case .review, .mapCleanup: EmptyView()
            case .source(let source): RoomSourceSheet(source: source, model: model)
            case .welcome:
                RoomOnboardingView(capacity: insights.volumeCapacity, isWorking: isOnboardingBusy(),
                                   needsPicker: !insights.hasRememberedHomeAccess, onFinish: finishWelcome)
                    .modifier(RoomMotionRoot())
                    .modifier(RoomAccentRoot())
                    .preferredColorScheme(colorScheme)
            case .protectedSources: RoomWhatStaysSheet(model: model)
            case .scanIssues: RoomScanIssuesSheet(issues: model.scanIssues)
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
        .onAppear { scanEverything.sources = RoomScanEverything.sources(cache: model, insights: insights, developer: developer) }
        .onAppear {
            #if !ROOM_APP_STORE
            developer.worktrees = agentWork
            #endif
            if navigation.needsWelcome { sheet = .welcome }
        }
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
            if let place = route.highlightedScreen { rowActivity.open(place) }
            RoomHideControl.shared.cancelPeek()
            guard case .room(let id) = route, let url = rooms.url(for: id) else { return }
            insights.openDiskMap(rootURL: url, requestNavigation: false)
        }
        .task { await savedViews.load() }
        .modifier(RoomNavObservers(observe: observeNavigation))
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

    private var topBar: some View {
        HStack(spacing: RoomTokens.Space.row) {
            statusChip
            RoomTopBarActions(model: model, destination: destination,
                              openGoTo: { openGoTo(keyboard: RoomSelectionOrigin.controlActivation == .keyboard) },
                              show: { navigation.select(.screen($0), origin: RoomSelectionOrigin.controlActivation) },
                              restore: restoreFromCaches)
        }
    }

    /// The bar's status chip (mockup `.chip`): "Up to date" or "Working", with its activity popover. Customise Overview
    /// (View menu, ⌥⌘C) opens from here now that the toolbar is gone.
    private var statusChip: some View {
        RoomActivityPill(stop: stopActivity, restore: restoreActivity,
                         showHistory: { navigation.select(.screen(.history), origin: .controlActivation) },
                         prefersQuietIdleLabel: true)
            .popover(isPresented: $showingCustomise, arrowEdge: .bottom) {
                RoomCustomisePopover(rooms: rooms, capacityBytes: insights.volumeCapacity?.capacityBytes ?? 210_000_000_000,
                    selected: $editingRoom, hidden: hide.masksNow,
                    canChoosePlanStyle: RoomOverviewStyle.isAvailable(homeKinds: insights.homeKinds),
                    hasRecentReceipts: model.makeRoomStore != nil)
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
        case .developer: developer.section.rawValue   // the mockup's crumb: Developer › Rooms
        case .clean, .memory, .history, .settings: nil
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
            RoomOverviewScreen(insights: insights,
                               navigate: { navigation.select(.screen($0), origin: .controlActivation) },
                               refresh: insights.refreshDiskCapacity, cacheModel: model,
                               developerBytes: developer.headline.total, makeRoom: startMakeRoom, scan: scanEverything)
        case .clean:
            RoomCachesView(model: model, review: { openReview(.caches) },
                inspect: { sheet = .source($0) }, showKept: { sheet = .protectedSources },
                showScanNotes: { sheet = .scanIssues }, restore: restoreFromCaches,
                agentWorktreeBytes: heavyAgentWorktreeBytes, reviewWorktrees: reviewAgentWorktrees)
                .roomPanelArrival(enabled: navigation.selectionOrigin == .pointer, from: RoomTokens.Space.tight)
        case .memory:
            RoomMemoryView(insights: insights, memoryActions: memoryActions)
        case .disk:
            RoomPinnedChips(navigation: navigation, rooms: rooms, canOpenRooms: insights.canChooseDiskLocation,
                            openRoom: openPinnedRoom, savedViews: savedViews, openSavedView: openSavedView)
            RoomDiskMapView(insights: insights, rooms: rooms, savedViews: savedViews,
                savedViewDisplay: savedViewDisplay, openSavedView: openSavedView,
                canInspectCacheSource: { cacheSource(for: $0) != nil },
                inspectCacheSource: inspectCacheSource, cleanupAction: mapCleanupAction,
                activateCleanup: activateMapCleanup,
                folderTrash: RoomFolderTrashModel.isAvailable ? folderTrash : nil,
                folderMoved: { receipt in
                    if receipt.canRestore { showToast(RoomMadeToastState(receiptID: receipt.id, bytes: receipt.trashedBytes)) }
                })
        case .developer:
            #if ROOM_APP_STORE
            RoomDeveloperView(model: developer)
            #else
            RoomDeveloperView(model: developer, agentWork: agentWork, memoryReport: insights.memoryReport)
            #endif
        case .history:
            RoomHistoryScreen(model: model, restore: restoreReceipt, extraActivity: folderTrash.activity)
        case .settings:
            RoomSettingsScreen(openAllSettings: { openSettings() })
        }
    }

    /// Heavy agent worktrees for the Caches line; Store has no Worktrees view, so no line.
    private var heavyAgentWorktreeBytes: Int64? {
        #if ROOM_APP_STORE
        nil
        #else
        RoomAgentWorktreeHint.suggestedBytes(scanned: RoomAgentWorktreeHint.scannedBytes(agentWork.report),
            measured: RoomAgentWorktreeHint.measuredBytes(model.protectedSources.map { ($0.id, $0.bytes) }))
        #endif
    }

    private var reviewAgentWorktrees: (() -> Void)? {
        #if ROOM_APP_STORE
        nil
        #else
        {
            developer.section = .worktrees
            navigation.select(.screen(.developer), origin: .controlActivation)
        }
        #endif
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
                openReview(.map(RoomMapCleanupContext(request: request, target: target, route: navigation.route,
                                                      approvalID: folder.id)))
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

    /// The nav-v3 observers (row signals, Make room, toast, one cleanup at a time), split from `body` so the
    /// type checker keeps up in both editions.
    private func observeNavigation<Content: View>(_ content: Content) -> some View {
        content
            .task {
            // One cleanup at a time: folder moves wait for cache moves and restores, and the other way round.
            folderTrash.otherCleanupBusy = { [model] in model.working }
            if RoomFolderTrashModel.isAvailable { await folderTrash.load() }
        }
            .onChange(of: folderTrash.isMoving) { _, moving in model.externalCleanupBusy = moving }
            .onChange(of: isMakingRoom) { _, moving in
            if moving { makeRoomTotal = model.selectedBytes }
        }
            .onChange(of: model.movedReceiptID) { old, new in
            guard let new, new != old, let receipt = model.activity.first(where: { $0.id == new }) else { return }
            showToast(RoomMadeToastState(receiptID: receipt.id, bytes: receipt.bytes))
        }
            .onChange(of: rowSignals, initial: true) { _, signals in
            rowActivity.update(signals, open: navigation.route.highlightedScreen)
        }
    }

    private func openReview(_ kind: RoomReviewKind) {
        reviewByKeyboard = RoomSelectionOrigin.controlActivation == .keyboard
        review = kind
    }

    private func closeReview() {
        reviewByKeyboard = RoomSelectionOrigin.controlActivation == .keyboard
        review = nil
    }

    /// Make room: the review sheet in front of every move, with the recommended places chosen.
    private func startMakeRoom() {
        guard !model.isScanning, !model.isWorking, model.hasReport else { return }
        if !model.canReviewCleanup { model.selectRecommended() }
        if model.canReviewCleanup { openReview(.caches) }
    }

    private func restoreFromCaches(_ record: RoomActivity) {
        #if ROOM_APP_STORE
        sheet = .restore(record)
        #else
        Task { await model.restore(record: record) }
        #endif
    }

    /// Go to opens instantly from the keyboard and with the UI spring from the pointer.
    private func openGoTo(keyboard: Bool) {
        goToByKeyboard = keyboard
        let animation = keyboard ? nil : motion.animation(RoomTokens.Motion.scrim, fallback: RoomTokens.Motion.fade)
        withAnimation(animation) { showsGoTo.toggle() }
    }

    private func closeGoTo(keyboard: Bool) {
        let animation = keyboard ? nil : motion.animation(RoomTokens.Motion.quick, fallback: RoomTokens.Motion.fade)
        withAnimation(animation) { showsGoTo = false }
    }

    private func runCommand(_ item: RoomCommandBar.Item, keyboard: Bool) {
        closeGoTo(keyboard: keyboard)
        let origin: RoomSelectionOrigin = keyboard ? .keyboard : .pointer
        func go(_ place: RoomDestination) {
            if keyboard {
                navigation.select(.screen(place), origin: origin)
            } else {
                withAnimation(RoomDock.selectionAnimation(origin: origin, motion: motion)) {
                    navigation.select(.screen(place), origin: origin)
                }
            }
        }
        switch item.target {
        case .place(let place): go(place)
        case .developerRoom(let name):
            go(.developer)
            if let section = RoomDeveloperSection(rawValue: name) { developer.section = section }
        case .action(.checkCaches):
            go(.clean)
            if model.canScan, !model.isScanning { model.scan() }
        case .action(.makeRoom):
            go(.overview)
            startMakeRoom()
        case .action(.scanProjects):
            go(.developer)
            if developer.canScan, !developer.isScanning { developer.scan() }
        case .action(.hideSizes):
            RoomHideControl.shared.toggle()
        }
    }

    /// Six seconds, then the toast leaves; History keeps the receipt.
    private func showToast(_ state: RoomMadeToastState, for duration: Duration = RoomTokens.Screen2.toastHold) {
        toastTask?.cancel()
        madeToast = state
        toastTask = Task {
            do { try await Task.sleep(for: duration) } catch { return }
            madeToast = nil
        }
    }

    /// Restore routes by owner: Disk Map folder receipts go back through their own engine, cache receipts through
    /// the cache receipt engine (Store opens its exact-item restore sheet).
    private func restoreReceipt(_ receipt: RoomActivity) {
        Task { _ = await restoreAndDescribe(receipt) }
    }

    /// Restores through the receipt's own engine and says what actually happened. Store hands off to its restore
    /// sheet (exact Trash-item approval), so there is no result to report yet.
    private func restoreAndDescribe(_ receipt: RoomActivity) async -> String? {
        if folderTrash.owns(receipt.id) { return await folderTrash.restore(receipt.id) }
        #if ROOM_APP_STORE
        sheet = .restore(receipt)
        return nil
        #else
        await model.restore(record: receipt)
        guard let after = model.activity.first(where: { $0.id == receipt.id }) else { return nil }
        return RoomMadeToastState.cacheOutcome(itemCount: after.itemCount, restoredCount: after.restoredCount,
                                               stillRestorable: after.canRestore)
        #endif
    }

    private func restoreFromToast() {
        guard let toast = madeToast, let receipt = allActivity.first(where: { $0.id == toast.receiptID }),
              receipt.canRestore, !toast.restored, !model.isScanning, !model.isWorking else { return }
        var restoring = toast
        restoring.restored = true
        showToast(restoring)
        Task {
            let outcome = await restoreAndDescribe(receipt)
            var done = restoring
            done.outcome = outcome ?? "Review the restore to put it back"
            showToast(done, for: outcome == "Put back" ? .seconds(2) : RoomTokens.Screen2.toastHold)
        }
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
        case .reviewAgain: if model.canReviewCleanup { openReview(.caches) }
        case .showSkipped, .showWhy: navigation.select(.screen(.history), origin: .programmatic)
        case .showInTrash: model.openTrash()
        case .ok: break
        }
    }
}

private enum RoomReviewKind: Equatable {
    case caches
    case map(RoomMapCleanupContext)
    static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.caches, .caches): true
        case (.map(let x), .map(let y)): x.request == y.request
        default: false
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
    case review, source(RoomSource), welcome, protectedSources, scanIssues
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
        #if ROOM_APP_STORE
        case .restore(let record): "restore-\(record.id)"
        #endif
        }
    }
}

private struct RoomNavObservers<Observed: View>: ViewModifier {
    let observe: (AnyView) -> Observed
    func body(content: Content) -> some View { observe(AnyView(content)) }
}
