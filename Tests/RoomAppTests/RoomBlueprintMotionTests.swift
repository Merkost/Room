import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomBlueprintMotionTests {
    private let start = Date(timeIntervalSinceReferenceDate: 100)
    private let size = CGSize(width: 640, height: 400)

    @Test func batchesKeepTheirLastGeometryAndPublishOnlyFinishedRooms() {
        var scan = RoomBlueprint(topLevelTotal: 3)
        scan.progress(files: 12, bytes: 32_768)
        #expect(scan.rooms.isEmpty)
        let firstBatch = scan.completed(name: "Projects", bytes: 4096, kind: "developer", at: start)
        let nextBatch = scan.completed(name: "Downloads", bytes: 8192, kind: "documents", at: start + 0.5)
        #expect(firstBatch)
        #expect(!nextBatch)
        #expect(scan.rooms.map(\.name) == ["Projects"])
        let beforeDeadline = scan.tick(start + 0.99)
        let atDeadline = scan.tick(start + 1)
        #expect(!beforeDeadline)
        #expect(atDeadline)
        #expect(scan.beforeLastReflow.map(\.name) == ["Projects"])
        #expect(scan.rooms.map(\.name) == ["Projects", "Downloads"])
        let (layer, motion) = frame(for: scan)
        if let projects = layer.first(where: { $0.id == "Projects" }) {
            #expect(motion.place(projects, at: 0).drawRect.width > projects.drawRect.width
                || motion.place(projects, at: 0).drawRect.height > projects.drawRect.height)
            #expect(motion.place(projects, at: 1) == projects)
        } else {
            Issue.record("Projects should retain its own tile")
        }
    }

    @Test func firstScanDrawsWallBeforeFillAndStaggersTheBatch() {
        var scan = RoomBlueprint()
        scan.completed(name: "First", bytes: 4096, kind: nil, at: start)
        scan.completed(name: "Largest", bytes: 16384, kind: nil, at: start + 0.5)
        scan.completed(name: "Second", bytes: 8192, kind: nil, at: start + 0.5)
        let nextBatch = scan.tick(start + 1)
        #expect(nextBatch)
        let (_, motion) = frame(for: scan)
        #expect(motion.firstScan)
        #expect(motion.reveal("Largest", at: 0.02).wall > 0)
        #expect(motion.reveal("Second", at: 0.02).wall == 0)
        #expect(motion.reveal("Largest", at: 0.30).fill == 0)
        #expect(motion.reveal("Largest", at: 0.50).fill > 0)
        #expect(motion.reveal("Second", at: RoomBlueprintMotion.duration).fill == 1)
        #expect(motion.reveal("First", at: 0).fill == 1)
    }

    @Test func rescanCrossfadesOnlyTheRoomThatFinished() {
        var scan = RoomBlueprint(earlier: ["Done": (4096, nil), "Waiting": (8192, nil)], earlierDate: start)
        scan.completed(name: "Done", bytes: 2048, kind: nil, isPartial: true, at: start + 5)
        let (layer, motion) = frame(for: scan)
        #expect(!motion.firstScan)
        #expect(motion.pending == ["Waiting"])
        #expect(motion.previous["Done"]?.bytes == 4096)
        #expect(layer.first(where: { $0.id == "Done" })?.isPartial == true)
        #expect(motion.reveal("Done", at: 0.15).wall == 0)
        #expect(motion.reveal("Done", at: 0.15).fill > 0)
        #expect(motion.reveal("Waiting", at: 0.15).fill == 1)
    }

    @Test func stopAndReducedMotionSettleWithoutDroppingMeasurements() {
        var scan = RoomBlueprint(topLevelTotal: 3)
        scan.completed(name: "First", bytes: 1024, kind: nil, at: start)
        let (_, reduced) = frame(for: scan, animates: false)
        #expect(reduced.startedAt == nil)
        #expect(reduced.reveal("First", at: 0).fill == 1)
        scan.completed(name: "Second", bytes: 2048, kind: nil, at: start + 0.5)
        scan.stop(at: start + 0.6)
        let (_, stopped) = frame(for: scan)
        #expect(stopped.startedAt == nil)
        #expect(scan.totalIsLowerBound)
        #expect(scan.stoppedSummary == "Scan stopped · 2 of 3 rooms measured")
    }

    @Test func visualTileLimitFoldsBytesAndPartialStatusIntoOther() {
        let rooms = [5, 4, 3, 2, 1].map {
            RoomBlueprint.Room(name: "Room \($0)", bytes: Int64($0), kind: nil, state: .measured, isPartial: $0 == 2)
        }
        let tree = RoomBlueprint.tree(rooms: rooms, maximumTiles: 3)
        #expect(tree.children.map(\.allocatedBytes) == [5, 4])
        #expect(tree.other?.allocatedBytes == 6)
        #expect(tree.other?.itemCount == 3)
        #expect(tree.other?.isPartial == true)
        #expect(tree.allocatedBytes == 15)
    }

    private func frame(for scan: RoomBlueprint, animates: Bool = true) -> ([RoomMapItem], RoomBlueprintMotion) {
        let tree = RoomBlueprint.tree(rooms: scan.rooms, maximumTiles: RoomMapLayer.maxTiles)
        let items = RoomMapLayer.make(level: tree, size: size).items
        return (items, RoomBlueprintMotion(blueprint: scan, items: items, size: size, animates: animates))
    }
}
