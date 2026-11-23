import Foundation
import Testing
@testable import RoomApp

struct RoomSignatureTests {
    let since = Date(timeIntervalSince1970: 1_600_000_000)

    @Test func interimSaysMovedNeverMade() {
        let signature = RoomSignature.make(ledgerMadeBytes: nil, ledgerCleanups: 0, ledgerSince: nil,
                                           movedKeptBytes: 12, movedCleanups: 2, movedSince: since)
        #expect(signature == .moved(bytes: 12, cleanups: 2, since: since))
        #expect(signature.caption(month: "March") == "moved to Trash since March, across 2 cleanups")
    }

    @Test func ledgerDecidesWhenPresent() {
        let signature = RoomSignature.make(ledgerMadeBytes: 3, ledgerCleanups: 1, ledgerSince: since,
                                           movedKeptBytes: 12, movedCleanups: 2, movedSince: since)
        #expect(signature == .made(bytes: 3, cleanups: 1, since: since))
        #expect(signature.caption(month: "March") == "of room made since March, across 1 cleanup")
        let pending = RoomSignature.make(ledgerMadeBytes: 0, ledgerCleanups: 0, ledgerSince: since,
                                         movedKeptBytes: 12, movedCleanups: 2, movedSince: since)
        #expect(pending == .hidden)
    }

    @Test func zeroHides() {
        let signature = RoomSignature.make(ledgerMadeBytes: nil, ledgerCleanups: 0, ledgerSince: nil,
                                           movedKeptBytes: 0, movedCleanups: 1, movedSince: since)
        #expect(signature == .hidden && signature.caption(month: "March") == nil)
    }

    @Test func singularCleanup() {
        #expect(RoomSignature.moved(bytes: 1, cleanups: 1, since: since).caption(month: "March")
            == "moved to Trash since March, across 1 cleanup")
    }
}
