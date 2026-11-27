import AppKit
import SwiftUI

/// Overview's words, kept pure: the headline, the goal distance and the three next steps.
nonisolated struct RoomOverviewWords: Equatable, Sendable {
    let headline: RoomHeadline
    let supporting: String?
    let note: String

    static func make(freeBytes: Int64?, capacityBytes: Int64?, goalBytes: Int64?, cachesChecked: Bool,
                     change: RoomVolumeChange) -> RoomOverviewWords {
        let headline: RoomHeadline = freeBytes.map { RoomHeadline(figure: RoomFormat.gb($0), words: "free") }
            ?? .words("Free space unavailable")
        var supporting: String?
        if let free = freeBytes, let capacity = capacityBytes {
            var line = "of \(RoomFormat.gb(capacity))"
            if let goal = goalBytes {
                if free >= goal {
                    line += free - goal >= 1_000_000_000 ? ", \(RoomFormat.gb(free - goal)) above your goal" : ", right at your goal"
                } else {
                    line += ", \(RoomFormat.gb(goal - free)) below your goal"
                }
            }
            supporting = line
        }
        let note: String = switch change {
        case .since(let label, let used) where abs(used) >= 1_000_000_000:
            used < 0 ? "\(RoomFormat.gb(-used)) more free than \(label)" : "\(RoomFormat.gb(used)) less free than \(label)"
        case .since(let label, _):
            "About the same as \(label)"
        case .tracking, .volumeChanged:
            cachesChecked ? "Nothing moves without a review" : "A scan only reads. Nothing moves."
        }
        return RoomOverviewWords(headline: headline, supporting: supporting, note: note)
    }
}

/// What the dock offers on Overview: scan everything, stop the scan, or make room with a second way to scan again.
nonisolated struct RoomOverviewDock: Equatable, Sendable {
    enum Step: Equatable, Sendable { case scan, stop, makeRoom(bytes: Int64) }
    let main: Step
    var rescan = false

    /// `makeRoomBytes` is what the review will open with.
    static func make(scanning: Bool, makeRoomBytes: Int64) -> RoomOverviewDock {
        if scanning { return RoomOverviewDock(main: .stop) }
        guard makeRoomBytes > 0 else { return RoomOverviewDock(main: .scan) }
        return RoomOverviewDock(main: .makeRoom(bytes: makeRoomBytes), rescan: true)
    }
}

/// Overview: "64 GB free", the goal distance, this Mac's meter and a floor plan of kinds.
struct RoomOverviewScreen: View {
    let insights: RoomInsightsModel
    let navigate: (RoomDestination) -> Void
    let refresh: () -> Void
    var cacheModel: RoomViewModel? = nil
    var developerBytes: Int64? = nil
    var makeRoom: () -> Void = {}
    var scan: RoomScanEverything? = nil

    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion

    private var capacity: RoomVolumeCapacity? { insights.volumeCapacity }
    private var cachesChecked: Bool { cacheModel?.hasReport == true }
    private var cachesBytes: Int64 { cachesChecked ? (cacheModel?.clearableBytes ?? 0) : 0 }
    private var makeRoomBytes: Int64 {
        guard cachesBytes > 0, let model = cacheModel else { return 0 }
        return model.selectedBytes > 0 ? model.selectedBytes : cachesBytes
    }

