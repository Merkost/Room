import Testing
@testable import RoomApp

struct RoomCachesHeroTests {
    @Test func readyOnlyOffersCheckInDirect() {
        let state = hero { $0.hasReport = false }
        #expect(state.primary == .check && state.heroBytes == nil && state.foundBytes == nil)
    }

    @Test func readyChoosesFolderInStore() {
        let state = hero { $0.hasReport = false; $0.store = true; $0.storeHasFolders = false }
        #expect(state.primary == .chooseFolderAndCheck && state.heroBytes == nil)
    }

    @Test func partialDisablesReviewWithReason() {
        let state = hero { $0.partial = true }
        #expect(state.lowerBound && state.heroBytes == nil && state.disabledReason == "Finish the check to review")
    }

    @Test func nothingClearableDrawsNoZero() {
        let state = hero { $0.clearableBytes = 0; $0.selectedBytes = 0 }
        #expect(state.heroBytes == nil && state.primary == .none)
    }

    @Test func unreadableSourceShowsRetryWithoutFigures() {
        let state = hero { $0.readableSourceCount = 0 }
        #expect(state.heroLabel == "Room couldn't read any caches." && state.primary == .check && state.heroBytes == nil)
    }

    @Test func selectedAndKeptUseTheSameReport() {
        let state = hero { $0.selectedBytes = 7 }
        #expect(state.heroLabel == "Selected to clear" && state.heroBytes == 7 && state.keptBytes == 41)
        #expect(state.primary == .review(7))
        let cleared = hero { $0.selectedBytes = 0 }
        #expect(cleared.heroLabel == "Clearable" && cleared.heroBytes == 8 && cleared.disabledReason != nil)
    }

    @Test func rememberedNeedsCheckAgain() {
        let state = hero { $0.hasReport = false; $0.remembered = true }
        #expect(state.primary == .checkAgain)
    }

    private func hero(_ edit: (inout RoomCachesHero.Input) -> Void) -> RoomCachesHero {
        var input = RoomCachesHero.Input(hasReport: true, remembered: false, partial: false,
            store: false, storeHasFolders: true, totalBytes: 49, clearableBytes: 8,
            selectedBytes: 8, sourceCount: 5, readableSourceCount: 5)
        edit(&input)
        return RoomCachesHero.make(input)
    }
}
