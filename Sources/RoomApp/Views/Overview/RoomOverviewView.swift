import Accessibility
import AppKit
import CoreText
import SwiftUI

struct RoomOverviewView: View {
    let insights: RoomInsightsModel
    let navigate: (RoomDestination) -> Void
    let refresh: () -> Void

    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var goalEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var model = RoomOverviewModel()

    private struct Inputs: Equatable {
        let capacity: RoomVolumeCapacity?
        let sampledAt: Date?
        let goalBytes: Int64?
    }

    private var inputs: Inputs {
        Inputs(capacity: insights.volumeCapacity, sampledAt: insights.diskCapacitySampledAt,
               goalBytes: goalEnabled ? Int64(storedGoal) : nil)
    }

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: RoomTokens.Density.calm.betweenGroups) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                Text(model.greeting)
                    .font(RoomTokens.Typography.lead)
                    .lineHeight(.exact(points: RoomTokens.Overview.greetingLineHeight))
                    .foregroundStyle(RoomTokens.Ink.secondary)
                answerGroup(snapshot)
            }
            actions(snapshot)
        }
        .frame(maxWidth: RoomTokens.Space.measure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(RoomTokens.Ink.graphite)
        .onChange(of: inputs, initial: true) { previous, updated in
            model.update(capacity: updated.capacity, goalBytes: updated.goalBytes)
            if previous.sampledAt != nil, (previous.capacity == nil) != (updated.capacity == nil),
               scenePhase == .active {
                AccessibilityNotification.Announcement(model.snapshot.accessibilityAnswer).post()
            }
        }
        .onAppear { updateCapacityMonitoring() }
        .onChange(of: scenePhase) { _, _ in updateCapacityMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == RoomApplicationDelegate.primaryWindowID else { return }
            updateCapacityMonitoring(in: window)
        }
        .onDisappear { insights.setOverviewActive(false) }
    }

    private func answerGroup(_ snapshot: RoomOverviewSnapshot) -> some View {
        let answer = Text(snapshot.answer)
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
            Text(snapshot.sentence)
                .font(RoomTokens.Typography.lead.monospacedDigit())
                .lineHeight(.exact(points: RoomTokens.Overview.goalLineHeight))
                .foregroundStyle(snapshot.state == .belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilityAnswer)
        .accessibilityHeading(.h1)
    }

    private func actions(_ snapshot: RoomOverviewSnapshot) -> some View {
        Group {
            switch snapshot.action {
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

    func openCaches() { navigate(.clean) }

    func openDiskMap() { navigate(.disk) }

    func retryCapacity() { refresh() }

    private func updateCapacityMonitoring(in window: NSWindow? = nil) {
        let primary = window ?? NSApp?.windows.first { $0.identifier == RoomApplicationDelegate.primaryWindowID }
        let windowVisible = primary?.occlusionState.contains(.visible) ?? true
        insights.setOverviewActive(scenePhase == .active && windowVisible)
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
