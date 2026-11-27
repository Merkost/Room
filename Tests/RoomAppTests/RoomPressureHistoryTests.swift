import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Memory pressure history") @MainActor
struct RoomPressureHistoryTests {
    @Test func referenceChecks() {
        func check(_ id: String, _ passed: Bool) { #expect(passed, Comment(rawValue: id)) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
        }
        let gb: Int64 = 1_000_000_000
        let now = date(2026, 11, 19)
        let t0 = date(2026, 11, 19, 8)       // 08:00
        var hist = RoomPressureHistory()
        for m in stride(from: 0, to: 120, by: 1) {  // 08:00–09:59 every minute (20 s samples are folded the same way)
            let at = t0.addingTimeInterval(Double(m) * 60)
            let raw = (m >= 30 && m < 45) ? "elevated" : (m == 50 ? "unknown" : "normal")
            hist.record(pressureRaw: raw, usedBytes: 16 * gb, swapBytes: 400_000_000, at: at)
        }
        let dayCols = hist.day.columns(now: t0.addingTimeInterval(119 * 60))
        check("DMR-C98_NinetySixColumns", dayCols.count == 96 && hist.week.columns(now: t0).count == 84)
        check("DMR-C99_WorstLevelWins", dayCols.compactMap { $0 }.map(\.worst) == [.normal, .normal, .elevated, .normal, .normal, .normal, .normal, .normal])
        check("DMR-C100_UnknownDropped", dayCols.compactMap({ $0 }).reduce(0) { $0 + $1.count } == 119)
        check("DMR-C101_GapsAreNil", dayCols.prefix(88).allSatisfy { $0 == nil })
        hist.record(pressureRaw: "normal", usedBytes: 16 * gb, swapBytes: nil, at: t0.addingTimeInterval(-3_600))
        check("DMR-C102_BackwardsClockIgnored", hist.day.buckets.first?.index == hist.day.bucketIndex(t0))
        let afterSleep = t0.addingTimeInterval(5 * 3_600)
        hist.record(pressureRaw: "normal", usedBytes: 16 * gb, swapBytes: nil, at: afterSleep)
        let sleepCols = hist.day.columns(now: afterSleep)
        check("DMR-C103_ThreeHourSleepStaysMissing", sleepCols.suffix(13).prefix(12).allSatisfy { $0 == nil })
        check("DMR-C104_RetentionCapped", { var s = RoomPressureSeries(bucketSeconds: 900, capacity: 96)
            for i in 0..<300 { s.record(.normal, usedBytes: 1, swapBytes: nil, at: t0.addingTimeInterval(Double(i) * 900)) }
            return s.buckets.count == 96 }())
        check("DMR-C111_ThreePocketLevels", RoomPressureLevel.allCases.map(\.pocketFill) == [0, 0.5, 1])
        let samples = (0..<3).map { (at: now.addingTimeInterval(Double(-$0) * 20), bytes: Int64(15 + $0) * gb) }
        check("DMR-C112_AverageNamesRealWindow", RoomMemoryInUse.average(samples, now: now)?.caption == "last 1 min"
              && RoomMemoryInUse.average(samples, now: now)?.bytes == 16 * gb)
        check("DMR-C113_AverageNeedsThreeSamples", RoomMemoryInUse.average(Array(samples.prefix(2)), now: now) == nil)
        let hourSamples = (0..<180).map { (at: now.addingTimeInterval(Double(-$0) * 20), bytes: 16 * gb) }
        check("DMR-C114_FullHourSaysLastHour", RoomMemoryInUse.average(hourSamples, now: now)?.caption == "last hour")

    }

    @Test func memoryVisibleSamplesWithMenuBarOff() async throws {
        try await withProbe { probe, model in
            model.setMemoryActive(true)
            try await waitFor { model.memorySamples.values.count == 1 && probe.waits == 1 }
            probe.tick.yield(())
            try await waitFor { model.memorySamples.values.count == 2 && probe.waits == 2 }
            #expect(model.pressureHistory.day.buckets.last?.worst == .elevated)
        }
    }

