import Foundation
import Testing
@testable import RoomApp

/// REVIEW 2026-11-23 §3 Memory: one title, a strip while Normal, lanes only when there is something to see.
struct RoomMemoryLayoutTests {
    private func bucket(_ index: Int64, _ level: RoomPressureLevel, count: Int = 1) -> RoomPressureBucket {
        RoomPressureBucket(index: index, worst: level, usedSum: 0, count: count, lastSwapBytes: nil)
    }

    @Test func stripWhileNormal() {
        let calm: [RoomPressureBucket?] = [bucket(1, .normal), nil, nil, bucket(4, .normal)]
        #expect(!RoomPressureLayout.showsLanes(calm, hovering: false, pinnedOpen: false))
        #expect(!RoomPressureLayout.showsLanes([nil, nil], hovering: false, pinnedOpen: false), "gaps alone stay a strip")
    }

    @Test func lanesWhenTheRangeHoldsElevatedOrCritical() {
        #expect(RoomPressureLayout.showsLanes([bucket(1, .normal), bucket(2, .elevated)], hovering: false, pinnedOpen: false))
        #expect(RoomPressureLayout.showsLanes([nil, bucket(2, .critical)], hovering: false, pinnedOpen: false))
    }

    @Test func hoverOrClickOpensTheLanes() {
        let calm: [RoomPressureBucket?] = [bucket(1, .normal)]
        #expect(RoomPressureLayout.showsLanes(calm, hovering: true, pinnedOpen: false))
        #expect(RoomPressureLayout.showsLanes(calm, hovering: false, pinnedOpen: true))
    }

    @Test func nowDotPulsesOncePerSample() {
        let before: [RoomPressureBucket?] = [bucket(7, .normal, count: 3), nil]
        let sameSample: [RoomPressureBucket?] = [bucket(7, .normal, count: 3), nil]
        let nextSample: [RoomPressureBucket?] = [bucket(7, .normal, count: 4), nil]
        let nextBucket: [RoomPressureBucket?] = [bucket(7, .normal, count: 4), bucket(8, .normal, count: 1)]
        #expect(RoomPressureLayout.sampleKey(before) == RoomPressureLayout.sampleKey(sameSample), "no sample, no pulse")
        #expect(RoomPressureLayout.sampleKey(before) != RoomPressureLayout.sampleKey(nextSample))
        #expect(RoomPressureLayout.sampleKey(nextSample) != RoomPressureLayout.sampleKey(nextBucket))
        #expect(RoomPressureLayout.sampleKey([nil, nil]) == nil)
    }

    @Test func singleTitle() throws {
        // The toolbar names the screen; the page starts with content, not a second "Memory" heading.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp/Views/RoomMemoryView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(!text.contains("Text(\"Memory\")"))
        #expect(!text.contains("accessibilityHeading(.h1)"))
    }
}