    private var words: RoomOverviewWords {
        RoomOverviewWords.make(freeBytes: capacity?.freeBytes, capacityBytes: capacity?.capacityBytes,
                               goalBytes: goalEnabled ? RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal)) : nil,
                               cachesChecked: cachesChecked,
                               change: insights.volumeHistory.log.change(now: Date(), calendar: .current))
    }

    private var plan: RoomOverviewFloorPlan {
        let kinds = insights.homeKinds
        return RoomOverviewFloorPlan.make(kinds: kinds?.kinds, notMappedBytes: kinds?.notMappedBytes ?? 0,
                                          freeBytes: capacity?.freeBytes ?? 0, capacityBytes: capacity?.capacityBytes ?? 0)
    }

    private var isScanShowing: Bool { scan?.isPresented == true }
    var body: some View {
        let words = words
        let tiles = isScanShowing ? scan?.tiles ?? [] : []
        let running = scan?.isRunning == true
        RoomScreenFrame(headline: isScanShowing ? .words(running ? "Reading your Mac" : "Scan finished") : words.headline,
                        supporting: isScanShowing ? RoomScanTile.progress(tiles) : words.supporting,
                        supportingMasked: !isScanShowing,
                        note: isScanShowing ? "A scan only reads. Nothing moves." : words.note) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                if isScanShowing {
                    RoomScanBoard(tiles: tiles) { id in
                        if let destination = Self.destination(id) { navigate(destination) }
                    }
                    .transition(.opacity)
                } else if let capacity {
                    RoomVolumeMeter(freeBytes: capacity.freeBytes, capacityBytes: capacity.capacityBytes,
                                    couldGoBytes: cachesBytes)
                    RoomOverviewFloorPlanView(plan: plan, prompt: mapPrompt)
                } else {
                    Button("Read free space again", action: retryCapacity).roomLink(accent)
                }
            }
        } action: {
            EmptyView()
        }
        .roomDock(dockMain(running: running), side: dockSide(running: running))
        .animation(motion.animation(RoomTokens.Motion.page, fallback: RoomTokens.Motion.fade), value: isScanShowing)
        .animation(motion.animation(RoomTokens.Motion.fade), value: running)
        .onAppear { updateCapacityMonitoring() }
        .task {
            await insights.refreshHomeMap()
            await insights.observeTreeChanges()
        }
        .onChange(of: scenePhase) { _, _ in updateCapacityMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == RoomApplicationDelegate.primaryWindowID else { return }
            updateCapacityMonitoring(in: window)
        }
        .onDisappear { insights.setOverviewActive(false) }
    }

    /// The Used room, unmapped, holds the way to fill it.
    private var mapPrompt: RoomOverviewFloorPlanView.Prompt? {
        guard insights.homeKinds == nil else { return nil }
        return .init(title: insights.isScanningDisk ? "Mapping your home folder…" : "Map your home folder to see what fills it",
                     disabled: insights.isScanningDisk || insights.isChoosingDiskFolder) { insights.scanHome() }
    }

    private func dockMain(running: Bool) -> RoomDockAction {
        switch RoomOverviewDock.make(scanning: running, makeRoomBytes: isScanShowing ? 0 : makeRoomBytes).main {
        case .stop:
            let asked = (scan?.tiles ?? []).filter { $0.state != .skipped }
            return RoomDockAction(title: "Stop", filled: false, identifier: "RoomOverviewScanButton",
                                  progress: .init(done: asked.filter { $0.state == .done }.count, total: asked.count)) {
                scan?.stop()
            }
        case .scan:
            return RoomDockAction(title: "Scan everything", symbol: "magnifyingglass", hint: "A scan only reads",
                                  identifier: "RoomOverviewScanButton", perform: scanEverything)
        case .makeRoom(let bytes):
            return RoomDockAction(title: "Make room \(RoomCachesVisibility.figure(RoomFormat.gb(bytes), hidden: hide.masksNow))",
                                  enabled: cacheModel?.isScanning != true && cacheModel?.isWorking != true,
                                  hint: "Opens a review before anything moves",
                                  identifier: "RoomOverviewMakeRoom", perform: makeRoom)
        }
    }

    private func dockSide(running: Bool) -> RoomDockAction? {
        guard RoomOverviewDock.make(scanning: running, makeRoomBytes: isScanShowing ? 0 : makeRoomBytes).rescan else { return nil }
        return RoomDockAction(title: "Scan everything", identifier: "RoomOverviewScanButton", perform: scanEverything)
    }

    static func destination(_ tile: String) -> RoomDestination? {
        switch RoomScanEverything.Part(rawValue: tile) {
        case .caches: .clean
        case .disk: .disk
        case .developer: .developer
        case .memory: .memory
        case nil: nil
        }
    }

    func scanEverything() { scan?.start() }

    func openDiskMap() { navigate(.disk) }

    func retryCapacity() { refresh() }

    private func updateCapacityMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let windowVisible = primary?.occlusionState.contains(.visible) ?? true
        insights.setOverviewActive(scenePhase == .active && windowVisible)
    }
}

/// When a screen plays its arrival (headline and evidence fade up): pointer or programmatic visits, never keyboard,
/// never under the welcome, once per launch for Overview (REVIEW §4.1).
nonisolated enum RoomOverviewArrival {
    static func plays(origin: RoomSelectionOrigin, needsWelcome: Bool, hasLeftOverview: Bool) -> Bool {
        origin != .keyboard && !needsWelcome && !hasLeftOverview
    }
}
