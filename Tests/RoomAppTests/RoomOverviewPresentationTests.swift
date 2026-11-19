import Foundation
import Testing
@testable import RoomApp

@Suite @MainActor
struct RoomOverviewPresentationTests {
    private let sample = RoomVolumeCapacity(capacityBytes: 994_000_000_000, freeBytes: 312_000_000_000)

    @Test func expiryUsesSingleExactDeadline() throws {
        let at = Date(timeIntervalSince1970: 1_800_014_400) // noon UTC
        let clock = TestClock(now: at.addingTimeInterval(86_399))
        let model = RoomOverviewModel(now: { clock.now })
        let check = RoomCachesCheck(at: at, bytes: 8_400_000_000, partial: false)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        model.update(capacity: sample, goalBytes: nil, caches: check, calendar: calendar)
        #expect(model.snapshot.action == .makeRoom(bytes: check.bytes, partial: false))
        #expect(model.nextCacheUpdateAt == at.addingTimeInterval(86_400))
        clock.now = try #require(model.nextCacheUpdateAt)
        model.update(capacity: sample, goalBytes: nil, caches: check, calendar: calendar)
        #expect(model.snapshot.action == .checkCaches)
        #expect(model.cacheCaption != nil)
    }

    @Test func invalidatedSizeNeverPromised() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let model = RoomOverviewModel(now: { date })
        let check = RoomCachesCheck(at: date, bytes: 8_400_000_000, partial: false)
        model.update(capacity: sample, goalBytes: nil, caches: check, invalidatedAt: date)
        #expect(model.snapshot.action == .checkCaches)
        #expect(!model.snapshot.sentence.contains("8.4"))
        #expect(model.cacheCaption == "Checked just now")
    }

    @Test func overviewHideTitleAndShortcut() throws {
        let visible = RoomMenuModel.make(.init(destination: .overview, window: .main))
        let command = try #require(visible.first { $0.id == .hideOverviewSizes })
        #expect(command.title == "Hide Sizes on Overview")
        #expect(command.shortcut == .init("h", [.command, .shift]))
        #expect(command.checked == false)
    }

    @Test func overviewHideChecksCurrentState() {
        let hidden = RoomMenuModel.make(.init(destination: .overview, overviewSizesHidden: true, window: .main))
        #expect(hidden.first { $0.id == .hideOverviewSizes }?.checked == true)
        for context in [
            RoomMenuModel.Input(destination: .overview, window: .modal),
            RoomMenuModel.Input(destination: .overview, window: .settings),
            RoomMenuModel.Input(destination: .clean, window: .main),
        ] {
            #expect(!RoomMenuModel.make(context).contains { $0.id == .hideOverviewSizes })
        }
    }

    @MainActor private final class TestClock {
        var now: Date
        init(now: Date) { self.now = now }
    }
}
