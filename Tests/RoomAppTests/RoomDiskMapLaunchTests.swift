import Foundation
import Testing
@testable import RoomApp

/// REVIEW 2026-11-23 §3 Disk Map: open at the home map unless another folder was opened on purpose within a day.
struct RoomDiskMapLaunchTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func deepFolderFromYesterdayOpensAtHome() {
        let yesterday = now.addingTimeInterval(-RoomDiskMapLaunch.keepWindow - 60)
        #expect(!RoomDiskMapLaunch.keepsLastOpened(isHome: false, lastUsed: yesterday, now: now))
    }

    @Test func folderLeftOpenWithinADayStays() {
        let earlier = now.addingTimeInterval(-3 * 60 * 60)
        #expect(RoomDiskMapLaunch.keepsLastOpened(isHome: false, lastUsed: earlier, now: now))
    }

    @Test func homeMapAlwaysStays() {
        #expect(RoomDiskMapLaunch.keepsLastOpened(isHome: true, lastUsed: .distantPast, now: now))
        #expect(RoomDiskMapLaunch.keepWindow == 86_400)
    }
}
