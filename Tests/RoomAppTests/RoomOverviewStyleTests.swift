import Foundation
import Testing
@testable import RoomApp

@Suite("Overview styles")
struct RoomOverviewStyleTests {
    @Test func solidRoomsDescribeTheSameBytesAndKeepUnmappedHonest() throws {
        let kinds = RoomHomeKinds(kinds: [("developer", 50)], mappedBytes: 50_000_000_000,
                                  notMappedBytes: 100_000_000_000, mappedAt: .distantPast)
        let plan = RoomOverviewPlanInput(capacityBytes: 250_000_000_000, freeBytes: 100_000_000_000,
                                         goalBytes: nil, homeKinds: kinds)
        let format = { (bytes: Int64) in "\(bytes / 1_000_000_000) GB" }
        let dots = RoomOverviewPlanPresentation(plan: plan, hidden: false, format: format)
        let rooms = RoomOverviewPlanPresentation(plan: plan, hidden: false, solidKinds: true, format: format)
        #expect(RoomOverviewStyle.isAvailable(homeKinds: kinds))
        #expect(!RoomOverviewStyle.isAvailable(homeKinds: nil))
        #expect(rooms.rows.map(\.size) == dots.rows.map(\.size))
        #expect(rooms.caption.contains("Area shows storage size"))
        let measured = try #require(rooms.rows.first { $0.id == .kind("developer") })
        #expect(measured.spoken.contains("50 GB") && measured.dots.isEmpty)
        let unmapped = try #require(rooms.rows.first { $0.id == .notMapped })
        #expect(unmapped.spoken.contains("Room hasn't looked here"))
    }
}
