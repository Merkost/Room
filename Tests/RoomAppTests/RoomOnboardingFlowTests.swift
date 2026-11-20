import Testing
@testable import RoomApp

struct RoomOnboardingFlowTests {
    @Test func upgradeShowsWelcomeOnce() {
        #expect(RoomOnboardingFlow.shouldShow(storedVersion: 0))
        #expect(RoomOnboardingFlow.shouldShow(storedVersion: 1))
        #expect(!RoomOnboardingFlow.shouldShow(storedVersion: 2))
        #expect(!RoomOnboardingFlow.shouldShow(storedVersion: 3))
    }

    @Test func directAndStorePickBeforeMapping() {
        #expect(RoomOnboardingFlow.effects(.mapFolder, edition: .direct) == [
            .markSeen, .close, .navigate("disk"), .chooseDiskFolder,
        ])
        #expect(RoomOnboardingFlow.effects(.mapFolder, edition: .store) == [
            .markSeen, .close, .navigate("disk"), .chooseHomeAccess,
        ])
    }

    @Test func cachesAndMenuBarUseEditionAppropriateActions() {
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .direct).last == .startCachesCheck)
        #expect(RoomOnboardingFlow.effects(.checkCaches, edition: .store).last == .chooseStoreCachesFolder)
        #expect(RoomOnboardingFlow.effects(.menuBar, edition: .direct) == [.markSeen, .close, .enableMenuBar, .showMonitorOnce])
    }

    @Test func skipsWithoutChangingDestination() {
        #expect(RoomOnboardingFlow.skipEffects == [.markSeen, .close])
    }

    @Test func choicesDisabledWhileWorking() {
        #expect(RoomOnboardingFlow.choicesEnabled(isWorking: false))
        #expect(!RoomOnboardingFlow.choicesEnabled(isWorking: true))
        #expect(RoomOnboardingChoice.allCases.filter(RoomOnboardingFlow.isProminent) == [.mapFolder])
    }

    @Test func unreadableOrOversizedCapacityDoesNotDrawFakePlan() {
        #expect(RoomOnboardingFlow.plan(capacityBytes: nil, freeBytes: 5) == nil)
        #expect(RoomOnboardingFlow.plan(capacityBytes: 50, freeBytes: 60) == nil)
        #expect(RoomOnboardingFlow.plan(capacityBytes: 27_000_000_000_000, freeBytes: 5) == nil)
        let measured = RoomOnboardingFlow.plan(capacityBytes: 994_000_000_000, freeBytes: 312_000_000_000)
        #expect(measured?.freeBytes == 312_000_000_000 && measured?.goalBytes == nil)
    }

    @Test func maskedAccessibilityOmitsActualBytes() {
        let hidden = RoomOnboardingFlow.planAccessibility(capacityBytes: 994, freeBytes: 312, hidden: true,
                                                          format: { "\($0) GB" })
        #expect(hidden == "Your Mac. Sizes hidden.")
        let visible = RoomOnboardingFlow.planAccessibility(capacityBytes: 994, freeBytes: 312, hidden: false,
                                                           format: { "\($0) GB" })
        #expect(visible == "Your Mac: 312 GB free of 994 GB.")
    }
}
