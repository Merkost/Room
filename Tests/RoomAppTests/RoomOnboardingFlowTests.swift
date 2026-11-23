import CoreGraphics
import Foundation
import Testing
@testable import RoomApp

/// ONBOARDING-V3-SPEC §12: the reference checks ONC-01...ONC-40, ported, plus the work-package tests that need no UI.
@MainActor
struct RoomOnboardingFlowTests {
    private let gb: Int64 = 1_000_000_000
    private func format(_ bytes: Int64) -> String {
        let v = Double(bytes) / 1e9
        return v >= 100 || v == v.rounded() ? "\(Int(v.rounded())) GB" : String(format: "%.1f GB", v)
    }
    private let direct = RoomOnboardingContext(edition: .direct, isWorking: false, motionIsFull: true)
    private let store = RoomOnboardingContext(edition: .store, isWorking: false, motionIsFull: true)
    private let busy = RoomOnboardingContext(edition: .direct, isWorking: true, motionIsFull: true)
    private let reduced = RoomOnboardingContext(edition: .direct, isWorking: false, motionIsFull: false)
    private let onStep3 = RoomOnboardingState(step: .firstStep, beat: .review, finished: false)
    private let onStep2 = RoomOnboardingState(step: .yourSay, beat: .review, finished: false)
    private let editions: [RoomOnboardingEdition] = [.direct, .store]

    private func run(_ events: [RoomOnboardingEvent], _ ctx: RoomOnboardingContext? = nil,
                     from start: RoomOnboardingState = .init()) -> (RoomOnboardingState, [RoomOnboardingEffect]) {
        var s = start, fx: [RoomOnboardingEffect] = []
        for e in events {
            let (n, f) = RoomOnboardingFlow.reduce(s, e, ctx ?? direct)
            s = n
            if !f.isEmpty { fx = f }
        }
        return (s, fx)
    }

    private func drawn(_ state: RoomOnboardingPlanState) -> RoomOverviewPlanInput? {
        if case .drawn(let p) = state { return p }
        return nil
    }

    // MARK: Versions

    @Test func onc01_ShownToNewAnd1xNotToV2Viewers() {
        #expect(RoomOnboardingFlow.version == 2)
        #expect(RoomOnboardingFlow.shouldShow(storedVersion: 0) && RoomOnboardingFlow.shouldShow(storedVersion: 1))
        #expect(!RoomOnboardingFlow.shouldShow(storedVersion: 2) && !RoomOnboardingFlow.shouldShow(storedVersion: 3))
    }

    // MARK: Keyboard and step machine

    @Test func onc02_ReturnAdvancesOneStepAtATime() {
        #expect(run([.key(.returnKey)]).0.step == .yourSay)
        #expect(run([.key(.returnKey), .key(.returnKey)]).0.step == .firstStep)
    }

    @Test func onc03_RightStopsAtFirstStepAndNeverChooses() {
        let r = run([.key(.right), .key(.right), .key(.right), .key(.right)])
        #expect(r.0.step == .firstStep && r.1.isEmpty && !r.0.finished)
    }

    @Test func onc04_LeftGoesBackAndStopsAtYourMac() {
        #expect(run([.key(.left)], from: onStep3).0.step == .yourSay)
        #expect(run([.key(.left), .key(.left), .key(.left)], from: onStep3).0.step == .yourMac)
    }

    @Test func onc05_ReturnOnFirstStepPressesMapHome() {
        let r = run([.key(.returnKey)], from: onStep3)
        #expect(r.0.finished && r.1 == RoomOnboardingFlow.effects(.mapHome, edition: .direct))
    }

    @Test func onc06_ReturnWhileWorkingDoesNothing() {
        let r = run([.key(.returnKey)], busy, from: onStep3)
        #expect(!r.0.finished && r.1.isEmpty && r.0.step == .firstStep)
    }

    @Test func onc07_EscSkipsFromEveryStepEvenWhileWorking() {
        for step in RoomOnboardingStep.allCases {
            let r = run([.key(.escape)], busy, from: .init(step: step, beat: .review, finished: false))
            #expect(r.0.finished && r.1 == [.markSeen, .close])
        }
    }

    @Test func onc08_EventsAfterFinishAreIgnored() {
        let r = run([.key(.escape), .key(.left), .choose(.menuBar)])
        #expect(r.1 == RoomOnboardingFlow.skipEffects && r.0.step == .yourMac)
    }