    @Test func leavingMemoryStopsLoop() async throws {
        try await withProbe { probe, model in
            model.setMemoryActive(true)
            try await waitFor { probe.waits == 1 && model.memorySamples.values.count == 1 }
            model.setMemoryActive(false)
            try await waitFor { probe.cancellations == 1 }
            #expect(probe.reads == 1)
        }
    }

    @Test func monitorAndScreenShareOneLoop() async throws {
        try await withProbe { probe, model in
            model.setMemoryActive(true)
            model.beginMonitoring()
            try await waitFor { model.memorySamples.values.count == 1 && probe.waits == 1 }
            model.setMemoryActive(false)
            probe.tick.yield(())
            try await waitFor { model.memorySamples.values.count == 2 && probe.waits == 2 }
            model.stopMonitoring()
            try await waitFor { probe.cancellations == 1 }
            #expect(probe.reads == 2)
        }
    }

    @Test func historySurvivesRelaunch() async throws {
        try await withProbe { probe, model in
            model.scanMemory()
            try await waitFor { model.memoryReport != nil && !model.isScanningMemory }
            #expect(probe.store.load().day.buckets.isEmpty)
            model.savePressureHistory()
            let relaunched = RoomInsightsModel(pressureStore: probe.store)
            #expect(relaunched.pressureHistory.day.buckets.last?.meanUsedBytes == 15)
            #expect(relaunched.pressureHistory.day.buckets.last?.lastSwapBytes == 3)
        }
    }

    @Test func corruptFileStartsEmpty() async throws {
        try await withProbe { probe, _ in
            let corrupt = Data("{broken".utf8)
            let file = probe.store.directory.appendingPathComponent("memory-pressure.json")
            try corrupt.write(to: file)
            let relaunched = RoomInsightsModel(pressureStore: probe.store)
            #expect(relaunched.pressureHistory.day.buckets.isEmpty)
            #expect(try Data(contentsOf: file) == corrupt)
        }
    }

    @Test func pressureVocabularyAgrees() {
        #expect(RoomMonitorPresentation.pressureTitle(.normal) == "Normal pressure")
        #expect(RoomMonitorPresentation.pressureTitle(.elevated) == "Elevated pressure")
        #expect(RoomMonitorPresentation.pressureTitle(.critical) == "Critical pressure")
    }

    private func withProbe(_ body: (Probe, RoomInsightsModel) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = Probe(store: RoomPressureHistoryStore(directory: directory))
        let model = probe.makeModel()
        defer {
            model.setMemoryActive(false)
            model.stopMonitoring()
            probe.tick.finish()
        }
        try await body(probe, model)
    }

    private func waitFor(_ ready: () -> Bool) async throws {
        for _ in 0..<100 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Memory sampler did not reach the expected state")
    }

    @MainActor private final class Probe {
        let store: RoomPressureHistoryStore
        let ticks: AsyncStream<Void>
        let tick: AsyncStream<Void>.Continuation
        var reads = 0
        var waits = 0
        var cancellations = 0

        init(store: RoomPressureHistoryStore) {
            self.store = store
            (ticks, tick) = AsyncStream.makeStream()
        }

        func makeModel() -> RoomInsightsModel {
            RoomInsightsModel(capacityReader: { nil }, pressureStore: store, readMemory: {
                self.reads += 1
                return MemoryReport(id: UUID(), scannedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(self.reads * 20)),
                    totalBytes: 32, usedBytes: 15, availableBytes: 17, compressedBytes: 2, swapUsedBytes: 3,
                    pressure: .elevated, processes: [], recommendations: [], issues: [])
            }, waitForMemoryTick: {
                self.waits += 1
                var iterator = self.ticks.makeAsyncIterator()
                guard await iterator.next(isolation: #isolation) != nil else {
                    self.cancellations += 1
                    throw CancellationError()
                }
            })
        }
    }
}
