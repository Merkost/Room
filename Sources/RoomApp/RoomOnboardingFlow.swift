import Foundation

nonisolated enum RoomOnboardingEdition: Sendable { case direct, store }

nonisolated enum RoomOnboardingChoice: CaseIterable, Sendable { case mapFolder, checkCaches, menuBar }

/// Every effect is an EXISTING entry point (named in the spec); onboarding adds no scanner, picker or permission.
nonisolated enum RoomOnboardingEffect: Equatable, Sendable {
    case markSeen                       // RoomOnboardingVersion = 2
    case close
    case navigate(String)               // RoomDestination raw value
    case chooseHomeAccess               // Store: choose a read-only root and map after approval
    case chooseDiskFolder               // Direct: the native picker grants a single mapping root
    case chooseStoreCachesFolder        // Store: RoomViewModel.chooseStoreFolder(scanAfterApproval: true)
    case startCachesCheck               // Direct: RoomViewModel.scan()
    case enableMenuBar                  // RoomMenuBarEnabled = true
    case showMonitorOnce                // RoomStatusMonitor.showMonitor(), once, after the item exists
}

nonisolated enum RoomOnboardingFlow {
    static let version = 2

    /// 04 §6: shown once to new people and once to 1.x / pre-2.0 people (stored 0 or 1).
    static func shouldShow(storedVersion: Int) -> Bool { storedVersion < version }

    static func effects(_ choice: RoomOnboardingChoice, edition: RoomOnboardingEdition) -> [RoomOnboardingEffect] {
        switch (choice, edition) {
        case (.mapFolder, .store): [.markSeen, .close, .navigate("disk"), .chooseHomeAccess]
        case (.mapFolder, .direct): [.markSeen, .close, .navigate("disk"), .chooseDiskFolder]
        case (.checkCaches, .store): [.markSeen, .close, .navigate("clean"), .chooseStoreCachesFolder]
        case (.checkCaches, .direct): [.markSeen, .close, .navigate("clean"), .startCachesCheck]
        case (.menuBar, _): [.markSeen, .close, .enableMenuBar, .showMonitorOnce]
        }
    }
    /// Skip for now / Esc: mark seen and close; the window stays on its resolved destination (no forced route).
    static let skipEffects: [RoomOnboardingEffect] = [.markSeen, .close]

    /// While a move, restore or picker is running every choice is disabled (same guard as File › Pin).
    static func choicesEnabled(isWorking: Bool) -> Bool { !isWorking }

    /// ON-5: the one prominent button is the first choice's.
    static func isProminent(_ choice: RoomOnboardingChoice) -> Bool { choice == .mapFolder }

    /// Page 1 plan from this Mac's real capacity (ON-1, D-12). Unreadable capacity: no plan is drawn at all.
    static func plan(capacityBytes: Int64?, freeBytes: Int64?) -> RoomOverviewPlanInput? {
        guard let c = capacityBytes, let f = freeBytes, c > 0, f >= 0, f <= c else { return nil }
        guard Double(c) / 1e9 / RoomPure.gbPerDot(capacityGB: Double(c) / 1e9) <= 260 else { return nil } // OVB §6 guard
        return RoomOverviewPlanInput(capacityBytes: c, freeBytes: f, goalBytes: nil)
    }
    /// ON-8: the plan is one image element.
    static func planAccessibility(capacityBytes: Int64, freeBytes: Int64, hidden: Bool,
                                  format: (Int64) -> String) -> String {
        if hidden {
            return String(localized: "onboarding.p1.a11y.hidden", defaultValue: "Your Mac. Sizes hidden.", bundle: RoomCopy.bundle)
        }
        let template = String(localized: "onboarding.p1.a11y", defaultValue: "Your Mac: %1$@ free of %2$@.", bundle: RoomCopy.bundle)
        return String.localizedStringWithFormat(template, format(freeBytes), format(capacityBytes))
    }
}