    @Test func onc09_ChoicesOnlyOnFirstStep() {
        #expect(run([.choose(.mapHome)]).1.isEmpty)
        #expect(run([.choose(.checkCaches)], from: onStep2).1.isEmpty)
    }

    // MARK: Effects: existing entry points only

    private var mapFx: [RoomOnboardingEffect] { [.markSeen, .close, .navigate("overview"), .scanHome(confirmed: true)] }

    @Test func onc10_MapHomeLandsOnOverviewDirect() {
        #expect(RoomOnboardingFlow.effects(.mapHome, edition: .direct) == mapFx)
    }

    @Test func onc11_MapHomeLandsOnOverviewStore() {
        #expect(RoomOnboardingFlow.effects(.mapHome, edition: .store) == mapFx)
    }

    @Test func onc12_CachesDirectScansStorePicksFirst() {
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .direct) == [.markSeen, .close, .navigate("clean"), .startCachesCheck])
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .store) == [.markSeen, .close, .navigate("clean"), .chooseStoreCachesFolder])
    }

    @Test func onc13_MenuBarNeedsNoScanAndNoRoute() {
        for edition in editions {
            #expect(RoomOnboardingFlow.effects(.menuBar, edition: edition) == [.markSeen, .close, .enableMenuBar, .showMonitorOnce])
        }
    }

    @Test func onc14_EveryChoiceMarksSeenAndClosesSkipNeverScans() {
        for choice in RoomOnboardingChoice.allCases {
            for edition in editions {
                #expect(Array(RoomOnboardingFlow.effects(choice, edition: edition).prefix(2)) == [.markSeen, .close])
            }
        }
        #expect(!RoomOnboardingFlow.skipEffects.contains(where: Self.startsWork))
    }

    @Test func onc15_OnlyMapHomeIsProminent() {
        #expect(RoomOnboardingChoice.allCases.filter(RoomOnboardingFlow.isProminent) == [.mapHome])
    }

    // MARK: The plan of this Mac

    @Test func onc16_SpecFixture78FreeRingsNoKindsNoGoal() throws {
        let p = try #require(drawn(.make(capacityBytes: 994 * gb, freeBytes: 312 * gb)))
        #expect(p.freeDots == 78 && p.notMappedDots == 0 && p.goalBytes == nil && p.gbPerDot == 4)
    }

    @Test func onc17_OwnerFixture32RingsAt2GB() throws {
        let p = try #require(drawn(.make(capacityBytes: 494 * gb, freeBytes: 64 * gb)))
        #expect(p.freeDots == 32 && p.gbPerDot == 2 && p.notMappedBytes == 430 * gb)
    }

    @Test func onc18_UnreadableDrawsNothing() {
        let states: [RoomOnboardingPlanState] = [
            .make(capacityBytes: nil, freeBytes: 1), .make(capacityBytes: 10 * gb, freeBytes: nil),
            .make(capacityBytes: 0, freeBytes: 0), .make(capacityBytes: 10 * gb, freeBytes: -1),
            .make(capacityBytes: 10 * gb, freeBytes: 11 * gb),
        ]
        #expect(states.allSatisfy { $0 == .unreadable })
    }

    @Test func onc19_Over26TBIsMeasuredButNotDrawn() {
        let huge = RoomOnboardingPlanState.make(capacityBytes: 40_000 * gb, freeBytes: 9_000 * gb)
        #expect(huge == .tooLarge(capacityBytes: 40_000 * gb, freeBytes: 9_000 * gb))
        #expect(RoomOnboardingPlanState.make(capacityBytes: 26_000 * gb, freeBytes: gb) != .unreadable)
        #expect(RoomOnboardingCopy.lead(.yourMac, plan: huge, hidden: false, format: format).strong
                == "This is your Mac: 9000 GB free of 40000 GB.")
        #expect(RoomOnboardingCopy.lead(.yourMac, plan: huge, hidden: false, format: format).secondary
                == "Room draws plans of disks up to 26 TB for now.")
    }

    @Test func onc20_ZeroFreeIsAMeasurementNotAFailure() throws {
        let full = RoomOnboardingPlanState.make(capacityBytes: 494 * gb, freeBytes: 0)
        let p = try #require(drawn(full))
        #expect(p.freeDots == 0)
        #expect(RoomOnboardingCopy.lead(.yourMac, plan: full, hidden: false, format: format).strong == "This is your Mac: 0 GB free of 494 GB.")
    }

    @Test func onc40_26TBIsTheLastDrawnSize() throws {
        let edge = try #require(drawn(.make(capacityBytes: 26_000 * gb, freeBytes: 2_000 * gb)))
        #expect(edge.gbPerDot == 100 && edge.freeDots == 20)
    }

    // MARK: Copy selection

    @Test func onc21_YourMacLeadNamesTheMeasuredFigures() {
        let lead = RoomOnboardingCopy.lead(.yourMac, plan: .make(capacityBytes: 494 * gb, freeBytes: 64 * gb), hidden: false, format: format)
        #expect(lead.strong == "This is your Mac: 64 GB free of 494 GB.")
        #expect(lead.secondary == "Room draws only what it has measured.")
    }

    @Test func onc22_HideRemovesEveryDigit() throws {
        let owner = RoomOnboardingPlanState.make(capacityBytes: 494 * gb, freeBytes: 64 * gb)
        let p = try #require(drawn(owner))
        let hasDigit: (String) -> Bool = { $0.contains(where: \.isNumber) }
        #expect(!hasDigit(RoomOnboardingCopy.lead(.yourMac, plan: owner, hidden: true, format: format).strong ?? "1"))
        #expect(!hasDigit(RoomOnboardingCopy.freeLegend(p, hidden: true, format: format)))
        #expect(!hasDigit(RoomOnboardingCopy.unitCaption(p, hidden: true)))
        #expect(!hasDigit(RoomOnboardingCopy.notMappedDetail(p, hidden: true, format: format)))
        #expect(RoomOnboardingCopy.planAccessibility(owner, hidden: true, format: format) == "Your Mac. Sizes hidden.")
    }

    @Test func onc23_CaptionAndLegendFromThePlan() throws {
        let p = try #require(drawn(.make(capacityBytes: 494 * gb, freeBytes: 64 * gb)))
        #expect(RoomOnboardingCopy.unitCaption(p, hidden: false) == "1 dot = about 2 GB")
        #expect(RoomOnboardingCopy.freeLegend(p, hidden: false, format: format) == "Free 64 GB")
        #expect(RoomOnboardingCopy.notMappedDetail(p, hidden: false, format: format) == "430 GB used. Room hasn’t looked inside.")
    }

    @Test func onc24_UnreadableLeadHasNoNumberAndNoZero() {
        let lead = RoomOnboardingCopy.lead(.yourMac, plan: .unreadable, hidden: false, format: format)
        #expect(lead.strong == nil && !lead.secondary.contains(where: \.isNumber))
        #expect(RoomOnboardingCopy.planAccessibility(.unreadable, hidden: false, format: format) == "Your Mac. Free space not available yet.")
    }

    @Test func onc25_EllipsisOnlyWhenThePickerFollows() {
        #expect(RoomOnboardingCopy.mapTitle(needsPicker: true) == "Map my home folder…")
        #expect(RoomOnboardingCopy.mapTitle(needsPicker: false) == "Map my home folder")
    }

    @Test func onc26_MapContextPerEditionAndPicker() {
        #expect(RoomOnboardingCopy.mapContext(edition: .direct, needsPicker: true)
                == "Next: macOS asks you to choose your home folder. Pictures and Music stay out. Full Disk Access is optional.")
        #expect(RoomOnboardingCopy.mapContext(edition: .store, needsPicker: false)
                == "Room starts mapping right away. Pictures and Music stay out. Room reads sizes, never file contents.")
        #expect(!RoomOnboardingCopy.mapContext(edition: .store, needsPicker: true).contains("Full Disk Access"))
    }

    @Test func onc27_StoreCachesCarriesEllipsis() {
        #expect(RoomOnboardingCopy.cachesTitle(edition: .store) == "Check caches…")
        #expect(RoomOnboardingCopy.cachesTitle(edition: .direct) == "Check caches")
    }

    @Test func onc28_PipsSpeakTheProgress() {
        #expect(RoomOnboardingCopy.stepNumber(.yourMac) == "1 of 3")
        #expect(RoomOnboardingCopy.stepNumber(.firstStep) == "3 of 3")
    }

    /// The welcome is nearly wordless: a title of two to four words and one line of eight words or fewer per step.
    @Test func scenesStayNearlyWordless() {
        let words: (String) -> Int = { $0.split(separator: " ").count }
        let plans: [RoomOnboardingPlanState] = [.make(capacityBytes: 494 * gb, freeBytes: 64 * gb), .unreadable,
                                                .make(capacityBytes: 40_000 * gb, freeBytes: 9_000 * gb)]
        for step in RoomOnboardingStep.allCases {
            #expect((2...4).contains(words(RoomOnboardingCopy.title(step))), "\(step)")
            for plan in plans { #expect(words(RoomOnboardingCopy.line(step, plan: plan)) <= 8, "\(step)") }
        }
        #expect(words(RoomOnboardingCopy.busy) <= 8)
        #expect(RoomOnboardingCopy.title(.yourMac) == "Meet your Mac")
        #expect(RoomOnboardingCopy.freeUnit("GB") == "GB free")
        for edition in editions {
            for picker in [false, true] { #expect(words(RoomOnboardingCopy.mapTitle(needsPicker: picker)) <= 4) }
            #expect(words(RoomOnboardingCopy.cachesTitle(edition: edition)) <= 4)
        }
        #expect(words(RoomOnboardingCopy.menuBarTitle) <= 4)
    }

    // MARK: The example on step 2

    @Test func onc29_DemoTicksOnceOnlyInFullMotionOnStep2() {
        #expect(run([.demoTick], from: onStep2).0.beat == .trashed)
        #expect(run([.demoTick], reduced, from: onStep2).0.beat == .review)
        #expect(run([.demoTick]).0.beat == .review)
        #expect(run([.demoTick, .demoTick], from: onStep2).0.beat == .trashed)
    }

    @Test func onc30_PutBackOnlyAfterTrashInFullMotion() {
        #expect(run([.demoPutBack], from: onStep2).0.beat == .review)
        #expect(run([.demoTick, .demoPutBack], from: onStep2).0.beat == .restored)
    }

    @Test func onc31_TriptychPutBackWorksWithoutAutoPlay() {
        #expect(run([.demoPutBack], reduced, from: onStep2).0.beat == .restored)
    }

    @Test func onc32_ReenteringStep2RestartsTheExample() {
        let r = run([.demoTick, .demoPutBack, .key(.right), .key(.left)], from: onStep2).0
        #expect(r.step == .yourSay && r.beat == .review)
    }

    @Test func onc33_ReduceMotionShowsTriptych() {
        #expect(RoomOnboardingFlow.demoLayout(beat: .review, motionIsFull: false) == .triptych(highlight: .review))
        #expect(RoomOnboardingFlow.demoLayout(beat: .trashed, motionIsFull: true) == .single(.trashed))
    }

    @Test func demoTrashSendsTheRoomInAndCanReplay() {
        for ctx in [direct, reduced] {
            #expect(run([.demoTrash], ctx, from: onStep2).0.beat == .trashed)
            #expect(run([.demoTrash, .demoPutBack], ctx, from: onStep2).0.beat == .restored)
            #expect(run([.demoTrash, .demoPutBack, .demoTrash], ctx, from: onStep2).0.beat == .trashed)
            #expect(run([.demoTrash, .demoTrash], ctx, from: onStep2).0.beat == .trashed)
        }
        #expect(run([.demoTrash]).0 == RoomOnboardingState())
        #expect(run([.demoTrash], from: onStep3).0 == onStep3)
    }

    @Test func onc34_DemoNeverEmitsEffects() {
        for event in [RoomOnboardingEvent.demoTick, .demoTrash, .demoPutBack, .demoTick, .demoPutBack] {
            #expect(RoomOnboardingFlow.reduce(onStep2, event, direct).1.isEmpty)
        }
    }

    // MARK: Geometry on the two stage sizes, through the shared RoomDotPlan

    @Test func onc35to37_StageGeometry() throws {
        let p = try #require(drawn(.make(capacityBytes: 494 * gb, freeBytes: 64 * gb)))
        let q = try #require(drawn(.make(capacityBytes: 994 * gb, freeBytes: 312 * gb)))
        let sizes = [RoomOnboardingStage.layoutSize(wallHeight: RoomOnboardingStage.introWallHeight),
                     RoomOnboardingStage.layoutSize(wallHeight: RoomOnboardingStage.chooseWallHeight)]
        // ONC-35 every free ring is placed on both stages
        #expect(sizes.allSatisfy { p.layout(size: $0).dots.count == p.freeDots && q.layout(size: $0).dots.count == q.freeDots })
        // ONC-36 stage sizes
        #expect(sizes == [CGSize(width: 590, height: 286), CGSize(width: 590, height: 118)])
        #expect(RoomOnboardingStage.wallHeight(for: .yourSay) == 296 && RoomOnboardingStage.wallHeight(for: .firstStep) == 128)
        // ONC-37 rings stay inside the free room and none sit in Not mapped
        let plan = p.layout(size: sizes[0])
        let free = try #require(plan.rooms.first { $0.id == .free }).rect
        #expect(plan.dots.allSatisfy { $0.room == .free && free.insetBy(dx: -0.5, dy: -0.5).contains($0.center) })
    }

    // MARK: Copy lint

    @Test func onc38_CopyHasNoExclamationNoEmDashSentenceCase() {
        let hits = RoomOnboardingCopy.allStrings(format: format).flatMap { s in
            RoomOnboardingCopyLint.violations(s).map { "\(s) → \($0)" }
        }
        #expect(hits.isEmpty, "\(hits)")
    }

    @Test func onc39_LintCatchesItsOwnRules() {
        #expect(!RoomOnboardingCopyLint.violations("Map My Home Folder").isEmpty)
        #expect(!RoomOnboardingCopyLint.violations("Ready!").isEmpty)
        #expect(!RoomOnboardingCopyLint.violations("Room \u{2014} calm").isEmpty)
        #expect(RoomOnboardingCopyLint.violations("Room draws only what it has measured. Room waits.").isEmpty)
    }

    /// ONV-6: ONC-38's rules over every `onboarding.v3.*` value in the String Catalogue, and the v2 keys are gone.
    @Test func copyLintOnboardingKeys() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp/Resources/Localizable.xcstrings")
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try #require(document["strings"] as? [String: [String: Any]])
        let v3 = rows.filter { $0.key.hasPrefix("onboarding.v3.") }
        #expect(v3.count >= 45)
        for (key, row) in v3 {
            let unit = ((row["localizations"] as? [String: Any])?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = try #require(unit?["value"] as? String, "\(key)")
            #expect(RoomOnboardingCopyLint.violations(value).isEmpty, "\(key): \(value)")
            #expect(RoomCopy.bundle.localizedString(forKey: key, value: "missing", table: nil) == value, "\(key)")
        }
        let v2 = rows.keys.filter { $0.hasPrefix("onboarding.p") }.sorted()
        #expect(v2 == ["onboarding.p1.continue", "onboarding.p2.back", "onboarding.p2.skip"])
    }

    // MARK: Work-package tests (pure)

    @Test func returnAdvancesThenChoosesMapHome() {
        let r = run([.key(.returnKey), .key(.returnKey), .key(.returnKey)], store)
        #expect(r.0.finished && r.1 == mapFx)
    }

    @Test func arrowsNeverChoose() {
        for step in RoomOnboardingStep.allCases {
            for key in [RoomOnboardingKey.left, .right] {
                let r = run([.key(key), .key(key), .key(key)], from: .init(step: step, beat: .review, finished: false))
                #expect(r.1.isEmpty && !r.0.finished)
            }
        }
    }

    @Test func escSkipsFromEveryStep() {
        for step in RoomOnboardingStep.allCases {
            for event in [RoomOnboardingEvent.key(.escape), .skipPressed] {
                let r = run([event], from: .init(step: step, beat: .review, finished: false))
                #expect(r.0.finished && r.1 == RoomOnboardingFlow.skipEffects)
            }
        }
    }

    @Test func choicesDisabledWhileWorking() {
        #expect(RoomOnboardingFlow.choicesEnabled(isWorking: false) && !RoomOnboardingFlow.choicesEnabled(isWorking: true))
        for choice in RoomOnboardingChoice.allCases {
            let r = run([.choose(choice)], busy, from: onStep3)
            #expect(r.1.isEmpty && !r.0.finished)
        }
        #expect(run([.skipPressed], busy, from: onStep3).1 == RoomOnboardingFlow.skipEffects)
    }

    @Test func skipStartsNothing() {
        #expect(RoomOnboardingFlow.skipEffects == [.markSeen, .close])
        #expect(!RoomOnboardingFlow.skipEffects.contains { if case .navigate = $0 { true } else { false } })
    }

    @Test func menuBarChoiceKeepsDestination() {
        for edition in editions {
            #expect(!RoomOnboardingFlow.effects(.menuBar, edition: edition).contains { if case .navigate = $0 { true } else { false } })
        }
    }

    @Test func checkCachesDirectStartsScanOnCaches() {
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .direct).suffix(2) == [.navigate("clean"), .startCachesCheck])
    }

    @Test func checkCachesStoreOpensPicker() {
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .store).last == .chooseStoreCachesFolder)
    }

    /// The example's events never produce an effect on any step, in any motion (the view's buttons only send these).
    @Test func exampleNeverTouchesFiles() {
        for step in RoomOnboardingStep.allCases {
            for ctx in [direct, reduced, store] {
                let r = run([.demoTick, .demoTrash, .demoPutBack, .demoTick, .demoTrash, .demoPutBack], ctx,
                            from: .init(step: step, beat: .review, finished: false))
                #expect(r.1.isEmpty && !r.0.finished && r.0.step == step)
            }
        }
    }

    @Test func demoTickCancelledWhenLeavingStep2() {
        let left = run([.key(.right)], from: onStep2).0
        #expect(run([.demoTick], from: left).0 == left)
        let back = run([.key(.left)], from: onStep2).0
        #expect(run([.demoTick], from: back).0.beat == .review)
    }

    @Test func reenteringStep2RestartsExample() {
        let restored = run([.demoTick, .demoPutBack], from: onStep2).0
        #expect(restored.beat == .restored)
        #expect(run([.key(.left), .continuePressed], from: restored).0.beat == .review)
    }

    @Test func triptychWhenMotionReduced() {
        for beat in RoomDemoBeat.allCases {
            #expect(RoomOnboardingFlow.demoLayout(beat: beat, motionIsFull: false) == .triptych(highlight: beat))
        }
    }

    @Test func hiddenAccessibilityHasNoDigits() {
        for plan in [RoomOnboardingPlanState.make(capacityBytes: 494 * gb, freeBytes: 64 * gb), .unreadable,
                     .make(capacityBytes: 40_000 * gb, freeBytes: 9_000 * gb)] {
            let spoken = RoomOnboardingCopy.planAccessibility(plan, hidden: true, format: format)
            #expect(!spoken.contains { $0.isNumber })
        }
    }

    @Test func planAccessibilityNamesNotMapped() {
        let owner = RoomOnboardingPlanState.make(capacityBytes: 494 * gb, freeBytes: 64 * gb)
        #expect(RoomOnboardingCopy.planAccessibility(owner, hidden: false, format: format)
                == "Your Mac: 64 GB free of 494 GB. 430 GB not mapped yet.")
    }

    @Test func noScrollViewInSheet() throws {
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp/Views", isDirectory: true)
        for path in ["RoomOnboardingView.swift", "Onboarding/RoomOnboardingPlanView.swift", "Onboarding/RoomOnboardingExample.swift",
                     "Onboarding/RoomOnboardingTiles.swift"] {
            let source = try String(contentsOf: views.appendingPathComponent(path), encoding: .utf8)
            #expect(!source.contains("ScrollView"), "\(path)")
            #expect(!source.contains("TimelineView"), "\(path)")
            #expect(!source.contains("Motion.success"), "\(path)")
            #expect(!source.contains("rotationEffect") && !source.contains("rotation3DEffect"), "\(path)")
        }
    }

    @Test func sheetTokensMatchTheSpec() {
        typealias O = RoomTokens.Onboarding
        #expect(O.width == 680 && O.height == 540)
        // Pips, header, the scene and the footer fit the fixed sheet with no scroll view, with room to breathe.
        let used = O.top + O.headerHeight + O.headerToStage
            + RoomOnboardingStage.introWallHeight + O.footerHeight + O.bottom
        #expect(used <= O.height - 16, "\(used)")
        #expect(RoomOnboardingStage.chooseWallHeight + O.stageToTiles + O.tileHeight <= RoomOnboardingStage.introWallHeight)
        #expect(O.width - 2 * O.side == RoomOnboardingStage.width)
    }

    private static func startsWork(_ effect: RoomOnboardingEffect) -> Bool {
        switch effect {
        case .scanHome, .chooseStoreCachesFolder, .startCachesCheck: true
        default: false
        }
    }
}
