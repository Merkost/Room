import Foundation
import SwiftUI
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor
struct RoomDiskMapRoomsTests {
    private func room(_ path: String, _ gb: Int64, _ protection: FolderProtection? = nil) -> RoomMapSelection.Room {
        .init(path: path, name: path, bytes: gb * 1_000_000_000, protection: protection)
    }

    @Test func tickingSelectsSeveralAndCountsTheShare() {
        let rooms = [room("Developer", 120), room("Library", 96, .library), room("Movies", 88), room("Downloads", 14)]
        var selection = RoomMapSelection()
        #expect(selection.toggle(rooms[2]) == nil)
        #expect(selection.toggle(rooms[3]) == nil)
        #expect(selection.count == 2)
        #expect(selection.bytes(in: rooms) == 102_000_000_000)
        #expect(selection.line(in: rooms, levelBytes: 430_000_000_000, place: "your home") == "2 selected, 102 GB, 24% of your home")
        #expect(selection.toggle(rooms[1]) == .library, "Library never ticks")
        #expect(!selection.contains("Library"))
        selection.toggle(rooms[2])
        #expect(selection.ticked == ["Downloads"], "a second tick unticks")
        selection.keep(only: ["Developer"])
        #expect(selection.isEmpty)
    }

    @Test func columnsFollowTheMockup() {
        #expect(RoomDiskRoomsLayout.columns(count: 7) == [[0], [1, 2], [3, 4], [5, 6]])
        #expect(RoomDiskRoomsLayout.columns(count: 8) == [[0], [1, 2], [3, 4], [5, 6, 7]], "a lone last room joins the column before")
        #expect(RoomDiskRoomsLayout.columns(count: 2) == [[0], [1]])
        #expect(RoomDiskRoomsLayout.columns(count: 0).isEmpty)
    }

    @Test func framesFillTheMapAndGiveZoomOrigins() {
        let bytes: [Int64] = [120, 96, 88, 74, 30, 14, 8].map { $0 * 1_000_000_000 }
        let size = CGSize(width: 800, height: 300)
        let frames = RoomDiskRoomsLayout.frames(bytes, in: size, gap: 6, minimum: CGSize(width: 96, height: 34))
        #expect(frames.count == 7)
        #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 800.5 && $0.minY >= 0 && $0.maxY <= 300.5 })
        #expect(frames.allSatisfy { $0.width >= 95.9 && $0.height >= 33.9 }, "every room can hold a label")
        #expect(abs(frames[0].height - 300) < 0.5, "the largest room has the first column")
        let anchor = RoomDiskRoomsLayout.anchor(of: frames[0], in: size)
        #expect(anchor.x < 0.25 && abs(anchor.y - 0.5) < 0.01, "stepping into the first room zooms from its centre")
    }

    @Test func protectionsComeFromTheEngineAndStoreHasNoTicks() {
        let model = RoomFolderTrashModel(home: URL(fileURLWithPath: "/Users/someone", isDirectory: true),
                                         directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #if ROOM_APP_STORE
        #expect(!RoomFolderTrashModel.isAvailable)
        #expect(model.protection(for: URL(fileURLWithPath: "/Users/someone/Movies")) == .unverified, "Store never offers the tick")
        #else
        #expect(RoomFolderTrashModel.isAvailable)
        #expect(model.protection(for: URL(fileURLWithPath: "/Users/someone/Movies")) == nil)
        #expect(model.protection(for: URL(fileURLWithPath: "/Users/someone/Library")) == .library)
        #endif
        #expect(model.protection(for: nil) == .unverified, "a room Room cannot locate is not movable")
    }

    @Test func folderReceiptsShowInHistory() async throws {
        #if !ROOM_APP_STORE
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("FolderModel-\(UUID().uuidString)").resolvingSymlinksInPath()
        let home = base.appendingPathComponent("home", isDirectory: true)
        let trash = base.appendingPathComponent("trash", isDirectory: true)
        let movies = home.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let model = RoomFolderTrashModel(home: home, directory: base.appendingPathComponent("receipts")) { source in
            let destination = trash.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        let review = try #require(model.review([(url: movies, name: "Movies", bytes: 88_000_000_000)]))
        #expect(review.bytes == 88_000_000_000)
        let receipt = try #require(await model.move(review))
        #expect(model.owns(receipt.id))
        #expect(model.activity.first?.title == "1 folder from Disk Map")
        #expect(model.activity.first?.details.first?.source == "diskMap")
        #expect(model.lastMovedID == receipt.id)
        await model.restore(receipt.id)
        #expect(FileManager.default.fileExists(atPath: movies.path))
        #endif
    }
}
