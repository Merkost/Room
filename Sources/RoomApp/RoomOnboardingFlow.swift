// Onboarding v3 (ONBOARDING-V3-SPEC §5 flow, §4 copy, §3 plan). Pure: no SwiftUI, no AppKit, no I/O, no clock.
// Copied from the design reference `onboarding-v3/snippets/RoomOnboardingV3.swift`; the copy reads the String
// Catalogue (`onboarding.v3.*`) with the reference's English as the fallback value.
import CoreGraphics
import Foundation

nonisolated enum RoomOnboardingEdition: Sendable {
    case direct, store

    static var current: Self {
        #if ROOM_APP_STORE
        .store
        #else
        .direct
        #endif
    }
}

/// v3 renames `mapFolder` to `mapHome`: the first action maps the home folder, it no longer asks for "a folder".
nonisolated enum RoomOnboardingChoice: CaseIterable, Sendable { case mapHome, checkCaches, menuBar }

/// Every effect is an EXISTING entry point; onboarding adds no scanner, picker or permission of its own.
nonisolated enum RoomOnboardingEffect: Equatable, Sendable {
    case markSeen                       // RoomOnboardingVersion = RoomOnboardingFlow.version
    case close
    case navigate(String)               // RoomDestination raw value
    case scanHome(confirmed: Bool)      // RoomInsightsModel.scanHome(confirmed:): picker only if no remembered home scope
    case chooseStoreCachesFolder        // Store: RoomViewModel.chooseStoreFolder(scanAfterApproval: true)
    case startCachesCheck               // Direct: RoomViewModel.scan()
    case enableMenuBar                  // RoomMenuBarEnabled = true
    case showMonitorOnce                // RoomStatusMonitor.showMonitor(), once, after the item exists
}

nonisolated enum RoomOnboardingStep: Int, CaseIterable, Sendable {
    case yourMac = 1, yourSay, firstStep
}

/// The example on step 2. It never touches a file: it is three drawings and one harmless button.
nonisolated enum RoomDemoBeat: Int, CaseIterable, Sendable { case review = 1, trashed, restored }

nonisolated enum RoomDemoLayout: Equatable, Sendable {
    case single(RoomDemoBeat)              // full motion: one card that changes beat
    case triptych(highlight: RoomDemoBeat) // Reduce Motion / Gentle off: three cards side by side, no auto-play
}

nonisolated enum RoomOnboardingKey: Sendable { case returnKey, escape, left, right }

nonisolated enum RoomOnboardingEvent: Sendable {
    case key(RoomOnboardingKey)
    case continuePressed, backPressed, skipPressed
    case choose(RoomOnboardingChoice)
    case demoTick                        // one-shot timer, 1.2 s after step 2 appears, full motion only
    case demoPutBack
}

nonisolated struct RoomOnboardingContext: Sendable {
    var edition: RoomOnboardingEdition
    var isWorking: Bool                  // a move, restore or picker is running
    var motionIsFull: Bool               // RoomMotionPolicy.isFull
}

nonisolated struct RoomOnboardingState: Equatable, Sendable {
    var step: RoomOnboardingStep = .yourMac
    var beat: RoomDemoBeat = .review
    var finished = false
}

