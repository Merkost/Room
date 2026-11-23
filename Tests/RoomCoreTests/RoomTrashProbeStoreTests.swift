#if ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomCore

struct RoomTrashProbeStoreTests {
    @Test func staleBookmarkResolvesToItsCurrentPath() throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RoomProbe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("first")
        try Data("x".utf8).write(to: first)
        let data = try first.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let second = directory.appendingPathComponent("second")
        try FileManager.default.moveItem(at: first, to: second)
        guard case .resolved(let path) = RoomTrashProbe.bookmark(data) else {
            Issue.record("a bookmark that resolves must not be treated as failed")
            return
        }
        #expect(path == second.roomLexicallyNormalized.path)
    }
}
#endif
