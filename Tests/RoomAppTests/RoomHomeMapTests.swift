import Foundation
import RoomCore
import Testing
@testable import RoomApp

@Suite("Overview measured maps")
struct RoomHomeMapTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let gb: Int64 = 1_000_000_000

    @Test func measuredKindsDrawOnlyRealDataDots() throws {
        let map = home()
        let kinds = try RoomHomeMap.kinds(roots: [("/Users/example", map)], capacityBytes: 994 * gb,
            freeBytes: 312 * gb, capacityVolumeUUID: "data").get()
        #expect(kinds.mappedBytes == 474 * gb)
        #expect(kinds.notMappedBytes == 208 * gb)
        #expect(kinds.mappedAt == now)

        let snapshot = snapshot(kinds: kinds, mapActionAvailable: false)
        let plan = try #require(snapshot.plan)
        let layout = plan.layout(size: CGSize(width: 860, height: 250))
        #expect(snapshot.state == .mapped)
        #expect(plan.notMappedBytes == 208 * gb)
        #expect(layout.dots.filter { $0.room == .free }.count == 78)
        #expect(layout.dots.filter { $0.room == .kind("developer") }.count == 60)
        #expect(!layout.dots.contains { $0.room == .notMapped })
        let presentation = RoomOverviewPlanPresentation(plan: plan, hidden: false, format: String.init)
        #expect(presentation.caption.contains("mapped"))
        #expect(presentation.rows.contains { $0.id == .kind("developer") })
    }

    @Test func unmatchedStoppedAndOverlappingMapsAreRefused() {
        let map = home()
        #expect(RoomHomeMap.kinds(roots: [("/Users/example", map)], capacityBytes: 994 * gb,
            freeBytes: 312 * gb, capacityVolumeUUID: "system") == .failure(.otherVolume))
        #expect(RoomHomeMap.kinds(roots: [("/Users/example", map)], capacityBytes: 500 * gb,
            freeBytes: 300 * gb, capacityVolumeUUID: "data") == .failure(.exceedsUsedSpace))
        var stopped = map
        stopped.cancelled = true
        #expect(RoomHomeMap.kinds(roots: [("/Users/example", stopped)], capacityBytes: 994 * gb,
            freeBytes: 312 * gb, capacityVolumeUUID: "data") == .failure(.stoppedMap))
        #expect(RoomHomeMap.kinds(roots: [("/Users/example", map), ("/Users/example/folder", map)], capacityBytes: 994 * gb,
            freeBytes: 312 * gb, capacityVolumeUUID: "data") == .failure(.overlappingRoots))
    }

    @Test func firstVisitOffersOneMapActionAndProgressUsesFinishedKinds() throws {
        let empty = snapshot(kinds: nil, mapActionAvailable: true)
        #expect(empty.action == .mapMac)
        #expect(!empty.mapLinkAvailable)
        let fresh = snapshot(kinds: nil, mapActionAvailable: true, caches: .init(at: now, bytes: 2 * gb, partial: false))
        #expect(fresh.action == .makeRoom(bytes: 2 * gb, partial: false))
        #expect(fresh.mapLinkAvailable)
        let progress = RoomOverviewMapping(files: 25, allocatedBytes: 36 * gb, finishedKinds: ["media": 20 * gb])
        let mapping = snapshot(kinds: nil, mapActionAvailable: true, mapping: progress)
        #expect(mapping.state == .mapping)
        #expect(mapping.action == .stopMapping)
        #expect(mapping.plan?.kindValues.first?.0 == "media")
        #expect(mapping.plan?.notMappedBytes == 662 * gb)
    }

    @Test func wakeDecaysAndDisabledMotionLeavesRadiusAlone() {
        let dots = [CGPoint(x: 10, y: 10)]
        var wake = RoomWakeField(dotCount: 1, enabled: true)
        wake.pointerMoved(to: dots[0], dots: dots)
        #expect(!wake.isAtRest)
        #expect(abs(wake.radius(0, rest: 1) - 2.2) < 0.001)
        for _ in 0..<44 { wake.step(dtMS: 16, dots: dots) }
        #expect(wake.isAtRest)
        wake.press(at: dots[0])
        wake.step(dtMS: 5_000, dots: dots)
        #expect(wake.rings.first?.ageMS == 64)

        var still = RoomWakeField(dotCount: 1, enabled: false)
        still.pointerMoved(to: dots[0], dots: dots)
        still.press(at: dots[0])
        #expect(still.isAtRest)
        #expect(still.radius(0, rest: 2) == 2)
    }

    private func home() -> RoomStoredTree {
        let sizes: [String: Int64] = ["developer": 238_600_000_000, "media": 95_200_000_000,
            "documents": 38_400_000_000, "apps": 42_100_000_000, "archives": 18_200_000_000,
            "system": 28_900_000_000, "hidden": 12_600_000_000]
        let tree = RoomTreeNode(name: "Home", relativePath: "", allocatedBytes: sizes.values.reduce(0, +), fileCount: 41,
            kindBytes: sizes, isPartial: true, isDirectory: true, children: [], other: nil)
        return RoomStoredTree(rootID: "home", displayPath: "~", scannedAt: now, cancelled: false,
                              volumeUUID: "data", issueCount: 1, tree: tree)
    }

    private func snapshot(kinds: RoomHomeKinds?, mapActionAvailable: Bool, caches: RoomCachesCheck? = nil,
                          mapping: RoomOverviewMapping? = nil) -> RoomOverviewSnapshot {
        RoomOverviewSnapshot.make(.init(capacityBytes: 994 * gb, freeBytes: 312 * gb, goalBytes: nil, caches: caches,
            cachesInvalidatedAt: nil, now: now, hidden: false, homeKinds: kinds,
            mapActionAvailable: mapActionAvailable, mapping: mapping), format: String.init)
    }
}
