import AppKit
import SwiftUI

/// Overview's words, kept pure: the headline, the goal distance and the three next steps.
nonisolated struct RoomOverviewWords: Equatable, Sendable {
    struct Fact: Equatable, Sendable {
        let label: String
        let value: String
        let destination: RoomDestination
        var masked = true
    }

    let headline: RoomHeadline
    let supporting: String?
    let note: String
    let facts: [Fact]

    static func make(freeBytes: Int64?, capacityBytes: Int64?, goalBytes: Int64?, cachesChecked: Bool, cachesBytes: Int64,
                     developerBytes: Int64?, change: RoomVolumeChange) -> RoomOverviewWords {
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
        let note = cachesChecked
            ? (cachesBytes > 0 ? "\(RoomFormat.gb(cachesBytes)) of caches are safe to move" : "Nothing else is safe to move today")
            : "Check caches to see what can safely go"

        let caches = Fact(label: "Caches",
                          value: cachesChecked ? (cachesBytes > 0 ? "\(RoomFormat.gb(cachesBytes)) could go" : "All clear") : "Not checked yet",
                          destination: .clean)
        let developer = Fact(label: "Developer",
                             value: (developerBytes ?? 0) > 0 ? "\(RoomFormat.gb(developerBytes!)) in your tools" : "Not scanned yet",
                             destination: .developer)
        let since: Fact = switch change {
        case .since(let label, let used):
            Fact(label: "Since \(label)",
                 value: abs(used) < 1_000_000_000 ? "About the same" : used < 0 ? "\(RoomFormat.gb(-used)) more free" : "\(RoomFormat.gb(used)) less free",
                 destination: .history)
        case .tracking, .volumeChanged:
            Fact(label: "This week", value: "Counting from today", destination: .history, masked: false)
        }
        return RoomOverviewWords(headline: headline, supporting: supporting, note: note, facts: [caches, developer, since])
    }
}

/// Overview (nav-v3): "64 GB free", the goal distance, a floor plan of kinds, three next steps, and Make room.
struct RoomOverviewScreen: View {
    let insights: RoomInsightsModel
    let navigate: (RoomDestination) -> Void
    let refresh: () -> Void
    var cacheModel: RoomViewModel? = nil
    var developerBytes: Int64? = nil
    var makeRoom: () -> Void = {}

    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @State private var hoverNote: String?

    private var capacity: RoomVolumeCapacity? { insights.volumeCapacity }
    private var cachesChecked: Bool { cacheModel?.hasReport == true }
    private var cachesBytes: Int64 { cachesChecked ? (cacheModel?.clearableBytes ?? 0) : 0 }

    private var words: RoomOverviewWords {
        RoomOverviewWords.make(freeBytes: capacity?.freeBytes, capacityBytes: capacity?.capacityBytes,
                               goalBytes: goalEnabled ? RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal)) : nil,
                               cachesChecked: cachesChecked, cachesBytes: cachesBytes, developerBytes: developerBytes,
                               change: insights.volumeHistory.log.change(now: Date(), calendar: .current))
    }

    private var plan: RoomOverviewFloorPlan {
        let kinds = insights.homeKinds
        return RoomOverviewFloorPlan.make(kinds: kinds?.kinds, notMappedBytes: kinds?.notMappedBytes ?? 0,
                                          freeBytes: capacity?.freeBytes ?? 0, capacityBytes: capacity?.capacityBytes ?? 0)
    }

    var body: some View {
        let words = words
        RoomScreenFrame(headline: words.headline, supporting: words.supporting, supportingMasked: true,
                        note: hoverNote ?? words.note) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                if capacity != nil {
                    RoomOverviewFloorPlanView(plan: plan) { room in
                        guard let room else { hoverNote = nil; return }
                        let name = room.isFree ? "Free space" : room.title
                        hoverNote = hide.masksNow ? name : "\(name) is \(plan.percent(of: room))% of this Mac"
                    }
                    if insights.homeKinds == nil {
                        Button(insights.isScanningDisk ? "Mapping your home folder…" : "Map your home folder to see what fills it") {
                            insights.scanHome()
                        }
                        .roomLink(accent)
                        .disabled(insights.isScanningDisk || insights.isChoosingDiskFolder)
                    }
                } else {
                    Button("Read free space again", action: retryCapacity).roomLink(accent)
                }
                HStack(alignment: .top, spacing: 4) {
                    ForEach(words.facts, id: \.label) { fact in factButton(fact) }
                }
                .padding(.horizontal, -RoomTokens.Space.row)
                .padding(.top, RoomTokens.Space.row)
            }
        } action: {
            if !cachesChecked {
                Button("Check caches", action: openCaches)
                    .roomScreenPrimary(accent)
                    .disabled(cacheModel?.isScanning == true || cacheModel?.canScan == false)
            } else if cachesBytes > 0 {
                Button("Make room", action: makeRoom)
                    .roomScreenPrimary(accent) // one-filled: exclusive with Check caches above (never both)
                    .disabled(cacheModel?.isScanning == true || cacheModel?.isWorking == true)
                    .accessibilityHint("Opens a review before anything moves")
            }
        }
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

    private func factButton(_ fact: RoomOverviewWords.Fact) -> some View {
        Button { navigate(fact.destination) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.label).font(RoomTokens.Screen2.factLabel).foregroundStyle(RoomTokens.Ink.secondary)
                HStack(spacing: 4) {
                    Group {
                        if fact.masked { RoomMaskable(fact.value) } else { Text(fact.value) }
                    }
                    .font(RoomTokens.Screen2.factValue)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    Text(verbatim: "›").font(RoomTokens.Screen2.factValue).foregroundStyle(RoomTokens.Ink.tertiary)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, RoomTokens.Space.row)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.card))
        .accessibilityLabel("\(fact.label), \(hide.masksNow && fact.masked ? "hidden" : fact.value)")
        .accessibilityHint("Opens \(RoomSidebarPlan.title(fact.destination))")
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
