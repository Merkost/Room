import AppKit
import SwiftUI

/// The first-run welcome: three nearly wordless scenes (Meet your Mac, You say what moves, Pick your first step).
/// Every input goes through `RoomOnboardingFlow.reduce`; effects leave through `onFinish`.
/// A fixed 680 x 540 layout with no scroll view: pips, a display title with one short line, the scene, the footer.
struct RoomOnboardingView: View {
    let capacity: RoomVolumeCapacity?
    let isWorking: Bool
    /// No remembered home scope: the folder picker opens first, so the action carries an ellipsis.
    let needsPicker: Bool
    /// Returns false when the root refused the effects (work started meanwhile); the sheet then stays usable.
    let onFinish: ([RoomOnboardingEffect]) -> Bool

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @State private var state = RoomOnboardingState()
    @State private var hoveredTile: RoomOnboardingChoice?
    @State private var numberIn = false
    @State private var finishing = false
    /// +1 going forward, -1 going back: the scene slides in from that side.
    @State private var direction: CGFloat = 1
    @FocusState private var focus: RoomOnboardingChoice?

    private typealias Onboarding = RoomTokens.Onboarding

    private var edition: RoomOnboardingEdition { .current }
    private var context: RoomOnboardingContext {
        RoomOnboardingContext(edition: edition, isWorking: isWorking, motionIsFull: motion.isFull)
    }
    private var planState: RoomOnboardingPlanState {
        .make(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes)
    }
    private var hidden: Bool { hide.masksNow }
    private var choicesEnabled: Bool { RoomOnboardingFlow.choicesEnabled(isWorking: isWorking) }
    /// The dashed Not mapped area lights while Map my home folder (the default action) is the tile in play.
    private var mapInPlay: Bool { hoveredTile == .mapHome || (hoveredTile == nil && focus != .checkCaches && focus != .menuBar) }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                stage
                    .padding(.top, Onboarding.headerToStage)
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, Onboarding.top)
            .padding(.horizontal, Onboarding.side)
            .padding(.bottom, Onboarding.bottom)
            .opacity(finishing ? 0 : 1)
            .scaleEffect(finishing ? 0.98 : 1)
            if finishing {
                RoomOnboardingFinishMark()
            }
        }
        .frame(width: Onboarding.width, height: Onboarding.height, alignment: .topLeading)
        .background(RoomTokens.Surface.canvas)
        .foregroundStyle(RoomTokens.Ink.graphite)
        .background { arrowKeys }
        .onAppear {
            Task { @MainActor in numberIn = true }
        }
        .onChange(of: state.step) { _, step in
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            if step == .firstStep { focus = .mapHome }
        }
        .onChange(of: state.beat) { _, beat in
            guard state.step == .yourSay, beat != .review else { return }
            AccessibilityNotification.Announcement(RoomOnboardingCopy.demoAccessibility(beat)).post()
        }
    }

    // MARK: Progress pips (the eyebrow, as a picture)

    private var pips: some View {
        HStack(spacing: Onboarding.pipGap) {
            ForEach(RoomOnboardingStep.allCases, id: \.rawValue) { step in
                let current = step == state.step
                Capsule()
                    .fill(current ? accent.fill : RoomTokens.Surface.line2)
                    .frame(width: current ? Onboarding.pipCurrent : Onboarding.pip, height: Onboarding.pip)
            }
        }
        .frame(height: Onboarding.pipsHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RoomOnboardingCopy.stepNumber(state.step))
    }

    // MARK: Header: title, one line, and on step 1 the one big number

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .lastTextBaseline, spacing: RoomTokens.Space.group) {
                VStack(alignment: .leading, spacing: Onboarding.titleToLine) {
                    Text(RoomOnboardingCopy.title(state.step))
                        .font(Onboarding.title)
                        .tracking(Onboarding.titleTracking)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h1)
                    Text(lineText)
                        .font(Onboarding.line)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.step == .yourMac, planState.measured != nil {
                    bigNumber
                }
            }
            .id(state.step)
            .transition(sceneTransition)
        }
        .frame(height: Onboarding.headerHeight, alignment: .bottomLeading)
    }

    private var lineText: String {
        if state.step == .firstStep, !choicesEnabled { return RoomOnboardingCopy.busy }
        return RoomOnboardingCopy.line(state.step, plan: planState)
    }

    /// The free space in the display face; it pops in once, after the first rings. Hide masks every digit.
    private var bigNumber: some View {
        let formatted = RoomFormat.gb(planState.measured?.free ?? 0, hero: true)
        let shown = hidden ? RoomPure.mask(formatted, first: Int.max, lettersToo: false) : formatted
        let parts = shown.split(separator: " ", maxSplits: 1).map(String.init)
        let figure = parts.first ?? shown
        let unit = parts.count > 1 ? parts[1] : ""
        return VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: figure)
                .font(Onboarding.bigNumber)
                .tracking(Onboarding.bigNumberTracking)
                .monospacedDigit()
            Text(verbatim: RoomOnboardingCopy.freeUnit(unit))
                .font(Onboarding.bigUnit)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .scaleEffect(numberIn || !motion.isFull ? 1 : Onboarding.numberPopFrom, anchor: .bottomTrailing)
        .opacity(numberIn ? 1 : 0)
        .animation(motion.isFull ? RoomTokens.Motion.pop.delay(Onboarding.numberDelay) : RoomTokens.Motion.fade, value: numberIn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RoomOnboardingCopy.lead(.yourMac, plan: planState, hidden: hidden, format: RoomFormat.gb).strong ?? "")
    }

    // MARK: Stage

    private var sceneTransition: AnyTransition {
        guard motion.isFull else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: 28 * direction)),
                           removal: .opacity.combined(with: .offset(x: -14 * direction)))
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch state.step {
                case .yourMac:
                    plan(height: RoomOnboardingStage.introWallHeight, highlight: false)
                case .yourSay:
                    RoomOnboardingExample(beat: state.beat,
                                          trash: { send(.demoTrash) },
                                          putBack: { send(.demoPutBack) })
                        .frame(width: RoomOnboardingStage.width, height: RoomOnboardingStage.introWallHeight)
                case .firstStep:
                    VStack(spacing: Onboarding.stageToTiles) {
                        plan(height: RoomOnboardingStage.chooseWallHeight, highlight: mapInPlay)
                        RoomOnboardingTiles(needsPicker: needsPicker, edition: edition, enabled: choicesEnabled,
                                            focus: $focus, hovered: $hoveredTile) { send(.choose($0)) }
                    }
                }
            }
            .id(state.step)
            .transition(sceneTransition)
        }
        .frame(width: RoomOnboardingStage.width, height: RoomOnboardingStage.introWallHeight, alignment: .topLeading)
    }

    @ViewBuilder private func plan(height: CGFloat, highlight: Bool) -> some View {
        let size = CGSize(width: RoomOnboardingStage.width, height: height)
        Group {
            switch planState {
            case .drawn(let plan):
                RoomOnboardingPlanView(plan: plan, size: size, hidden: hidden, highlight: highlight)
            case .tooLarge, .unreadable:
                RoomOnboardingPlanUnavailable(size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibility)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("RoomOnboardingPlan")
    }

    private var planAccessibility: String {
        let plan = RoomOnboardingCopy.planAccessibility(planState, hidden: hidden, format: RoomFormat.gb)
        guard state.step == .firstStep, case .drawn = planState else { return plan }
        return "\(plan) \(RoomOnboardingCopy.hint)."
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Onboarding.linkGap) {
            if state.step != .yourMac {
                Button { send(.backPressed) } label: {
                    Label {
                        Text("onboarding.p2.back", bundle: RoomCopy.bundle)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minWidth: 44, minHeight: RoomTokens.Sidebar.minimumTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RoomPressStyle())
                .foregroundStyle(RoomTokens.Ink.secondary)
                .accessibilityIdentifier("RoomOnboardingBack")
            }
            Spacer(minLength: 0)
            Button { send(.skipPressed) } label: {
                Text("onboarding.p2.skip", bundle: RoomCopy.bundle)
                    .frame(minHeight: RoomTokens.Sidebar.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoomPressStyle())
            .foregroundStyle(RoomTokens.Ink.secondary)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("RoomOnboardingSkip")
            if state.step != .firstStep {
                Button { send(.continuePressed) } label: {
                    Label {
                        Text("onboarding.p1.continue", bundle: RoomCopy.bundle)
                    } icon: {
                        Image(systemName: "arrow.right")
                    }
                    .labelStyle(RoomTrailingIconLabelStyle())
                }
                .roomScreenPrimary(accent) // one-filled: exclusive with the Map tile (Continue shows only on steps 1 and 2)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("RoomOnboardingContinue")
            }
        }
        .font(RoomTokens.Typography.body)
        .frame(height: Onboarding.footerHeight)
        .overlay { pips }
    }

    /// ← and → move between steps (→ never chooses). Invisible shortcut buttons work wherever focus is.
    private var arrowKeys: some View {
        ZStack {
            Button("") { send(.key(.left), fromKey: true) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { send(.key(.right), fromKey: true) }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Events

    /// Key-driven step changes never animate; pointer changes use springs. A choice pops the Room mark, then closes.
    private func send(_ event: RoomOnboardingEvent, fromKey: Bool = false) {
        let previous = state
        let (next, effects) = RoomOnboardingFlow.reduce(previous, event, context)
        if !effects.isEmpty {
            state = next
            finish(effects)
            return
        }
        guard next != previous else { return }
        direction = next.step.rawValue >= previous.step.rawValue ? 1 : -1
        let keyDriven = fromKey || NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
        if keyDriven, next.step != previous.step {
            roomWithoutMotion { state = next }
            return
        }
        withAnimation(previous.step != next.step ? motion.animation(RoomTokens.Motion.page) : nil) { state = next }
    }

    private func finish(_ effects: [RoomOnboardingEffect]) {
        guard effects != RoomOnboardingFlow.skipEffects, motion.isFull else {
            if !onFinish(effects) { state.finished = false }
            return
        }
        withAnimation(RoomTokens.Motion.pop) { finishing = true }
        Task { @MainActor in
            try? await Task.sleep(for: Onboarding.markHold)
            if !onFinish(effects) {
                state.finished = false
                withAnimation(RoomTokens.Motion.standard) { finishing = false }
            }
        }
    }
}

/// "Continue →": the arrow rides after the word.
private struct RoomTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RoomTokens.Space.tight) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// The finishing beat: the Room mark pops in the accent, then the sheet closes. Full motion only.
private struct RoomOnboardingFinishMark: View {
    @Environment(\.roomAccent) private var accent
    @State private var popped = false

    var body: some View {
        RoomMark()
            .fill(accent.fill, style: FillStyle(eoFill: true))
            .frame(width: RoomTokens.Onboarding.markSize, height: RoomTokens.Onboarding.markSize)
            .scaleEffect(popped ? 1 : RoomTokens.Onboarding.ringPopFrom)
            .opacity(popped ? 1 : 0)
            .animation(RoomTokens.Motion.pop, value: popped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { Task { @MainActor in popped = true } }
            .accessibilityHidden(true)
    }
}