nonisolated enum RoomOnboardingFlow {
    /// Unchanged from v2: people who already saw the v2 welcome do not see v3 (D-ONV-9). Help › Show Welcome replays it.
    /// Bumping this to 3 would show the v3 welcome once to everyone who saw v2 (owner decision).
    static let version = 2

    static func shouldShow(storedVersion: Int) -> Bool { storedVersion < version }

    static func effects(_ choice: RoomOnboardingChoice, edition: RoomOnboardingEdition) -> [RoomOnboardingEffect] {
        switch (choice, edition) {
        case (.mapHome, _): [.markSeen, .close, .navigate("overview"), .scanHome(confirmed: true)]
        case (.checkCaches, .store): [.markSeen, .close, .navigate("clean"), .chooseStoreCachesFolder]
        case (.checkCaches, .direct): [.markSeen, .close, .navigate("clean"), .startCachesCheck]
        case (.menuBar, _): [.markSeen, .close, .enableMenuBar, .showMonitorOnce]
        }
    }
    /// Skip for now / Esc: mark seen and close; the window stays on its resolved destination.
    static let skipEffects: [RoomOnboardingEffect] = [.markSeen, .close]

    static func choicesEnabled(isWorking: Bool) -> Bool { !isWorking }

    /// The one filled button on step 3.
    static func isProminent(_ choice: RoomOnboardingChoice) -> Bool { choice == .mapHome }

    static func demoLayout(beat: RoomDemoBeat, motionIsFull: Bool) -> RoomDemoLayout {
        motionIsFull ? .single(beat) : .triptych(highlight: beat)
    }

    /// The whole step machine. Returns the next state and, when the sheet should close, the effects to run.
    static func reduce(_ state: RoomOnboardingState, _ event: RoomOnboardingEvent,
                       _ context: RoomOnboardingContext) -> (RoomOnboardingState, [RoomOnboardingEffect]) {
        guard !state.finished else { return (state, []) }
        var next = state
        func finish(_ effects: [RoomOnboardingEffect]) -> (RoomOnboardingState, [RoomOnboardingEffect]) {
            next.finished = true
            return (next, effects)
        }
        func move(to step: RoomOnboardingStep) {
            if step == .yourSay, next.step != .yourSay { next.beat = .review }   // the example starts again on entry
            next.step = step
        }
        func choose(_ choice: RoomOnboardingChoice) -> (RoomOnboardingState, [RoomOnboardingEffect]) {
            guard state.step == .firstStep, choicesEnabled(isWorking: context.isWorking) else { return (state, []) }
            return finish(effects(choice, edition: context.edition))
        }
        switch event {
        case .key(.escape), .skipPressed:
            return finish(skipEffects)
        case .key(.returnKey), .continuePressed:
            if state.step == .firstStep { return choose(.mapHome) }   // Return presses the one filled button
            if let later = RoomOnboardingStep(rawValue: state.step.rawValue + 1) { move(to: later) }
        case .key(.right):
            if let later = RoomOnboardingStep(rawValue: state.step.rawValue + 1) { move(to: later) } // never chooses
        case .key(.left), .backPressed:
            if let earlier = RoomOnboardingStep(rawValue: state.step.rawValue - 1) { move(to: earlier) }
        case .choose(let choice):
            return choose(choice)
        case .demoTick:
            if state.step == .yourSay, state.beat == .review, context.motionIsFull { next.beat = .trashed }
        case .demoPutBack:
            if state.step == .yourSay {
                // Full motion: Put back exists only once the card shows the receipt. Triptych: Put back is always visible.
                if state.beat == .trashed || (!context.motionIsFull && state.beat == .review) { next.beat = .restored }
            }
        }
        return (next, [])
    }
}

// MARK: - The plan of this Mac (step 1 and step 3)

nonisolated enum RoomOnboardingPlanState: Equatable, Sendable {
    case drawn(RoomOverviewPlanInput)
    case tooLarge(capacityBytes: Int64, freeBytes: Int64)   // measured, but more than 260 dots at 100 GB per dot
    case unreadable

    static func make(capacityBytes: Int64?, freeBytes: Int64?) -> Self {
        guard let c = capacityBytes, let f = freeBytes, c > 0, f >= 0, f <= c else { return .unreadable }
        let gb = Double(c) / 1e9
        guard gb / RoomPure.gbPerDot(capacityGB: gb) <= Double(RoomPure.targetDots) else {
            return .tooLarge(capacityBytes: c, freeBytes: f)
        }
        return .drawn(RoomOverviewPlanInput(capacityBytes: c, freeBytes: f, goalBytes: nil))
    }

    var measured: (capacity: Int64, free: Int64)? {
        switch self {
        case .drawn(let p): (p.capacityBytes, p.freeBytes)
        case .tooLarge(let c, let f): (c, f)
        case .unreadable: nil
        }
    }
}

