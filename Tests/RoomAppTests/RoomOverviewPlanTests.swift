import CoreGraphics
import Foundation
import Testing
@testable import RoomApp

@Suite @MainActor
struct RoomOverviewPlanTests {
    private let normal = RoomOverviewPlanInput(capacityBytes: 994_000_000_000, freeBytes: 312_000_000_000, goalBytes: 50_000_000_000)
    private let viewport = CGSize(width: 560, height: 288)

    @Test func fixtureHas78FreeAndNoKindDots() throws {
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: normal, size: viewport))
        #expect(drawing.layout.dots.map(\.room) == Array(repeating: .free, count: 78))
        #expect(drawing.notMapped != nil)
    }

    @Test func observedReturnsLightOnlyWholeAvailableDots() {
        #expect(RoomOverviewPlanGeometry.returnedDotCount(bytes: 0, gbPerDot: 2, limit: 10) == 0)
        #expect(RoomOverviewPlanGeometry.returnedDotCount(bytes: 1_900_000_000, gbPerDot: 2, limit: 10) == 0)
        #expect(RoomOverviewPlanGeometry.returnedDotCount(bytes: 5_000_000_000, gbPerDot: 2, limit: 10) == 2)
        #expect(RoomOverviewPlanGeometry.returnedDotCount(bytes: Int64.max, gbPerDot: 2, limit: 10) == 10)
    }

    @Test func contextGridExcludedFromDataCount() throws {
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: normal, size: viewport))
        let details = RoomOverviewPlanPresentation(plan: normal, hidden: false, format: RoomFormat.gb)
        let unmeasured = try #require(details.rows.first { $0.id == .notMapped })
        #expect(!drawing.contextGrid.isEmpty)
        #expect(drawing.layout.dots.allSatisfy { $0.room != .notMapped })
        #expect(unmeasured.dots == "not measured")
        #expect(unmeasured.spoken.contains("Room hasn't looked here"))
    }

    @Test func positiveTinyFreeHasTableRow() throws {
        // Under 0.5 MB produces no visual rect in the shared rounding code.
        let tiny = RoomOverviewPlanInput(capacityBytes: normal.capacityBytes, freeBytes: 1, goalBytes: nil)
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: tiny, size: viewport))
        let details = RoomOverviewPlanPresentation(plan: tiny, hidden: false, format: RoomFormat.gb)
        let free = try #require(details.rows.first { $0.id == .free })
        #expect(drawing.free == nil && drawing.rings.isEmpty)
        #expect(free.dots == "under 4 GB")
        #expect(free.size != "0 GB")
    }

    @Test func zeroFreeDoesNotCrash() throws {
        let full = RoomOverviewPlanInput(capacityBytes: normal.capacityBytes, freeBytes: 0, goalBytes: nil)
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: full, size: viewport))
        #expect(drawing.layout.rooms.map(\.id) == [.notMapped])
        #expect(drawing.rings.isEmpty)
    }

    @Test func captionBandUses550By264() throws {
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: normal, size: viewport))
        #expect(drawing.wall == CGRect(x: 5, y: 5, width: 550, height: 264))
    }

    @Test func goalOutlineFitsWithoutLabelCollision() throws {
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: normal, size: viewport))
        let goal = try #require(drawing.goal)
        let free = try #require(drawing.free)
        let label = try #require(drawing.freeLabelArea)
        #expect(free.contains(goal) && !goal.intersects(label))
        #expect(abs(goal.width * goal.height - drawing.wall.width * drawing.wall.height * 50 / 994) < 0.001)
    }

    @Test func belowGoalKeepsNeutralRings() throws {
        let low = RoomOverviewPlanInput(capacityBytes: normal.capacityBytes, freeBytes: 41_000_000_000, goalBytes: nil)
        let drawing = try #require(RoomOverviewPlanGeometry.make(plan: low, size: viewport))
        #expect(drawing.goal == nil && !drawing.rings.isEmpty)
        #expect(drawing.layout.dots.map(\.room) == Array(repeating: .free, count: 10))
    }

    @Test func over26TBDoesNotAllocatePlan() {
        let edge = RoomOverviewPlanInput(capacityBytes: 26_000_000_000_000, freeBytes: 312_000_000_000, goalBytes: nil)
        let tooLarge = RoomOverviewPlanInput(capacityBytes: edge.capacityBytes + 1, freeBytes: edge.freeBytes, goalBytes: nil)
        #expect(RoomOverviewPlanGeometry.make(plan: edge, size: viewport) != nil)
        #expect(RoomOverviewPlanGeometry.make(plan: tooLarge, size: viewport) == nil)
    }

    @Test func planArrowsUseDescendingBytesAndStableIDs() {
        let details = RoomOverviewPlanPresentation(plan: normal, hidden: true, format: RoomFormat.gb)
        #expect(details.nextFocus(from: nil, step: 1) == .notMapped)
        #expect(details.nextFocus(from: .notMapped, step: 1) == .free)
        #expect(details.nextFocus(from: .free, step: -1) == .notMapped)
    }

    @Test func hiddenLabelsAndAccessibilityValuesContainNoSizesOrDotCounts() throws {
        let details = RoomOverviewPlanPresentation(plan: normal, hidden: true) { bytes in
            bytes == 312_000_000_000 ? "٣١٢ GB" : "٤ GB"
        }
        let free = try #require(details.rows.first { $0.id == .free })
        #expect(free.visualSize == "••• GB")
        #expect(details.rows.allSatisfy { $0.dots.isEmpty })
        let presentationText = [details.caption, details.accessibilityLabel, details.goalLabel ?? ""]
            + details.rows.flatMap { [$0.visualSize, $0.size, $0.spoken, $0.readout] }
        #expect(presentationText.allSatisfy { !$0.contains(where: \.isNumber) })
    }
}
