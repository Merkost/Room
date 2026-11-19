import Accessibility
import AppKit
import CoreText
import SwiftUI

struct RoomOverviewView: View {
    let insights: RoomInsightsModel
    let rooms: RoomRoomsModel
    let navigate: (RoomDestination) -> Void
    let refresh: () -> Void
    var cacheModel: RoomViewModel? = nil
    var editingRoom: UUID? = nil
    var showAllRooms: () -> Void = {}
    var restoreRecent: ((RoomActivity) -> Void)? = nil
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
        VStack(alignment: .leading, spacing: density.betweenChapters) {
            VStack(alignment: .leading, spacing: density.betweenGroups) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    if let greeting = model.greeting {
                        Text(greeting)
                            .font(RoomTokens.Typography.lead)
                            .lineHeight(.exact(points: RoomTokens.Overview.greetingLineHeight))
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    answerGroup(snapshot)
                }
                if let plan = snapshot.plan, plan.fitsDotBudget {
                    RoomDotPlanView(plan: plan, belowGoal: snapshot.state == .belowGoal, hidden: hidden,
                                    density: density, solidKinds: style == .rooms, openDiskMap: openDiskMap)
                }
                actions(snapshot)
                if snapshot.mapLinkAvailable {
                    link(RoomOverviewCopy.mapMac, accessibilityLabel: RoomOverviewCopy.mapMac, action: insights.scanHome)
                }
                if let caption = model.cacheCaption {
                    RoomMaskable(caption)
                        .font(RoomTokens.Typography.body)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            .frame(minHeight: density.firstScreenMinHeight, alignment: .topLeading)
            if showRooms && (!rooms.visibleRooms.isEmpty || rooms.canChooseFolder) {
                VStack(alignment: .leading, spacing: density.insideChapter) {
                    RoomChapterRooms(rooms: rooms, calendar: .current, editing: editingRoom, openRoom: openPinned,
                                     showAll: showAllRooms)
                    recentLine(standalone: false)
                }
            } else {
                recentLine(standalone: true)
            }
        }
        .frame(maxWidth: density.planSize.width, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(RoomTokens.Ink.graphite)
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

    @ViewBuilder private func recentLine(standalone: Bool) -> some View {
        if showRecent, let cacheModel, let store = cacheModel.makeRoomStore,
           store.hasReadReceipts || store.latest != nil {
            let entry = store.latest
            let receipt = cacheModel.activity.first { $0.id == entry?.id }
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

    private func answerGroup(_ snapshot: RoomOverviewSnapshot) -> some View {
        let answer = RoomMaskable(model.snapshot.answer, spoken: model.snapshot.accessibilityAnswer)
            .font(RoomTokens.Typography.hero)
            .tracking(RoomTokens.Typography.heroTracking)
            .lineHeight(.exact(points: RoomTokens.Overview.answerLineHeight))
        return VStack(alignment: .leading, spacing: RoomTokens.Overview.goalSpacing) {
            ViewThatFits(in: .horizontal) {
                answer.fixedSize(horizontal: true, vertical: false)
                RoomOverviewWrappedAnswer {
                    answer.fixedSize(horizontal: false, vertical: true)
                }
            }
            RoomMaskable(model.snapshot.sentence)
                .font(RoomTokens.Typography.lead.monospacedDigit())
                .lineHeight(.exact(points: RoomTokens.Overview.goalLineHeight))
                .foregroundStyle(snapshot.state == .belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .focusable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilityAnswer)
        .accessibilityHeading(.h1)
    }

    private func actions(_ snapshot: RoomOverviewSnapshot) -> some View {
        Group {
            switch snapshot.action {
            case .mapMac:
                Button(snapshot.actionTitle, action: insights.scanHome).roomPrimary(accent)
            case .stopMapping:
                Button(snapshot.actionTitle, action: insights.cancelDiskScan).roomSecondary()
            case .retryCapacity:
                link(snapshot.actionTitle, accessibilityLabel: snapshot.accessibilityAction, action: retryCapacity)
                    .transition(.opacity)
            case .checkCaches, .makeRoom:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RoomTokens.Overview.actionSpacing) {
                        cacheButton(snapshot).fixedSize()
                        usingSpaceLink.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                        cacheButton(snapshot)
                        usingSpaceLink
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
        Button(action: openCaches) {
            Text(snapshot.actionTitle)
                .font(RoomTokens.Typography.section)
        }
        .roomPrimary(accent)
        .frame(minHeight: RoomTokens.Overview.actionHeight)
        .accessibilityLabel(snapshot.accessibilityAction)
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

    func openCaches() { navigate(.clean) }

    func openDiskMap() { navigate(.disk) }

    func retryCapacity() { refresh() }

    private func updateCapacityMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let windowVisible = primary?.occlusionState.contains(.visible) ?? true
        isActive = scenePhase == .active && windowVisible
        insights.setOverviewActive(isActive)
    }
}

/// Finds the narrowest width that still fits the two-line answer.
/// Longer translations keep their natural wrapping at the full measure.
private nonisolated struct RoomOverviewWrappedAnswer: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let text = subviews[0]
        let ideal = text.sizeThatFits(.unspecified)
        guard let width = proposal.width, width < ideal.width else { return ideal }
        let wrapped = text.sizeThatFits(ProposedViewSize(width: width, height: nil))
        guard wrapped.height > ideal.height, wrapped.height <= 2 * ideal.height else { return wrapped }

        var lower = min(ideal.width / 2, width)
        var upper = width
        while upper - lower > 1 {
            let trial = (lower + upper) / 2
            let size = text.sizeThatFits(ProposedViewSize(width: trial, height: nil))
            if size.height <= wrapped.height, size.width <= trial {
                upper = trial
            } else {
                lower = trial
            }
        }
        return CGSize(width: upper, height: wrapped.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
