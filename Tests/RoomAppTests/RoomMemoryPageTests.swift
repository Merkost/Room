import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

/// Memory shows everything on one screen: a range, one pressure sentence, the curve, four figures, two lists.
struct RoomMemoryPageTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ secondsAgo: Double, _ level: RoomPressureLevel? = .normal) -> RoomMemorySampleRing.Sample {
        .init(at: end.addingTimeInterval(-secondsAgo), bytes: 9_000_000_000, level: level)
    }

    @Test func eachRangeKeepsOnlyItsOwnSamples() {
        let samples = [sample(1_800), sample(600), sample(200), sample(0)]
        #expect(RoomMemoryPage.window(samples, range: .now).count == 2)
        #expect(RoomMemoryPage.window(samples, range: .quarter).count == 3)
        #expect(RoomMemoryPage.window(samples, range: .hour).count == 4)
        #expect(RoomMemoryPage.window([], range: .hour).isEmpty)
    }

    @Test func pressureSentenceNamesTheWorstLevelAndTheTimeReallyCovered() {
        #expect(RoomMemoryPage.pressureSentence([sample(720), sample(0)]) == "Pressure stayed normal over the last 12 min")
        #expect(RoomMemoryPage.pressureSentence([sample(120, .critical), sample(0)])
                == "Pressure reached critical over the last 2 min")
        #expect(RoomMemoryPage.pressureSentence([sample(0)]) == "Pressure is normal so far")
        #expect(RoomMemoryPage.pressureSentence([sample(40, nil), sample(0, nil)]) == "macOS didn’t report pressure")
        #expect(RoomMemoryPage.pressureSentence([]) == "Waiting for the first reading")
    }

    @Test func curveSitsInTimeAndBreaksAcrossASleep() {
        let samples = [sample(300), sample(280), sample(20), sample(0)]
        let runs = RoomMemoryPage.runs(samples, range: .now, size: CGSize(width: 300, height: 100))
        #expect(runs.count == 2, "a gap longer than three readings is not drawn across")
        #expect(runs.first?.first?.x == 0)
        #expect(runs.last?.last?.x == 300)
        let short = RoomMemoryPage.runs([sample(20), sample(0)], range: .now, size: CGSize(width: 300, height: 100))
        #expect(short.first?.first?.x == 280, "unmeasured time stays empty")
    }

    @Test func backgroundIsEverythingThatCannotBeQuitHere() {
        let processes = [MemoryProcess(id: 1, name: "Xcode", residentBytes: 3),
                         MemoryProcess(id: 2, name: "java", residentBytes: 2)]
        #expect(RoomMemoryPage.background(processes, apps: [1]).map(\.name) == ["java"])
    }

    @Test func adviceOnlyWhenPressureAsksForIt() {
        let calm = MemoryEngine.recommendations(pressure: .normal, totalBytes: 16, swapUsedBytes: 5, processes: [])
        #expect(RoomMemoryPage.advice(calm).isEmpty)
        let tight = MemoryEngine.recommendations(pressure: .critical, totalBytes: 16, swapUsedBytes: 5, processes: [])
        #expect(RoomMemoryPage.advice(tight).map(\.id) == ["pressure"])
    }

    @Test func aMissingReadingIsNeverZero() {
        let measured = RoomMemoryWords.figures(used: 9, compressed: 1, wired: 2, swap: 0)
        #expect(measured.map(\.bytes) == [6, 2, 1, 0])
        let noSwap = RoomMemoryWords.figures(used: 9, compressed: 1, wired: nil, swap: nil)
        #expect(noSwap.map(\.bytes) == [nil, nil, 1, nil])
        #expect(RoomMemoryWords.figures(used: 0, compressed: 0, wired: nil, swap: nil).allSatisfy { $0.bytes == nil })
        #expect(RoomMemoryWords.make(usedBytes: 0, totalBytes: 16, pressureRaw: nil).headline.figure == nil)
    }

    @Test func nothingHidesBehindMoreDetail() throws {
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp/Views/RoomMemoryView.swift")
        let text = try String(contentsOf: views, encoding: .utf8)
        #expect(!text.contains("DisclosureGroup"))
        #expect(!text.contains("Text(\"Memory\")"), "the toolbar names the screen")
    }
}