/// Stage sizes: the plan is laid out inside the wall with pad 5 (OVERVIEW-SPEC §6).
nonisolated enum RoomOnboardingStage {
    static let width: CGFloat = 600
    static let introWallHeight: CGFloat = 252      // steps 1 and 2
    static let chooseWallHeight: CGFloat = 180     // step 3
    static let pad: CGFloat = 5
    static func layoutSize(wallHeight: CGFloat) -> CGSize {
        CGSize(width: width - 2 * pad, height: wallHeight - 2 * pad)
    }
    static func wallHeight(for step: RoomOnboardingStep) -> CGFloat {
        step == .firstStep ? chooseWallHeight : introWallHeight
    }
}

// MARK: - Copy selection (String Catalogue keys, English reference values as the fallback)

nonisolated struct RoomOnboardingLead: Equatable, Sendable {
    var strong: String?      // ink: the measured sentence
    var secondary: String    // ink 2
}

nonisolated enum RoomOnboardingText {
    static func string(_ key: String, _ english: String) -> String {
        RoomCopy.bundle.localizedString(forKey: key, value: english, table: nil)
    }
    static func format(_ key: String, _ english: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key, english), locale: .current, arguments: arguments)
    }
}

nonisolated enum RoomOnboardingCopy {
    private typealias T = RoomOnboardingText

    static func stepName(_ step: RoomOnboardingStep) -> String {
        switch step {
        case .yourMac: T.string("onboarding.v3.step1.name", "Your Mac")
        case .yourSay: T.string("onboarding.v3.step2.name", "Your say")
        case .firstStep: T.string("onboarding.v3.step3.name", "First step")
        }
    }
    static func stepNumber(_ step: RoomOnboardingStep) -> String {
        T.format("onboarding.v3.step", "%1$d of 3", step.rawValue)
    }
    static func eyebrow(_ step: RoomOnboardingStep) -> String { "\(stepNumber(step)) · \(stepName(step))" }

    static func title(_ step: RoomOnboardingStep) -> String {
        switch step {
        case .yourMac: T.string("onboarding.v3.step1.title", "Room to breathe.")
        case .yourSay: T.string("onboarding.v3.step2.title", "Nothing moves until you say so.")
        case .firstStep: T.string("onboarding.v3.step3.title", "Where should Room look first?")
        }
    }

    static func lead(_ step: RoomOnboardingStep, plan: RoomOnboardingPlanState, hidden: Bool,
                     format: (Int64) -> String) -> RoomOnboardingLead {
        switch step {
        case .yourSay:
            return .init(strong: nil, secondary: T.string("onboarding.v3.step2.lead",
                "Room shows you what it found, then waits. Whatever you move goes to Trash with a receipt, so you can put it back."))
        case .firstStep:
            return .init(strong: nil, secondary: T.string("onboarding.v3.step3.lead",
                "Pick one to start. The others are on Overview whenever you want them."))
        case .yourMac:
            guard let m = plan.measured else {
                return .init(strong: nil, secondary: T.string("onboarding.v3.step1.unreadable",
                    "Room couldn’t read this Mac’s free space just now. Overview asks again on its own."))
            }
            let strong = hidden ? T.string("onboarding.v3.step1.hidden", "This is your Mac. Sizes hidden.")
                : T.format("onboarding.v3.step1.measured", "This is your Mac: %1$@ free of %2$@.", format(m.free), format(m.capacity))
            if case .tooLarge = plan {
                return .init(strong: strong, secondary: tooLarge)
            }
            return .init(strong: strong, secondary: T.string("onboarding.v3.step1.honest", "Room draws only what it has measured."))
        }
    }

    static var tooLarge: String { T.string("onboarding.v3.step1.tooLarge", "Room draws plans of disks up to 26 TB for now.") }

    /// Inside the Not mapped yet area. Step 3 swaps it for the hint.
    static func notMappedLabel(_ step: RoomOnboardingStep) -> String {
        step == .firstStep ? hint : T.string("onboarding.v3.plan.notMapped", "Not mapped yet")
    }
    static var hint: String { T.string("onboarding.v3.hint", "Rooms appear here as Room maps your home folder") }
    static func notMappedDetail(_ plan: RoomOverviewPlanInput, hidden: Bool, format: (Int64) -> String) -> String {
        hidden ? T.string("onboarding.v3.plan.notMappedDetail.hidden", "Room hasn’t looked inside.")
            : T.format("onboarding.v3.plan.notMappedDetail", "%@ used. Room hasn’t looked inside.", format(plan.notMappedBytes))
    }
    static var freeName: String { T.string("onboarding.v3.plan.free", "Free") }
    static func freeSize(_ plan: RoomOverviewPlanInput, hidden: Bool, format: (Int64) -> String) -> String {
        hidden ? RoomPure.mask(format(plan.freeBytes), first: Int.max, lettersToo: false) : format(plan.freeBytes)
    }
    static func freeLegend(_ plan: RoomOverviewPlanInput, hidden: Bool, format: (Int64) -> String) -> String {
        "\(freeName) \(freeSize(plan, hidden: hidden, format: format))"
    }
    static func unitCaption(_ plan: RoomOverviewPlanInput, hidden: Bool) -> String {
        let s = T.format("onboarding.v3.plan.unit", "1 dot = about %@", "\(Int(plan.gbPerDot)) GB")
        return hidden ? RoomPure.mask(s, first: Int.max, lettersToo: false) : s
    }
    static var emptyTitle: String { T.string("onboarding.v3.plan.empty.title", "Your Mac’s plan appears here once macOS answers.") }
    static var emptyDetail: String { T.string("onboarding.v3.plan.empty.detail", "Room only draws what it has measured.") }

    /// The ellipsis means "more input follows": the folder picker opens before anything is read.
    static func mapTitle(needsPicker: Bool) -> String {
        needsPicker ? T.string("onboarding.v3.map.picker", "Map my home folder…") : T.string("onboarding.v3.map", "Map my home folder")
    }

    static func mapContext(edition: RoomOnboardingEdition, needsPicker: Bool) -> String {
        let first = needsPicker ? T.string("onboarding.v3.map.next", "Next: macOS asks you to choose your home folder.")
                                : T.string("onboarding.v3.map.now", "Room starts mapping right away.")
        let second = edition == .store
            ? T.string("onboarding.v3.map.store", "Pictures and Music stay out. Room reads sizes, never file contents.")
            : T.string("onboarding.v3.map.direct", "Pictures and Music stay out. Full Disk Access is optional.")
        return "\(first) \(second)"
    }

    static func cachesTitle(edition: RoomOnboardingEdition) -> String {
        edition == .store ? T.string("onboarding.v3.caches.store", "Check caches…") : T.string("onboarding.v3.caches", "Check caches")
    }
    static func cachesHint(edition: RoomOnboardingEdition) -> String {
        edition == .store ? T.string("onboarding.v3.a11y.caches.store", "Opens Caches and asks for a folder.")
                          : T.string("onboarding.v3.a11y.caches", "Opens Caches and starts a check.")
    }

    static var menuBarTitle: String { T.string("onboarding.v3.menuBar", "Watch memory in the menu bar") }
    static var menuBarHint: String { T.string("onboarding.v3.a11y.menuBar", "Adds Room to the menu bar.") }
    static var alternativesLead: String { T.string("onboarding.v3.or", "Or start with") }
    static var busy: String { T.string("onboarding.v3.busy", "Room is finishing another task. This is ready in a moment.") }
    static var local: String { T.string("onboarding.v3.local", "No account. Everything runs on this Mac.") }
    static var exampleOnly: String { T.string("onboarding.v3.exampleOnly", "Example only. Nothing on your Mac has moved.") }

    // Accessibility (ONBOARDING-V3-SPEC §8)
    static func planAccessibility(_ plan: RoomOnboardingPlanState, hidden: Bool, format: (Int64) -> String) -> String {
        guard let m = plan.measured else {
            return T.string("onboarding.v3.a11y.plan.unavailable", "Your Mac. Free space not available yet.")
        }
        if hidden { return T.string("onboarding.v3.a11y.plan.hidden", "Your Mac. Sizes hidden.") }
        return T.format("onboarding.v3.a11y.plan", "Your Mac: %1$@ free of %2$@. %3$@ not mapped yet.",
                        format(m.free), format(m.capacity), format(m.capacity - m.free))
    }
    static func captionAccessibility(_ plan: RoomOverviewPlanInput, hidden: Bool, format: (Int64) -> String) -> String {
        if hidden { return freeName }
        return T.format("onboarding.v3.a11y.caption", "Free, %1$@. 1 dot is about %2$@.",
                        format(plan.freeBytes), "\(Int(plan.gbPerDot)) GB")
    }
    static func demoAccessibility(_ beat: RoomDemoBeat) -> String {
        switch beat {
        case .review: T.string("onboarding.v3.a11y.example.1",
            "Example, nothing on your Mac moves. Step 1 of 3: you review first.")
        case .trashed: T.string("onboarding.v3.a11y.example.2",
            "Example, nothing on your Mac moves. Step 2 of 3: moved to Trash, receipt kept in History.")
        case .restored: T.string("onboarding.v3.a11y.example.3",
            "Example, nothing on your Mac moves. Step 3 of 3: put back where it was.")
        }
    }

    /// Every English string this file can produce with a fixture, for the copy lint check.
    static func allStrings(format: (Int64) -> String) -> [String] {
        let gb: Int64 = 1_000_000_000
        let p = RoomOverviewPlanInput(capacityBytes: 994 * gb, freeBytes: 312 * gb, goalBytes: nil)
        var out: [String] = []
        for step in RoomOnboardingStep.allCases {
            out += [eyebrow(step), title(step), notMappedLabel(step)]
            for plan in [RoomOnboardingPlanState.drawn(p), .unreadable, .tooLarge(capacityBytes: 40_000 * gb, freeBytes: 9_000 * gb)] {
                for hidden in [false, true] {
                    let l = lead(step, plan: plan, hidden: hidden, format: format)
                    out += [l.strong ?? "", l.secondary, planAccessibility(plan, hidden: hidden, format: format)]
                }
            }
        }
        for e in [RoomOnboardingEdition.direct, .store] {
            for n in [false, true] { out += [mapTitle(needsPicker: n), mapContext(edition: e, needsPicker: n)] }
            out += [cachesTitle(edition: e), cachesHint(edition: e)]
        }
        out += [menuBarTitle, menuBarHint, alternativesLead, busy, local, exampleOnly, emptyTitle, emptyDetail, tooLarge,
                notMappedDetail(p, hidden: false, format: format), notMappedDetail(p, hidden: true, format: format),
                freeLegend(p, hidden: false, format: format), unitCaption(p, hidden: false),
                captionAccessibility(p, hidden: false, format: format)]
        out += RoomDemoBeat.allCases.map(demoAccessibility)
        return out.filter { !$0.isEmpty }
    }
}

