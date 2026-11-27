import Testing
@testable import RoomApp

/// What each screen puts in the dock, state by state.
@MainActor
struct RoomDockPlanTests {
    @Test func overviewScansThenStopsThenMakesRoom() {
        #expect(RoomOverviewDock.make(scanning: false, makeRoomBytes: 0) == .init(main: .scan))
        #expect(RoomOverviewDock.make(scanning: true, makeRoomBytes: 5) == .init(main: .stop))
        #expect(RoomOverviewDock.make(scanning: false, makeRoomBytes: 5) == .init(main: .makeRoom(bytes: 5), rescan: true))
    }

    @Test func cachesOfferTheFolderPickerWhenNoApprovedFolderCanBeRead() {
        let input = RoomCachesDock.Input(unreadableFolders: true, hasReport: true)
        #expect(RoomCachesDock.make(input) == .init(main: .chooseFolder))
    }

    @Test func cachesChecksThenReviews() {
        var input = RoomCachesDock.Input()
        #expect(RoomCachesDock.make(input) == .init(main: .check))
        input.needsFolder = true
        #expect(RoomCachesDock.make(input) == .init(main: .chooseFolder))
        input.needsFolder = false
        input.scanning = true
        #expect(RoomCachesDock.make(input) == .init(main: .stop))
        input.scanning = false
        input.hasReport = true
        input.reviewBytes = 7
        #expect(RoomCachesDock.make(input) == .init(main: .review(bytes: 7), checkAgain: true))
        input.partial = true
        #expect(RoomCachesDock.make(input) == .init(main: .check), "a partial result is checked again, not reviewed")
        input.partial = false
        input.reviewBytes = 0
        input.movedWithNothingLeft = true
        #expect(RoomCachesDock.make(input) == .init(main: .check), "nothing left to review after a move")
        input.reviewBytes = nil
        #expect(RoomCachesDock.make(input) == .init(main: .check))
    }

    @Test func diskMapMapsThenRescansThenMovesWhatIsTicked() {
        var input = RoomDiskDock.Input()
        #expect(RoomDiskDock.make(input) == .init(main: .chooseFolder))
        input.pendingFolder = true
        #expect(RoomDiskDock.make(input) == .init(main: .mapPending, side: .chooseAnother))
        input.hasMap = true
        #expect(RoomDiskDock.make(input) == .init(main: .rescan, side: .mapAnother))
        input.cancelled = true
        #expect(RoomDiskDock.make(input) == .init(main: .mapAgain, side: .mapAnother))
        input.tickedBytes = 9
        #expect(RoomDiskDock.make(input) == .init(main: .moveToTrash(bytes: 9), side: .rescan))
        input.lostAccess = true
        #expect(RoomDiskDock.make(input) == .init(main: .chooseAgain), "a map without access cannot be moved or rescanned")
        input.showsMap = false
        #expect(RoomDiskDock.make(input) == .init(main: .none))
        input.scanning = true
        #expect(RoomDiskDock.make(input) == .init(main: .stop))
    }

    @Test func developerAsksForAFolderThenScans() {
        #expect(RoomDeveloperDock.make(scanning: false, hasFolders: false, hasResults: false) == .init(main: .chooseProjects))
        #expect(RoomDeveloperDock.make(scanning: false, hasFolders: true, hasResults: false) == .init(main: .scan(again: false)))
        #expect(RoomDeveloperDock.make(scanning: false, hasFolders: true, hasResults: true) == .init(main: .scan(again: true)))
        #expect(RoomDeveloperDock.make(scanning: true, hasFolders: true, hasResults: true) == .init(main: .stop))
    }
}
