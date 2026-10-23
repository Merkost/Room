import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Actual memory sample history") @MainActor
struct RoomMemoryHistoryTests {
    @Test("History retains actual report identities and timestamps, caps at ninety, and skips failed counters")
    func boundedActualSamples() {
        func report(_ index: Int, available: Bool = true) -> MemoryReport {
            MemoryReport(id: UUID(), scannedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 20)),
                totalBytes: 16_000_000_000, usedBytes: available ? Int64(index + 1) * 1_000_000 : 0,
                availableBytes: available ? 8_000_000_000 : 0, compressedBytes: 0, swapUsedBytes: 0,
                pressure: .normal, processes: [], recommendations: [], issues: available ? [] : ["Counters unavailable"])
        }
        var history: [RoomMemorySample] = []
        var actual: [MemoryReport] = []
        for index in 0..<100 {
            let sample = report(index); actual.append(sample)
            history = RoomMemorySample.retaining(sample, in: history)
        }
        #expect(history.count == 90)
        #expect(history.map(\.id) == actual.suffix(90).map(\.id))
        #expect(history.map(\.scannedAt) == actual.suffix(90).map(\.scannedAt))
        #expect(history.last?.usedBytes == actual.last?.usedBytes)
        history = RoomMemorySample.retaining(report(100, available: false), in: history)
        #expect(history.count == 90)
        #expect(history.last?.id == actual.last?.id)
        history = RoomMemorySample.retaining(actual.last!, in: history)
        #expect(history.count == 90)
    }
}
