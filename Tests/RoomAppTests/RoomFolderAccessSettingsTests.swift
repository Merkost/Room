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

    @Test func missingPathReportsFolderNotFound() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomFolderAccessMissing-\(UUID().uuidString)", isDirectory: true)
        let status = RoomFolderAccessStatus.status(for: missing)
        #expect(status == .missing && status.text == "Folder not found" && !status.isReadable)
    }

    @Test func lockedFolderReportsProtectedByMacOS() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/RoomFolderAccessLocked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let status = RoomFolderAccessStatus.status(for: folder)
        #expect(status == .protectedByMacOS && status.text == "Protected by macOS" && !status.isReadable)
    }
}
