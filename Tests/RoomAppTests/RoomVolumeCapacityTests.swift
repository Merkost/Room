import Foundation
import Testing
@testable import RoomApp

@Suite("Volume capacity") @MainActor
struct RoomVolumeCapacityTests {
    @Test(arguments: [true, false])
    func missingKeysAreUnavailable(_ missingTotal: Bool) {
        let result = RoomVolumeCapacity(capacityBytes: missingTotal ? nil : 100, freeBytes: missingTotal ? 25 : nil)
        #expect(result == nil)
    }

    @Test func failureClearsPriorSuccess() throws {
        let measured = try #require(RoomVolumeCapacity(capacityBytes: 994_000_000_000, freeBytes: 312_000_000_000))
        var shouldThrow = false
        let insights = RoomInsightsModel(capacityReader: {
            if shouldThrow { throw CocoaError(.fileReadUnknown) }
            return measured
        })
        let overview = RoomOverviewModel()

        insights.refreshDiskCapacity()
        overview.update(capacity: insights.volumeCapacity, goalBytes: RoomMenuBarSettings.defaultGoalBytes)
        #expect(insights.volumeCapacity == measured)
        #expect(overview.snapshot.state == .notMapped)

        shouldThrow = true
        insights.refreshDiskCapacity()
        overview.update(capacity: insights.volumeCapacity, goalBytes: RoomMenuBarSettings.defaultGoalBytes)
        #expect(insights.volumeCapacity == nil)
        #expect(insights.diskAvailableBytes == 0 && insights.diskCapacityBytes == 0)
        #expect(overview.snapshot.action == .retryCapacity)
        #expect(overview.snapshot.answer == "Room can't read free space right now.")

        shouldThrow = false
        insights.refreshDiskCapacity()
        overview.update(capacity: insights.volumeCapacity, goalBytes: RoomMenuBarSettings.defaultGoalBytes)
        #expect(overview.snapshot.state == .notMapped)
    }

    @Test func zeroFreeIsMeasured() throws {
        let measured = try #require(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 0))
        let insights = RoomInsightsModel(capacityReader: { measured })
        insights.refreshDiskCapacity()
        #expect(insights.volumeCapacity?.freeBytes == 0)
        #expect(insights.volumeCapacity?.capacityBytes == 100)
    }

    @Test func freeAboveCapacityRejected() {
        #expect(RoomVolumeCapacity(capacityBytes: 100, freeBytes: 101) == nil)
    }

    @Test(arguments: [Int64(-1), 0])
    func nonpositiveCapacityRejected(_ capacity: Int64) {
        #expect(RoomVolumeCapacity(capacityBytes: capacity, freeBytes: 0) == nil)
    }

    @Test func negativeFreeRejected() {
        #expect(RoomVolumeCapacity(capacityBytes: 100, freeBytes: -1) == nil)
    }

    @Test func refreshRunsWithMenuBarOff() async throws {
        let probe = CapacityProbe(delay: .milliseconds(10))
        let insights = probe.makeInsights()
        insights.setOverviewActive(true)
        defer { insights.setOverviewActive(false) }

        try await waitFor { probe.reads >= 2 }
        #expect(insights.volumeCapacity?.freeBytes == 25)
    }

    @Test func leavingOverviewCancelsRefresh() async throws {
        let probe = CapacityProbe(delay: .seconds(60))
        let insights = probe.makeInsights()
        insights.setOverviewActive(true)
        defer { insights.setOverviewActive(false) }
        try await waitFor { probe.waits == 1 }

        insights.setOverviewActive(false)
        try await waitFor { probe.cancelledWaits == 1 }
        #expect(probe.reads == 1)
        #expect(probe.waits == 1)
    }

    @Test(arguments: [true, false])
    func activationCoalescesWithMonitor(_ monitorFirst: Bool) async throws {
        let probe = CapacityProbe(delay: .seconds(60))
        let insights = probe.makeInsights()
        defer {
            insights.setOverviewActive(false)
            insights.stopMonitoring()
        }
        if monitorFirst {
            insights.beginMonitoring()
            insights.setOverviewActive(true)
        } else {
            insights.setOverviewActive(true)
            insights.beginMonitoring()
        }

        try await waitFor { probe.waits == 1 }
        #expect(probe.reads == 1)

        insights.setOverviewActive(false)
        insights.setOverviewActive(true)
        try await waitFor { probe.waits == 2 && probe.cancelledWaits == 1 }
        #expect(probe.reads == 2)

        insights.setOverviewActive(false)
        insights.stopMonitoring()
        try await waitFor { probe.cancelledWaits == 2 }
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition())
    }
}

@MainActor
private final class CapacityProbe {
    let delay: Duration
    private(set) var reads = 0
    private(set) var waits = 0
    private(set) var cancelledWaits = 0

    init(delay: Duration) { self.delay = delay }

    func makeInsights() -> RoomInsightsModel {
        RoomInsightsModel(capacityReader: {
            self.reads += 1
            return RoomVolumeCapacity(capacityBytes: 100, freeBytes: 25)
        }, waitForCapacityTick: {
            self.waits += 1
            do {
                try await Task.sleep(for: self.delay)
            } catch {
                self.cancelledWaits += 1
                throw error
            }
        })
    }
}
