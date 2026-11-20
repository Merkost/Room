import Accessibility
import AppKit
import SwiftUI

private struct RoomOverviewArrivalGroup: ViewModifier {
    let visible: Bool
    let index: Int

    func body(content: Content) -> some View {
        content.roomReveal(visible, from: RoomTokens.Space.tight,
                           animation: RoomTokens.Motion.settle.delay(Double(index) * RoomTokens.Motion.settleStagger))
    }
}

struct RoomOverviewView: View {
    let insights: RoomInsightsModel
    let rooms: RoomRoomsModel
    let navigate: (RoomDestination) -> Void
    let refresh: () -> Void
    var cacheModel: RoomViewModel? = nil
    var editingRoom: UUID? = nil
    var showAllRooms: () -> Void = {}
    var restoreRecent: ((RoomActivity) -> Void)? = nil
    var animatesArrival = false
    @AppStorage(RoomOverviewPreferences.densityKey) private var density = RoomTokens.Density.calm
    @AppStorage(RoomOverviewPreferences.recentReceiptKey) private var showRecent = true
    @AppStorage(RoomOverviewStyle.preferenceKey) private var style = RoomOverviewStyle.dots
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }

    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage(RoomOverviewPreferences.roomsChapterKey) private var showRooms = true
    @AppStorage(RoomOverviewPreferences.greetingKey) private var greetByName = true
    @Environment(\.controlActiveState) private var controlActiveState
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var model = RoomOverviewModel()
    @State private var isActive = false
    @State private var arrived = false
    @State private var earlierHomeMap: RoomStoredTree?

    private struct Inputs: Equatable {
        let capacity: RoomVolumeCapacity?
        let sampledAt: Date?
        let goalBytes: Int64?
        let caches: RoomCachesCheck?
        let invalidatedAt: Date?
        let homeKinds: RoomHomeKinds?
        let mapActionAvailable: Bool
        let mapping: RoomOverviewMapping?
        let stoppedMapping: Bool
    }

    private var inputs: Inputs {
        let saved = cacheModel?.cachesCheckStore.invalidatedAt
        let known = cacheModel?.activity.first?.date
        let mapping: RoomOverviewMapping? = insights.isMappingHome ? RoomOverviewMapping(
            files: insights.diskProgress?.visitedFiles ?? 0, allocatedBytes: insights.diskProgress?.allocatedBytes ?? 0,
            finishedKinds: insights.homeMappingKinds) : nil
        return Inputs(capacity: insights.volumeCapacity, sampledAt: insights.diskCapacitySampledAt,
               goalBytes: goalEnabled ? Int64(storedGoal) : nil,
               caches: cacheModel?.cachesCheckStore.check, invalidatedAt: [saved, known].compactMap { $0 }.max(),
               homeKinds: insights.homeKinds, mapActionAvailable: insights.homeTree?.cancelled != false,
               mapping: mapping, stoppedMapping: insights.stoppedMappingHome)
    }

    var body: some View {
        let snapshot = presentedSnapshot
        let map = storageMapPlan(snapshot)
        VStack(alignment: .leading, spacing: density == .calm ? RoomTokens.Space.breath1 : RoomTokens.Space.group) {
            if let greeting = model.greeting {
                Text(greeting)
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            if let plan = snapshot.plan {
                RoomOverviewStoragePanel(volumeName: insights.volumeCapacity?.volumeName,
                    balance: .init(plan: plan, goal: goalEnabled ? Int64(storedGoal) : nil))
                    .modifier(arrivalGroup(0))
            }
            if snapshot.action != .usingSpaceOnly || map == nil {
                nextAction(snapshot)
                    .modifier(arrivalGroup(1))
            }
            if let plan = map {
                let returnedBytes = plan.homeKinds.map {
                    cacheModel?.makeRoomStore?.returnedBytes(since: $0.mappedAt) ?? 0
                } ?? 0
                RoomOverviewStorageMap(plan: plan, belowGoal: snapshot.state == .belowGoal, returnedBytes: returnedBytes,
                    hidden: hidden, density: density, solidKinds: style == .rooms, openDiskMap: openDiskMap,
                    isMapping: insights.isScanningDisk, isChoosingFolder: insights.isChoosingDiskFolder,
                    mapHome: insights.scanHome, mapAnotherFolder: insights.chooseDiskFolderAndOpenMap)
                    .modifier(arrivalGroup(2))
                    .roomPanelArrival(enabled: !animatesArrival || arrived)
            }
            let volumeHistory = insights.volumeHistory.log
            if snapshot.state != .firstRun, snapshot.state != .capacityUnreadable, volumeHistory.latest != nil {
                RoomOverviewHistoryLink(log: volumeHistory, goal: inputs.goalBytes,
                                        latestReceipt: cacheModel?.makeRoomStore?.latest,
                                        earlierMap: earlierHomeMap, currentMap: insights.homeTree)
            }
            if RoomOverviewPreferences(roomsChapterShown: showRooms)
                .showsRoomsChapter(roomCount: rooms.visibleRooms.count, allowsEmptyChapter: snapshot.state != .firstRun) {
                RoomChapterRooms(rooms: rooms, calendar: .current, editing: editingRoom, openRoom: openPinned,
                                 showAll: showAllRooms)
                    .modifier(arrivalGroup(3))
            }
            recentLine(standalone: true)
                .modifier(arrivalGroup(4))
        }
        .frame(maxWidth: 920, alignment: .leading)
        .frame(maxWidth: .infinity)
        .foregroundStyle(RoomTokens.Ink.graphite)
        .roomReveal(!animatesArrival || motion.isFull || arrived, animation: RoomTokens.Motion.fade)
        .task { arrived = true }
        .task(id: insights.homeTree?.scannedAt) {
            let earlier = await insights.previousHomeTreeForHistory()
            if !Task.isCancelled { earlierHomeMap = earlier }
        }
        .onChange(of: inputs, initial: true) { previous, updated in
            updateSnapshot(updated)
            if previous.sampledAt != nil, (previous.capacity == nil) != (updated.capacity == nil),
               scenePhase == .active {
                AccessibilityNotification.Announcement(presentedSnapshot.accessibilityAnswer).post()
            }
        }
        .onChange(of: controlActiveState, initial: true) { _, state in
            model.updateGreeting(enabled: greetByName, hidden: hidden, refreshName: state == .key)
        }
        .onChange(of: greetByName) { _, _ in
            model.updateGreeting(enabled: greetByName, hidden: hidden, refreshName: true)
        }
        .onChange(of: hidden) { _, _ in
            model.updateGreeting(enabled: greetByName, hidden: hidden, refreshName: true)
        }
        .task(id: scenePhase == .active ? model.nextGreetingUpdateAt : nil) {
            guard scenePhase == .active, let deadline = model.nextGreetingUpdateAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                model.updateGreeting(enabled: greetByName, hidden: hidden)
            } catch {}
        }
        .onAppear { updateCapacityMonitoring() }
        .task {
            await insights.refreshHomeMap()
            await insights.observeTreeChanges()
        }
        .onChange(of: scenePhase) { _, _ in
            updateCapacityMonitoring()
            if isActive {
                updateSnapshot(inputs)
                model.updateGreeting(enabled: greetByName, hidden: hidden)
            }
        }
        .task(id: isActive ? model.nextCacheUpdateAt : nil) {
            guard isActive, let deadline = model.nextCacheUpdateAt else { return }
            do {
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                }
                guard !Task.isCancelled else { return }
                updateSnapshot(inputs)
            } catch {
                return
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if isActive { updateSnapshot(inputs) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            if isActive { updateSnapshot(inputs) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == RoomApplicationDelegate.primaryWindowID else { return }
            updateCapacityMonitoring(in: window)
        }
        .onDisappear {
            isActive = false
            insights.setOverviewActive(false)
        }
    }

    private func storageMapPlan(_ snapshot: RoomOverviewSnapshot) -> RoomOverviewPlanInput? {
        guard let plan = snapshot.plan, plan.fitsDotBudget,
              plan.mapping != nil || !plan.kindValues.isEmpty || snapshot.state == .mappingStopped else { return nil }
        return plan
    }

    @ViewBuilder private func recentLine(standalone: Bool) -> some View {
        if showRecent, let cacheModel, let store = cacheModel.makeRoomStore,
           let entry = store.latest {
            let receipt = cacheModel.activity.first { $0.id == entry.id }
            let restore = receipt.flatMap { receipt in restoreRecent.map { action in { action(receipt) } } }
            RoomRecentOverviewLine(entry: entry, receipt: receipt, restore: restore, standalone: standalone)
        }
    }

    private var presentedSnapshot: RoomOverviewSnapshot {
        hidden ? model.snapshot.hidingSizes() : model.snapshot
    }

    private func updateSnapshot(_ inputs: Inputs) {
        model.update(capacity: inputs.capacity, goalBytes: inputs.goalBytes,
                     caches: inputs.caches, invalidatedAt: inputs.invalidatedAt, homeKinds: inputs.homeKinds,
                     mapActionAvailable: inputs.mapActionAvailable, mapping: inputs.mapping, stoppedMapping: inputs.stoppedMapping)
    }

    private func nextAction(_ snapshot: RoomOverviewSnapshot) -> some View {
        let copy = actionCopy(snapshot)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: RoomTokens.Space.breath1) {
                actionSummary(copy)
                Spacer(minLength: 0)
                actions(snapshot).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                actionSummary(copy)
                actions(snapshot)
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.popover))
    }

    private func actionSummary(_ copy: (title: String, detail: String, symbol: String)) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            RoomChangingSymbol(name: copy.symbol, color: accent.text)
                .font(RoomTokens.Typography.lead)
                .frame(width: RoomTokens.Space.breath2, height: RoomTokens.Space.breath2)
                .background(accent.wash, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title).font(RoomTokens.Typography.title).accessibilityHeading(.h2)
                RoomMaskable(copy.detail)
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
        .layoutPriority(1)
    }

    private func actionCopy(_ snapshot: RoomOverviewSnapshot) -> (title: String, detail: String, symbol: String) {
        switch snapshot.action {
        case .mapMac:
            if snapshot.state == .mappingStopped {
                return ("Mapping stopped", "Room kept the space it measured. Map again to update it.", "map")
            }
            return ("See what’s using space", "Map folders to see how their space is used. Your files stay in place.", "map")
        case .stopMapping:
            return ("Mapping storage", model.snapshot.sentence, "map")
        case .retryCapacity:
            return ("Storage unavailable", model.snapshot.sentence, "internaldrive")
        case .checkCaches, .makeRoom:
            return ("Rebuildable caches", model.cacheCaption ?? "See which caches your apps can rebuild.", "archivebox")
        case .usingSpaceOnly:
            return ("Explore your storage", model.snapshot.sentence, "map")
        }
    }

    private func arrivalGroup(_ index: Int) -> RoomOverviewArrivalGroup {
        RoomOverviewArrivalGroup(visible: !animatesArrival || !motion.isFull || arrived, index: index)
    }

    private func actions(_ snapshot: RoomOverviewSnapshot) -> some View {
        Group {
            switch snapshot.action {
            case .mapMac:
                Button(insights.isChoosingDiskFolder ? "Choosing a folder…" :
                       snapshot.state == .mappingStopped ? "Map again" : snapshot.actionTitle,
                       action: insights.scanHome)
                    .roomScreenPrimary(accent)
                    .disabled(insights.isChoosingDiskFolder)
            case .stopMapping:
                Button(snapshot.actionTitle, action: insights.cancelDiskScan).roomSecondary()
            case .retryCapacity:
                link(snapshot.actionTitle, accessibilityLabel: snapshot.accessibilityAction, action: retryCapacity)
                    .transition(.opacity)
            case .checkCaches, .makeRoom:
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    cacheButton(snapshot)
                    if snapshot.mapLinkAvailable {
                        link(RoomOverviewCopy.mapMac, accessibilityLabel: RoomOverviewCopy.mapMac, action: insights.scanHome)
                    } else if storageMapPlan(snapshot) == nil {
                        link("Open Disk Map", accessibilityLabel: RoomOverviewCopy.usingSpaceAccessibility, action: openDiskMap)
                    }
                }
                .transition(.opacity)
            case .usingSpaceOnly:
                usingSpaceLink
                    .transition(.opacity)
            }
        }
        .animation(motion.animation(RoomTokens.Motion.fade), value: snapshot.action)
    }

    private func cacheButton(_ snapshot: RoomOverviewSnapshot) -> some View {
        Button {
            if snapshot.action == .checkCaches { openCaches() }
            else { navigate(.clean) }
        } label: {
            Text(snapshot.actionTitle)
                .font(RoomTokens.Typography.section)
        }
        .roomScreenPrimary(accent)
        .accessibilityLabel(snapshot.accessibilityAction)
        .accessibilityIdentifier("RoomOverviewCachesAction")
    }

    private var usingSpaceLink: some View {
        link(RoomOverviewCopy.usingSpace, accessibilityLabel: RoomOverviewCopy.usingSpaceAccessibility, action: openDiskMap)
    }

    private func link(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(RoomTokens.Typography.body)
                .frame(minWidth: RoomTokens.Space.breath1, minHeight: RoomTokens.Space.breath1)
        }
        .roomLink(accent)
        .accessibilityLabel(accessibilityLabel)
    }

    private func openPinned(_ url: URL) {
        if let room = rooms.rooms.first(where: { rooms.url(for: $0.id) == url }) {
            insights.requestedPinnedRoom = room.id
        }
    }

    func openCaches() {
        navigate(.clean)
        cacheModel?.scan()
    }

    func openDiskMap() { navigate(.disk) }

    func retryCapacity() { refresh() }

    private func updateCapacityMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let windowVisible = primary?.occlusionState.contains(.visible) ?? true
        isActive = scenePhase == .active && windowVisible
        insights.setOverviewActive(isActive)
    }
}
