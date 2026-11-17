import Foundation
import Testing
@testable import RoomApp

@Suite("Folder Access settings")
struct RoomFolderAccessSettingsTests {
    @Test func readableFolderReportsReadsSizes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomFolderAccessSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = RoomFolderAccessStatus.status(for: folder)
        #expect(status == .readsSizes)
        #expect(status.text == "Reads sizes")
        #expect(status.isReadable)
    }

    @Test func unreadablePathReportsProtectedByMacOS() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomFolderAccessMissing-\(UUID().uuidString)", isDirectory: true)
        let status = RoomFolderAccessStatus.status(for: missing)
        #expect(!FileManager.default.isReadableFile(atPath: missing.path))
        #expect(status == .protectedByMacOS)
        #expect(status.text == "Protected by macOS")
        #expect(!status.isReadable)
    }
}
