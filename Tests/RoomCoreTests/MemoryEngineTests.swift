import Foundation
import Testing
@testable import RoomCore

@Suite("Read-only memory measurement")
struct MemoryEngineTests {
    @Test("Physical compressor storage is included exactly once in used RAM")
    func physicalMemoryAccounting() {
        let metrics = MemoryMetrics.calculate(totalBytes: 16_384, pageSize: 1024,
            internalPages: 8, purgeablePages: 2, wiredPages: 3, compressorPages: 2)
        #expect(metrics.totalBytes == 16_384)
        #expect(metrics.usedBytes == 11_264)
        #expect(metrics.availableBytes == 5120)
        #expect(metrics.compressedBytes == 2048)
        #expect(metrics.usedBytes + metrics.availableBytes == metrics.totalBytes)
    }

    @Test("Asynchronous VM counters and arithmetic overflow cannot create negative RAM")
    func boundedAccounting() {
        let underflow = MemoryMetrics.calculate(totalBytes: 1024, pageSize: 1024,
            internalPages: 1, purgeablePages: 2, wiredPages: 0, compressorPages: 0)
        #expect(underflow.usedBytes == 0)
        #expect(underflow.availableBytes == 1024)
        let overflow = MemoryMetrics.calculate(totalBytes: 1024, pageSize: UInt64.max,
            internalPages: UInt64.max, purgeablePages: 0, wiredPages: UInt64.max, compressorPages: UInt64.max)
        #expect(overflow.usedBytes == 1024)
        #expect(overflow.availableBytes == 0)
        #expect(overflow.compressedBytes == 1024)
    }

    @Test("Pressure maps actual Dispatch flags and never guesses from occupancy")
    func actualPressureFlags() {
        let samples: [(UInt32, MemoryPressure)] = [(1, .normal), (2, .elevated), (4, .critical), (0, .unknown), (3, .unknown), (99, .unknown)]
        for (flags, expected) in samples {
            #expect(MemoryEngine.pressure(fromDispatchFlags: flags) == expected)
        }
    }

    @Test("RSS parsing preserves executable names with spaces and rejects unsafe rows")
    func processParsing() {
        let output = """
            33    2048 /Applications/ChatGPT.app/Contents/Frameworks/Codex (Service)
             2     512 /sbin/launchd
            44    2048 /Applications/Xcode.app/Contents/MacOS/Xcode
        malformed
           -1      200 /not/a/process
             0      100 /kernel
             9       -2 /negative
            10 9223372036854775807 /overflow
        """
        let processes = MemoryEngine.parseProcesses(output)
        #expect(processes.map(\.id) == [33, 44, 2])
        #expect(processes.first?.name == "Codex (Service)")
        #expect(processes.first?.residentBytes == 2_097_152)
        #expect(processes.last?.residentBytes == 524_288)
        #expect(processes.allSatisfy { !$0.name.contains("/Applications/") })
    }

    @Test("Process evidence retains lower-ranked app PIDs within a bounded sample")
    func boundedProcesses() {
        let output = (1...25).map { "\($0) \($0 * 1024) /usr/bin/process\($0)" }.joined(separator: "\n")
        let processes = MemoryEngine.parseProcesses(output)
        #expect(processes.count == 25)
        #expect(processes.map(\.id) == Array((1...25).reversed()).map(Int32.init))
        #expect(MemoryEngine.parseProcesses("").isEmpty)
        let large = (1...(MemoryEngine.processSampleLimit + 100)).map {
            "\($0) \($0 * 1024) /usr/bin/process\($0)"
        }.joined(separator: "\n")
        let bounded = MemoryEngine.parseProcesses(large)
        #expect(bounded.count == MemoryEngine.processSampleLimit)
        #expect(bounded.last?.id == 101)
    }

    @Test("Normal pressure stays calm despite residual swap and a large app")
    func normalRecommendations() {
        let recommendations = MemoryEngine.recommendations(pressure: .normal,
            totalBytes: 16 * 1_073_741_824, swapUsedBytes: 8 * 1_073_741_824,
            processes: [MemoryProcess(id: 12, name: "Large app", residentBytes: 10 * 1_073_741_824)])
        #expect(recommendations.first?.id == "normal")
        #expect(recommendations.first?.title == "No RAM optimization needed")
        #expect(!recommendations.contains { $0.id == "largest-process" })
        #expect(recommendations.first { $0.id == "swap" }?.detail.contains("does not prove") == true)
    }

    @Test("Elevated pressure grounds a suggestion in the measured largest process")
    func elevatedRecommendations() {
        let recommendations = MemoryEngine.recommendations(pressure: .elevated,
            totalBytes: 16 * 1_073_741_824, swapUsedBytes: 0,
            processes: [MemoryProcess(id: 12, name: "Xcode", residentBytes: 4 * 1_073_741_824)])
        #expect(recommendations.map(\.id) == ["pressure", "largest-process"])
        #expect(recommendations.last?.title == "Review Xcode")
        #expect(recommendations.last?.detail.contains("shared pages") == true)
    }

    @Test("Unavailable pressure remains unknown and makes no app-quit recommendation")
    func unknownRecommendations() {
        let recommendations = MemoryEngine.recommendations(pressure: .unknown,
            totalBytes: 1_073_741_824, swapUsedBytes: 0,
            processes: [MemoryProcess(id: 12, name: "App", residentBytes: 1_073_741_824)])
        #expect(recommendations.count == 1)
        #expect(recommendations.first?.id == "pressure-unavailable")
    }

    @Test("A live host sample has coherent physical counters without changing the system")
    func liveHostSanity() async {
        let report = await MemoryEngine().scan()
        #expect(report.totalBytes > 0)
        #expect(report.usedBytes >= 0 && report.usedBytes <= report.totalBytes)
        #expect(report.availableBytes >= 0 && report.availableBytes <= report.totalBytes)
        #expect(report.usedBytes + report.availableBytes == report.totalBytes, "\(report.issues)")
        #expect(report.compressedBytes >= 0 && report.compressedBytes <= report.usedBytes)
        #expect(report.swapUsedBytes >= 0)
        #expect(report.processes.count <= MemoryEngine.processSampleLimit)
        #expect(!report.processes.isEmpty, "\(report.issues)")
        #expect(report.processes.allSatisfy { $0.id > 0 && $0.residentBytes >= 0 })
        #expect(zip(report.processes, report.processes.dropFirst()).allSatisfy { $0.residentBytes >= $1.residentBytes })
        #expect(!report.recommendations.isEmpty)
    }
}
