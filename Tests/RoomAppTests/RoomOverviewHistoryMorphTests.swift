import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomOverviewHistoryMorphTests {
    private let gb: Int64 = 1_000_000_000

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    private func plot(_ range: RoomOverviewHistoryRange, _ metric: RoomOverviewHistoryMetric,
                      log: RoomVolumeSampleLog? = nil) -> RoomOverviewHistoryPlot {
        let now = date(19)
        var measured = log ?? RoomVolumeSampleLog()
        if log == nil {
            for (day, bytes) in [(15, 120), (16, 114), (17, 115)] {
                measured.record(.init(at: date(day), capacityBytes: 200 * gb,
                                      freeBytes: Int64(bytes) * gb, volumeID: "disk"), calendar: calendar)
            }
        }
        let history = RoomOverviewHistory(log: measured, range: range, now: now, calendar: calendar)
        let domain = metric == .freeSpace ? 90.0...135.0 : -8.0...8.0
        return RoomOverviewHistoryPlot(history: history, range: range, metric: metric,
                                       domain: domain, now: now, selected: nil)
    }

    @Test func endpointsUseNinetySixColumnsAndPreserveGaps() {
        let free = plot(.week, .freeSpace)
        let change = plot(.twelveWeeks, .change)
        let transition = RoomOverviewHistoryTransition(source: [.init(plot: free, opacity: 1)],
                                                       target: change, morphs: true, start: .now)
        let duration = RoomTokens.Motion.morphDuration
        let middle = transition.layers(elapsed: duration / 2)[0].plot
        #expect(free.columns.count == 96 && middle.columns.count == 96 && change.columns.count == 96)
        #expect(middle.columns != free.columns && middle.columns != change.columns)
        #expect(transition.layers(elapsed: 0) == [.init(plot: free, opacity: 1)])
        #expect(transition.layers(elapsed: duration) == [.init(plot: change, opacity: 1)])
        #expect(free.gaps[40] == 1 && free.columns[40] == nil) // Wednesday had no sample.
        #expect(free.gaps[90] == 0 && free.columns[90] == nil) // Sunday has not arrived.
    }

    @Test func interruptionBeginsWithCurrentVisibleGeometry() {
        let start = ContinuousClock.now
        let source = plot(.week, .freeSpace)
        let first = RoomOverviewHistoryTransition(source: [.init(plot: source, opacity: 1)],
            target: plot(.twelveWeeks, .change), morphs: true, start: start)
        let interruption = start.advanced(by: .milliseconds(130))
        let visible = first.layers(at: interruption)
        let second = RoomOverviewHistoryTransition(source: visible,
            target: plot(.week, .change), morphs: true, start: interruption)
        #expect(second.layers(at: interruption) == visible)
        #expect(second.source[0].plot != source && second.source[0].plot != first.target)
        #expect(second.layers(elapsed: second.duration) == [.init(plot: second.target, opacity: 1)])
    }

    @Test func reducedMotionFadesWholePlotsWithoutMovingTheirColumns() {
        let source = plot(.week, .freeSpace)
        let target = plot(.week, .change)
        let transition = RoomOverviewHistoryTransition(source: [.init(plot: source, opacity: 1)],
                                                       target: target, morphs: false, start: .now)
        let halfway = transition.layers(elapsed: 0.075)
        #expect(halfway.map(\.plot) == [source, target])
        #expect(halfway.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
        #expect(transition.duration == 0.15)
        let interrupted = RoomOverviewHistoryTransition(source: halfway, target: source, morphs: false, start: .now)
        #expect(interrupted.layers(elapsed: 0) == halfway)
        #expect(interrupted.layers(elapsed: 0.15) == [.init(plot: source, opacity: 1)])
    }

    @Test func weeklyDotsRiseAndStaggerFromTheBaseUp() throws {
        let target = plot(.week, .change)
        let transition = RoomOverviewHistoryTransition(source: [.init(plot: plot(.day, .change), opacity: 1)],
                                                       target: target, morphs: true, start: .now)
        let early = transition.layers(elapsed: 0.035)[0].plot.dots.filter { $0.id.slot == 0 && $0.id.kind == .growth }
        #expect(early.map(\.id.step) == [0, 1])
        try #require(early.count == 2)
        #expect(early[0].lift > 0 && early[0].opacity > early[1].opacity)
        let settled = transition.layers(elapsed: transition.duration)[0].plot
        #expect(settled.dots == target.dots)
        #expect(settled.dots.contains { $0.id.kind == .freed })
    }

    @Test func noMeasurementsProduceNoBarsLinesOrDots() {
        for range in RoomOverviewHistoryRange.allCases {
            for metric in RoomOverviewHistoryMetric.allCases {
                let empty = plot(range, metric, log: RoomVolumeSampleLog())
                #expect(empty.columns.count == 96)
                #expect(empty.columns.allSatisfy { $0 == nil })
                #expect(empty.dots.isEmpty)
                #expect(empty.gaps.contains(1))
            }
        }
    }
}
