import Foundation
import SwiftUI
import Testing
@testable import RoomApp

/// DS-9 and REVIEW §4: motion through `roomMotion`, Reduce Motion keeps fades and drops travel, nothing loops at rest.
@MainActor
struct RoomMotionTests {
    @Test func receiptPillTravelsToHistoryOnlyWithFullMotion() {
        let origin = CGPoint(x: 400, y: 300)
        let full = RoomReceiptTravel.offset(from: origin, screenWidth: 1_000, fullMotion: true)
        #expect(full.width > 0 && full.height < 0, "towards the toolbar's trailing History button")
        #expect(full.height <= -origin.y, "it leaves the content area at the top")
        #expect(RoomReceiptTravel.offset(from: origin, screenWidth: 1_000, fullMotion: false) == .zero,
                "Reduce Motion cross-fades in place")
    }

    @Test func historyPulsesWhenThePillArrives() {
        #expect(RoomReceiptTravel.pulseDelay == RoomReceiptTravel.hold + RoomReceiptTravel.trip)
        #expect(RoomReceiptTravel.hold == RoomDS.Motion.Duration.standard.seconds)
        #expect(RoomReceiptTravel.trip == RoomDS.Motion.Duration.page.seconds)
    }

    @Test func hideDissolvesIn150ms() {
        #expect(RoomHideMask.dissolveDuration == 0.15)
        #expect(RoomHideMask.dissolveBlur > 0 && RoomHideMask.dissolveBlur <= 2, "a soft blur, not a smear")
    }

    @Test func everyMoveHasReduceFallback() {
        let reduced = RoomMotionPolicy(gentleMotion: true, reduceMotion: true)
        #expect(reduced.animation(RoomTokens.Motion.page) == RoomTokens.Motion.fade, "travel becomes a fade")
        #expect(reduced.animation(RoomTokens.Motion.page, fallback: nil) == nil)
        for move in RoomDS.Motion.Vocabulary.allCases where move.move.reduce != .swap {
            #expect(move.reducedAnimation != nil, "\(move) keeps a cross-fade under Reduce Motion")
        }
    }

    @Test func noLoopsAtRest() throws {
        // Every frame-driven view is either paused at rest or only exists while something really moves.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var checked = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("TimelineView(.animation")
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                checked += 1
                let guarded = line.contains("paused:") || (index > 0 && lines[index - 1].contains("if "))
                #expect(guarded, "\(file.lastPathComponent):\(index + 1) animates without a pause or a guard")
                #expect(!line.contains("repeatForever"))
            }
        }
        #expect(checked > 0)
    }
}
