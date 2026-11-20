import Foundation
import Testing
@testable import RoomApp

struct RoomActivityBoardTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let idle = RoomActivityPillState.idle(freeBytes: nil)

    @Test func needsAccessPrecedesScanAndFailedStates() {
        var board = RoomActivityBoard()
        board.post(.scanning(tool: .caches, location: "Gradle", files: 3, bytes: 20), from: .caches, at: now)
        board.post(.failed(action: "Couldn't move selected caches"), from: .makeRoom, at: now)
        board.post(.needsAccess(folders: 2), from: .access, at: now)
        #expect(board.visible(now: now, idle: idle) == .needsAccess(folders: 2))
        board.clear(.access)
        #expect(board.visible(now: now, idle: idle) == .failed(action: "Couldn't move selected caches"))
    }

    @Test func pauseNeverRevivesAlreadyExpiredPosts() {
        var board = RoomActivityBoard()
        board.post(.ok(sentence: "Caches checked"), from: .caches, at: now)
        let after = now.addingTimeInterval(4)
        board.pause(at: after)
        #expect(board.visible(now: after, idle: idle) == idle)
        #expect(board.nextExpiry(now: after) == nil)
    }

    @Test func postsDuringPauseReceiveOnlyTheirRemainingHold() {
        var board = RoomActivityBoard()
        board.pause(at: now)
        board.post(.ok(sentence: "Caches checked"), from: .caches, at: now.addingTimeInterval(5))
        let resume = now.addingTimeInterval(10)
        board.resume(at: resume)
        #expect(board.nextExpiry(now: resume) == resume.addingTimeInterval(2.6))
    }

    @Test func rollingLabelRetainsOnlyNewestReportedPath() {
        var label = RoomRollingLabel()
        #expect(label.offer("/build", at: now) == "/build")
        #expect(label.offer("/gradle", at: now.addingTimeInterval(0.1)) == nil)
        #expect(label.offer("/swiftpm", at: now.addingTimeInterval(0.2)) == nil)
        #expect(label.flush(at: now.addingTimeInterval(0.5)) == "/swiftpm")
    }

    @Test func pathAbbreviationRequiresDirectoryBoundary() {
        #expect(RoomPillPath.abbreviate("/Users/me/Cache", home: "/Users/me") == "~/Cache")
        #expect(RoomPillPath.abbreviate("/Users/me2/Cache", home: "/Users/me") == "/Users/me2/Cache")
    }
}