/// Copy rules from 16 §1 and the brief: no exclamation marks, no em dash, sentence case (proper nouns allowed).
nonisolated enum RoomOnboardingCopyLint {
    /// "Put" (the Put back button) and "Caches" (the screen) are names in the example rail and the VoiceOver hints.
    static let properNouns: Set<String> = ["Room", "Mac", "macOS", "Trash", "History", "Overview", "Pictures", "Music",
                                           "Full", "Disk", "Access", "TB", "GB", "Xcode", "DerivedData", "Put", "Caches"]
    static func violations(_ s: String) -> [String] {
        var v: [String] = []
        if s.contains("!") { v.append("exclamation") }
        if s.contains("\u{2014}") { v.append("em dash") }
        // Sentences and clauses that may start with a capital: after ". ", ": ", "? " and the eyebrow's " · ".
        var text = s
        for mark in [". ", ": ", "? ", " · "] { text = text.replacingOccurrences(of: mark, with: "\n") }
        for clause in text.split(separator: "\n") {
            for word in clause.split(separator: " ").dropFirst() {
                let bare = word.trimmingCharacters(in: .punctuationCharacters).replacingOccurrences(of: "’s", with: "")
                if bare.first?.isUppercase == true, !properNouns.contains(bare) { v.append("capital: \(bare)") }
            }
        }
        return v
    }
}
