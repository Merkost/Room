import AppKit
import SwiftUI

/// The first-run welcome, v3 (ONBOARDING-V3-SPEC): Your Mac, Your say, First step.
/// Every input goes through `RoomOnboardingFlow.reduce`; effects leave through `onFinish`.
/// A fixed 680 x 540 layout with no scroll view, so the stage sits at the same place on every step.
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
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var state = RoomOnboardingState()
    @State private var planSettled = false
    @State private var hoveringLink = false
    @FocusState private var focus: Choice?

    private enum Choice: Hashable { case mapHome, checkCaches, menuBar }
    private typealias Onboarding = RoomTokens.Onboarding

    private var edition: RoomOnboardingEdition { .current }
    /// VoiceOver reads the still triptych instead of a beat that changes on a timer.
    private var exampleMotionIsFull: Bool { motion.isFull && !NSWorkspace.shared.isVoiceOverEnabled }
    private var context: RoomOnboardingContext {
        RoomOnboardingContext(edition: edition, isWorking: isWorking, motionIsFull: exampleMotionIsFull)
    }
    private var planState: RoomOnboardingPlanState {
        .make(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes)
    }
    private var hidden: Bool { hide.masksNow }
    private var choicesEnabled: Bool { RoomOnboardingFlow.choicesEnabled(isWorking: isWorking) }
    private var hintActive: Bool { !hoveringLink && focus != .checkCaches && focus != .menuBar }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            stage
                .padding(.top, Onboarding.leadToStage)
            caption
                .padding(.top, Onboarding.captionGap)
            if state.step == .firstStep {
                choices
                    .padding(.top, Onboarding.choiceGap)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, Onboarding.top)
        .padding(.horizontal, Onboarding.side)
        .padding(.bottom, Onboarding.bottom)
        .frame(width: Onboarding.width, height: Onboarding.height, alignment: .topLeading)
        .background(RoomTokens.Surface.canvas)
        .foregroundStyle(RoomTokens.Ink.graphite)
        .background { arrowKeys }
        .onAppear {
            Task { @MainActor in planSettled = true }
        }
        .task(id: state.step) {
            guard state.step == .yourSay, exampleMotionIsFull else { return }
            try? await Task.sleep(for: Onboarding.demoTick)
            guard !Task.isCancelled else { return }
            send(.demoTick)
        }
        .onChange(of: state.step) { _, step in
            if step == .firstStep { focus = .mapHome }
        }
        .onChange(of: state.beat) { _, beat in
            guard state.step == .yourSay, beat != .review else { return }
            AccessibilityNotification.Announcement(RoomOnboardingCopy.demoAccessibility(beat)).post()
        }
    }

    // MARK: Header (eyebrow, title, lead)

    private var header: some View {
        let lead = RoomOnboardingCopy.lead(state.step, plan: planState, hidden: hidden, format: RoomFormat.gb)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(RoomOnboardingCopy.stepNumber(state.step))
                    .fontWeight(.semibold)
                    .foregroundStyle(accent.text)
                Text(verbatim: " · \(RoomOnboardingCopy.stepName(state.step))")
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .font(RoomTokens.Typography.caption)
            .monospacedDigit()
            .frame(height: 16)
            .accessibilityElement(children: .combine)
            Text(RoomOnboardingCopy.title(state.step))
                .font(Onboarding.title)
                .tracking(Onboarding.titleTracking)
                .frame(height: 28, alignment: .leading)
                .padding(.top, Onboarding.headerGap)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h1)
            VStack(alignment: .leading, spacing: 4) {
                if let strong = lead.strong {
                    Text(strong).foregroundStyle(RoomTokens.Ink.graphite).monospacedDigit()
                }
                Text(lead.secondary).foregroundStyle(RoomTokens.Ink.secondary)
            }
            .font(RoomTokens.Typography.lead)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Onboarding.leadWidth, alignment: .leading)
            .frame(minHeight: Onboarding.leadReserve, alignment: .topLeading)
            .padding(.top, Onboarding.headerGap)
            .accessibilityElement(children: .combine)
        }
        .id(state.step)
        .transition(motion.isFull
            ? .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
            : .opacity)
    }

    // MARK: Stage (wall, plan or example)

    private var wallIsDashed: Bool {
        if state.step == .yourSay { return false }
        if case .drawn = planState { return false }
        return true
    }

    private var stage: some View {
        let height = RoomOnboardingStage.wallHeight(for: state.step)
        let wall = RoundedRectangle(cornerRadius: RoomTokens.OverviewPlan.outerRadius)
        let wallInk = contrast == .increased ? RoomTokens.Ink.secondary.opacity(0.6) : RoomTokens.Surface.line2
        return ZStack(alignment: .topLeading) {
            wall.strokeBorder(wallInk, style: StrokeStyle(lineWidth: RoomTokens.OverviewPlan.wall,
                                                          dash: wallIsDashed ? RoomTokens.OverviewPlan.dashedWall.dash : []))
            stageContent(height: height)
        }
        .frame(width: RoomOnboardingStage.width, height: height, alignment: .topLeading)
    }

    @ViewBuilder private func stageContent(height: CGFloat) -> some View {
        switch state.step {
        case .yourMac, .firstStep:
            planContent(height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(planAccessibility)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("RoomOnboardingPlan")
                .transition(.opacity)
        case .yourSay:
            RoomOnboardingExample(layout: RoomOnboardingFlow.demoLayout(beat: state.beat, motionIsFull: exampleMotionIsFull),
                                  putBack: { send(.demoPutBack) })
                .frame(width: RoomOnboardingStage.width, height: height)
                .transition(motion.isFull
                    ? .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
                    : .opacity)
        }
    }

    @ViewBuilder private func planContent(height: CGFloat) -> some View {
        switch planState {
        case .drawn(let plan):
            RoomOnboardingPlanView(plan: plan, wallHeight: height, hidden: hidden,
                                   showsHint: state.step == .firstStep, hintActive: hintActive, settled: planSettled)
        case .tooLarge:
            RoomOnboardingPlanUnavailable(tooLarge: true)
        case .unreadable:
            RoomOnboardingPlanUnavailable(tooLarge: false)
        }
    }

    private var planAccessibility: String {
        let plan = RoomOnboardingCopy.planAccessibility(planState, hidden: hidden, format: RoomFormat.gb)
        guard state.step == .firstStep, case .drawn = planState else { return plan }
        return "\(plan) \(RoomOnboardingCopy.hint)."
    }

    // MARK: Caption row

    @ViewBuilder private var caption: some View {
        HStack(spacing: 0) {
            switch state.step {
            case .yourSay:
                Label {
                    Text(RoomOnboardingCopy.local)
                } icon: {
                    Image(systemName: "lock").font(RoomTokens.Typography.caption)
                }
                Spacer(minLength: RoomTokens.Space.row)
                Text(RoomOnboardingCopy.exampleOnly)
            case .yourMac, .firstStep:
                if case .drawn(let plan) = planState {
                    HStack(spacing: 6) {
                        Circle()
                            .stroke(RoomTokens.Ink.secondary, lineWidth: RoomTokens.Dots.freeRingStroke)
                            .frame(width: 2 * Onboarding.ringGlyphRadius, height: 2 * Onboarding.ringGlyphRadius)
                        Text(RoomOnboardingCopy.freeName)
                            .fontWeight(.semibold)
                            .foregroundStyle(RoomTokens.Ink.graphite)
                        Text(verbatim: RoomOnboardingCopy.freeSize(plan, hidden: hidden, format: RoomFormat.gb))
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: RoomTokens.Space.row)
                    Text(verbatim: RoomOnboardingCopy.unitCaption(plan, hidden: hidden))
                }
            }
        }
        .font(RoomTokens.Typography.caption)
        .monospacedDigit()
        .foregroundStyle(RoomTokens.Ink.secondary)
        .lineLimit(1)
        .frame(width: RoomOnboardingStage.width, height: Onboarding.captionHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captionAccessibility)
    }

    private var captionAccessibility: String {
        switch state.step {
        case .yourSay: return "\(RoomOnboardingCopy.local) \(RoomOnboardingCopy.exampleOnly)"
        case .yourMac, .firstStep:
            guard case .drawn(let plan) = planState else { return "" }
            return RoomOnboardingCopy.captionAccessibility(plan, hidden: hidden, format: RoomFormat.gb)
        }
    }

    // MARK: Step 3 choices

    private var choices: some View {
        VStack(alignment: .leading, spacing: Onboarding.alternativesGap) {
            HStack(alignment: .center, spacing: RoomTokens.Space.group) {
                Button { send(.choose(.mapHome)) } label: {
                    Label(RoomOnboardingCopy.mapTitle(needsPicker: needsPicker), systemImage: "house")
                }
                .roomScreenPrimary(accent)
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .mapHome)
                .accessibilityHint(RoomOnboardingCopy.mapContext(edition: edition, needsPicker: needsPicker))
                .accessibilityIdentifier("RoomOnboardingMapHome")
                Text(choicesEnabled ? RoomOnboardingCopy.mapContext(edition: edition, needsPicker: needsPicker)
                                    : RoomOnboardingCopy.busy)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Onboarding.contextWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Onboarding.linkGap) {
                    alternativesLead
                    cachesLink
                    menuBarLink
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    alternativesLead
                    cachesLink
                    menuBarLink
                }
            }
        }
        .disabled(!choicesEnabled)
        .opacity(choicesEnabled ? 1 : Onboarding.disabledOpacity)
    }

    private var alternativesLead: some View {
        Text(RoomOnboardingCopy.alternativesLead)
            .font(RoomTokens.Typography.body)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .fixedSize()
    }

    private var cachesLink: some View {
        Button { send(.choose(.checkCaches)) } label: {
            Label(RoomOnboardingCopy.cachesTitle(edition: edition), systemImage: "archivebox")
                .font(RoomTokens.Typography.body)
                .fixedSize()
        }
        .roomLink(accent)
        .focused($focus, equals: .checkCaches)
        .onHover { hoveringLink = $0 }
        .accessibilityHint(RoomOnboardingCopy.cachesHint(edition: edition))
        .accessibilityIdentifier("RoomOnboardingCheckCaches")
    }

    private var menuBarLink: some View {
        Button { send(.choose(.menuBar)) } label: {
            Label(RoomOnboardingCopy.menuBarTitle, systemImage: "memorychip")
                .font(RoomTokens.Typography.body)
                .fixedSize()
        }
        .roomLink(accent)
        .focused($focus, equals: .menuBar)
        .onHover { hoveringLink = $0 }
        .accessibilityHint(RoomOnboardingCopy.menuBarHint)
        .accessibilityIdentifier("RoomOnboardingMenuBar")
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
                    Text("onboarding.p1.continue", bundle: RoomCopy.bundle)
                }
                .roomScreenPrimary(accent) // one-filled: exclusive with Map my home folder (shown only on steps 1 and 2)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("RoomOnboardingContinue")
            }
        }
        .font(RoomTokens.Typography.body)
        .frame(height: Onboarding.footerHeight)
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

    /// Key-driven changes never animate; pointer changes use the step's motion (MV-3...MV-7).
    private func send(_ event: RoomOnboardingEvent, fromKey: Bool = false) {
        let previous = state
        let (next, effects) = RoomOnboardingFlow.reduce(previous, event, context)
        if !effects.isEmpty {
            state = next
            if !onFinish(effects) { state.finished = false }
            return
        }
        guard next != previous else { return }
        let keyDriven = fromKey || NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
        if keyDriven, next.step != previous.step {
            roomWithoutMotion { state = next }
            return
        }
        withAnimation(animation(from: previous, to: next)) { state = next }
    }

    private func animation(from previous: RoomOnboardingState, to next: RoomOnboardingState) -> Animation? {
        if previous.step != next.step {
            let crossesChoose = previous.step == .firstStep || next.step == .firstStep
            return motion.animation(crossesChoose ? RoomTokens.Motion.page : RoomTokens.Motion.settle)
        }
        return motion.animation(RoomTokens.Motion.standard)
    }
}
