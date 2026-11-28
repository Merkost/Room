import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomRowActivityTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func working(_ done: Int, of: Int?) -> RoomRowSignal {
        RoomRowSignal(working: true, done: done, of: of, sentence: "Checking \(done) of \(of ?? 0) places",
                      doneSentence: "Found 22 GB")
    }

    @Test func workingFillsTheRingAndCountsDots() {
        var row = RoomRowActivity()
        #expect(!row.showsSentence && row.fraction == nil && row.dots == nil)
        row.apply(working(4, of: 11), isOpen: false, now: t0)
        #expect(row.phase == .working && row.showsSentence)
        #expect(row.fraction == 4.0 / 11)
        #expect(row.dots?.total == 11 && row.dots?.filled == 4)
        row.apply(working(30, of: 48), isOpen: false, now: t0)
        #expect(row.dots?.total == 12, "at most twelve dots")
        #expect(row.dots?.filled == 8)
        row.apply(working(3, of: nil), isOpen: false, now: t0)
        #expect(row.fraction == nil && row.dots == nil, "no total: a plain track and no counted dots")
    }

    @Test func finishingShowsTheCheckThenSettlesAfterFourSeconds() {
        var row = RoomRowActivity()
        row.apply(working(10, of: 11), isOpen: false, now: t0)
        let finished = row.apply(.idle.with(done: "Found 22 GB"), isOpen: false, now: t0)
        #expect(finished)
        #expect(row.phase == .finished && row.showsCheck && row.fraction == 1)
        #expect(row.sentence == "Found 22 GB")
        #expect(row.unseen, "finished away from the place: waits to be seen")
        row.settle(now: t0.addingTimeInterval(3))
        #expect(row.phase == .finished, "still showing at 3 s")
        row.settle(now: t0.addingTimeInterval(4))
        #expect(row.phase == .idle && !row.showsSentence)
        #expect(row.unseen, "the dot and accent value stay until the place is opened")
        row.open()
        #expect(!row.unseen)
    }

    @Test func finishingWhileOpenIsAlreadySeen() {
        var row = RoomRowActivity()
        row.apply(working(1, of: 2), isOpen: true, now: t0)
        row.apply(.idle.with(done: "All clear"), isOpen: true, now: t0)
        #expect(!row.unseen)
    }

    @Test func failureIsOnePlainSentenceUntilOpened() {
        var row = RoomRowActivity()
        row.apply(working(4, of: 11), isOpen: false, now: t0)
        var signal = RoomRowSignal.idle
        signal.failure = "Could not read 2 places"
        let finished = row.apply(signal, isOpen: false, now: t0)
        #expect(!finished)
        #expect(row.phase == .failed && row.sentence == "Could not read 2 places" && !row.showsCheck)
        #expect(row.fraction == nil)
        row.open()
        #expect(row.phase == .idle)
    }

    @Test func stopReturnsToRestWithoutACheck() {
        var row = RoomRowActivity()
        row.apply(working(4, of: 11), isOpen: false, now: t0)
        row.stop()
        #expect(row.phase == .idle && !row.showsCheck && !row.unseen)
        let finished = row.apply(.idle, isOpen: false, now: t0)
        #expect(!finished, "an idle signal after Stop does not finish")
    }

    @Test func idleSignalsLeaveARestingRowAlone() {
        var row = RoomRowActivity()
        let finished = row.apply(.idle, isOpen: false, now: t0)
        #expect(!finished)
        #expect(row == RoomRowActivity())
    }

    @Test func trackerSettlesOnItsTimer() async throws {
        let tracker = RoomSidebarActivity(settleDelay: .milliseconds(20))
        tracker.update([.clean: working(1, of: 2)], open: .overview)
        tracker.update([.clean: .idle.with(done: "Found 2 GB")], open: .overview)
        #expect(tracker.row(.clean).phase == .finished)
        try await Task.sleep(for: .milliseconds(200))
        #expect(tracker.row(.clean).phase == .idle)
        #expect(tracker.row(.clean).unseen)
        tracker.open(.clean)
        #expect(!tracker.row(.clean).unseen)
    }

    @Test func sentencesUseTheFormatter() {
        let caches = RoomRowSignals.caches(isScanning: true, checked: 3, of: 11, clearableBytes: 22_400_000_000, unreadable: 0)
        #expect(caches.sentence == "Checking 4 of 11 places")
        #expect(caches.doneSentence == "Found 22 GB")
        #expect(RoomRowSignals.caches(isScanning: false, checked: 0, of: 0, clearableBytes: 0, unreadable: 2).failure
                == "Could not read 2 places")
        #expect(RoomRowSignals.caches(isScanning: false, checked: 0, of: 0, clearableBytes: 0, unreadable: 0).doneSentence == "All clear")
        let move = RoomRowSignals.makeRoom(isMoving: true, movedBytes: 7_000_000_000, totalBytes: 22_000_000_000,
                                           madeBytes: nil, failed: 0)
        #expect(move.sentence == "Moving 7 of 22 GB" && move.of == 22 && move.done == 7)
        #expect(move.doneSentence == "Made 22 GB")
        let developer = RoomRowSignals.developer(isScanning: false, progress: "", totalBytes: 120_000_000_000,
                                                 projects: 48, error: nil)
        #expect(developer.doneSentence == "120 GB in 48 projects")
        let map = RoomRowSignals.diskMap(isScanning: true, mapped: 2, of: 12)
        #expect(map.sentence == "Mapping 3 of 12 folders")
    }
}

private extension RoomRowSignal {
    func with(done: String) -> RoomRowSignal {
        var copy = self
        copy.doneSentence = done
        return copy
    }
}
