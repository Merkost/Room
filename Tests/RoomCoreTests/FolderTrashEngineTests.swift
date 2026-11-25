import Foundation
import Testing
@testable import RoomCore

struct FolderTrashEngineTests {
    private func sandbox() throws -> (home: URL, trash: URL, receipts: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderTrash-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let receipts = root.appendingPathComponent("receipts", isDirectory: true)
        for url in [home, trash, receipts] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (home, trash, receipts, root)
    }

    private func engine(_ box: (home: URL, trash: URL, receipts: URL, root: URL)) -> FolderTrashEngine {
        let trash = box.trash
        return FolderTrashEngine(home: box.home, directory: box.receipts) { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent + "-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
    }

    private func folder(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: url.appendingPathComponent("file"))
        return url
    }

    private func request(_ url: URL, bytes: Int64 = 1_000) throws -> FolderTrashRequest {
        let id = try #require(FolderTrashEngine.identity(of: url))
        return FolderTrashRequest(url: url, bytes: bytes, device: id.device, inode: id.inode)
    }

    @Test func protectedRoomsHaveNoTick() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        func p(_ path: String) -> FolderProtection? { FolderTrashEngine.protection(for: URL(fileURLWithPath: path), home: home) }
        #expect(p("/Users/someone/Movies") == nil)
        #expect(p("/Users/someone/Developer/old-project") == nil)
        #expect(p("/Users/someone") == .home)
        #expect(p("/Users/someone/Library") == .library)
        #expect(p("/Users/someone/Library/Application Support/Foo") == .library)
        #expect(p("/Users/someone/Applications") == .library)
        #expect(p("/Users/someone/.config") == .hidden)
        #expect(p("/Users/someone/Pictures/Photos Library.photoslibrary") == .package)
        #expect(p("/Users/someone/Desktop/Tool.app") == .package)
        #expect(p("/Users/other/Movies") == .outsideHome)
        #expect(p("/Applications/Xcode.app") == .outsideHome)
        #expect(p("/Users/someonelse/Movies") == .outsideHome, "a prefix is not a parent")
        #expect(FolderProtection.library.sentence(name: "Library") == "Room will not move Library")
    }

    @Test func movesToTrashWithAReceiptAndRestores() async throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let movies = try folder("Movies", in: box.home)
        let engine = engine(box)
        let receipt = await engine.move([try request(movies, bytes: 88_000_000_000)])
        #expect(receipt.items.first?.status == .trashed)
        #expect(receipt.trashedBytes == 88_000_000_000 && receipt.canRestore)
        #expect(!FileManager.default.fileExists(atPath: movies.path))
        #expect(await engine.history().map(\.id) == [receipt.id], "the receipt is saved")

        let restored = try #require(await engine.restore(receiptID: receipt.id))
        #expect(restored.items.first?.status == .restored)
        #expect(FileManager.default.fileExists(atPath: movies.appendingPathComponent("file").path))
        #expect(!restored.canRestore)
    }

    @Test func refusesAFolderThatChangedSinceTheReview() async throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let docs = try folder("Documents", in: box.home)
        let before = try request(docs)
        try FileManager.default.removeItem(at: docs)
        _ = try folder("Documents", in: box.home)      // same name, a different folder now
        let receipt = await engine(box).move([before])
        #expect(receipt.items.first?.status == .failed)
        #expect(FileManager.default.fileExists(atPath: docs.path), "nothing moved")
    }

    @Test func refusesProtectedOutsideAndLinkedFolders() async throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let library = try folder("Library", in: box.home)
        let outside = try folder("Elsewhere", in: box.root)
        let link = box.home.appendingPathComponent("Shortcut", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(FolderTrashEngine.identity(of: link) == nil, "a link is not a folder Room can verify")
        let receipt = await engine(box).move([try request(library), try request(outside)])
        #expect(receipt.items.allSatisfy { $0.status == .failed })
        #expect(FileManager.default.fileExists(atPath: library.path) && FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func restoreLeavesTheFolderWhenSomethingTookItsPlace() async throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let downloads = try folder("Downloads", in: box.home)
        let engine = engine(box)
        let receipt = await engine.move([try request(downloads)])
        _ = try folder("Downloads", in: box.home)
        let restored = try #require(await engine.restore(receiptID: receipt.id))
        #expect(restored.items.first?.status == .trashed, "the trashed folder stays in Trash")
        #expect(restored.items.first?.message?.contains("Something else") == true)
    }
}
