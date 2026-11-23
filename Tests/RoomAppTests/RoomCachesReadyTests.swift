import Foundation
import Testing
@testable import RoomApp

/// REVIEW 2026-11-23 §3 Caches (ready state): lead with what clicking does, show the last result as a number.
@MainActor
struct RoomCachesReadyTests {
    @Test func leadSaysWhatHappensAndThatNothingIsDeleted() {
        let lead = RoomCachesReadyCopy.lead(needsFolder: false)
        #expect(lead.contains("Nothing is deleted"))
        #expect(lead.contains("review before anything moves to Trash"))
        #expect(RoomCachesReadyCopy.lead(needsFolder: true) == "Choose a folder to check, then review what can move to Trash.",
                "the Store folder sentence is unchanged")
    }

    @Test func lastResultIsANumber() {
        let check = RoomCachesCheck(at: .now, bytes: 12_400_000_000, partial: false)
        #expect(RoomCachesReadyCopy.lastResult(check, format: RoomFormat.gb) == "12 GB could go")
        let partial = RoomCachesCheck(at: .now, bytes: 12_400_000_000, partial: true)
        #expect(RoomCachesReadyCopy.lastResult(partial, format: RoomFormat.gb) == "≥ 12 GB could go")
        #expect(RoomCachesReadyCopy.lastResult(RoomCachesCheck(at: .now, bytes: 0, partial: false), format: RoomFormat.gb) == nil)
    }
}

struct RoomCachesProgressTests {
    @Test func determinateWhenCountKnown() {
        #expect(RoomCachesProgress.isDeterminate(total: 11))
        #expect(RoomCachesProgress.line(completed: 4, total: 11) == "Checking, 4 of 11 places")
        #expect(RoomCachesProgress.line(completed: 12, total: 11) == "Checking, 11 of 11 places", "never past the total")
    }

    @Test func indeterminateUntilTheEngineReports() {
        #expect(!RoomCachesProgress.isDeterminate(total: 0))
        #expect(RoomCachesProgress.line(completed: 0, total: 0) == nil)
    }
}
