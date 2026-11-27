import Foundation
import Testing
@testable import RoomApp

@Suite("Developer folder roles and unreferenced dates") @MainActor
struct RoomDeveloperModelTests {
    @Test func unreferencedDatesPersistAndOnlyCompleteScansChangeThem() throws {
        let key = "gradle:7.6.4-bin"
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        let now = first + 140 * 86_400
        let record = RoomDevUnreferenced().updated(orphanKeys: [key], referencedKeys: [], scanComplete: true, now: first)
        // DMR-C93 through DMR-C96.
        #expect(record.updated(orphanKeys: [], referencedKeys: [], scanComplete: false, now: now) == record)
        #expect(record.updated(orphanKeys: [key], referencedKeys: [], scanComplete: true, now: now).since[key] == first)
        #expect(record.updated(orphanKeys: [], referencedKeys: [key], scanComplete: true, now: now).since.isEmpty)
        #expect(RoomDevUnreferenced.caption(since: first, now: now, thresholdDays: 90) == "Not referenced for 4 months")
        #expect(RoomDevUnreferenced.caption(since: first, now: first + 59 * 86_400, thresholdDays: 90) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomDeveloperUnreferencedStore(directory: directory)
        store.save(record)
        #expect(store.load() == record)
        let contents = try String(contentsOf: directory.appendingPathComponent("developer-unreferenced.json"), encoding: .utf8)
        #expect(!contents.contains(directory.path))
    }
}
