import Darwin
import Foundation

/// Why Room will not move a folder from the Disk Map. Protected rooms have no tick.
public enum FolderProtection: Equatable, Sendable {
    case outsideHome, home, library, hidden, package, notAFolder, unverified

    /// One plain sentence for the note under the map.
    public func sentence(name: String) -> String {
        switch self {
        case .outsideHome: "Room only moves folders inside your home folder"
        case .home: "Room will not move your home folder"
        case .library: "Room will not move \(name)"
        case .hidden: "Room will not move hidden folders"
        case .package: "Room will not move app or library packages"
        case .notAFolder: "Room moves folders only"
        case .unverified: "Room could not check \(name), so it stays"
        }
    }
}

/// One folder chosen on the Disk Map, with the identity Room saw when the review opened.
public struct FolderTrashRequest: Equatable, Sendable {
    public let url: URL
    public let bytes: Int64
    public let device: UInt64
    public let inode: UInt64

    public init(url: URL, bytes: Int64, device: UInt64, inode: UInt64) {
        self.url = url; self.bytes = bytes; self.device = device; self.inode = inode
    }
}

public struct FolderTrashItem: Codable, Equatable, Sendable {
    public let originalPath: String
    public var trashPath: String?
    public let bytes: Int64
    public let device: UInt64
    public let inode: UInt64
    public var status: ActivityStatus
    public var message: String?
}

/// A receipt for folders moved from the Disk Map. Saved before anything moves; Restore reads it back.
public struct FolderTrashReceipt: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public var items: [FolderTrashItem]

    public var trashedBytes: Int64 { items.filter { $0.status == .trashed }.reduce(0) { $0 + $1.bytes } }
    public var canRestore: Bool { items.contains { $0.status == .trashed } }
    public var restoredCount: Int { items.filter { $0.status == .restored }.count }
    public var failedCount: Int { items.filter { $0.status == .failed }.count }
}

/// Moves a person's own folders to Trash from the Disk Map, with a receipt and Restore (nav-v3, Direct edition).
/// Separate from `CacheEngine` on purpose: that engine only moves candidates minted by a completed cache scan, and
/// this one must never widen it. Every folder is re-checked just before it moves: still inside home, not protected,
/// a real folder (no link, no mount point), and the same folder (device and inode) Room saw in the review.
public actor FolderTrashEngine {
    private let home: URL
    private let directory: URL
    private let trash: @Sendable (URL) throws -> URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL,
                trash: (@Sendable (URL) throws -> URL)? = nil) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
        self.directory = directory
        self.trash = trash ?? { url in
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            guard let result else { throw CocoaError(.fileWriteUnknown) }
            return result as URL
        }
    }

    // MARK: Protection (pure)

    private static let libraryNames: Set<String> = ["Library", "Applications", "System", ".Trash"]
    private static let packageExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "bundle",
                                                         "framework", "plugin", "kext", "pkg", "sparsebundle", "xcarchive"]

    /// Whether a folder is protected, from its path alone (the Disk Map hides ticks with this). `home` is the real,
    /// symlink-resolved home folder.
    public nonisolated static func protection(for url: URL, home: URL) -> FolderProtection? {
        let homeParts = home.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts else { return .outsideHome }
        let inside = Array(parts.dropFirst(homeParts.count))
        guard let first = inside.first else { return .home }
        if inside.contains("..") || inside.contains(".") { return .unverified }
        if libraryNames.contains(first) { return .library }
        if inside.contains(where: { $0.hasPrefix(".") }) { return .hidden }
        if inside.contains(where: { packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) { return .package }
        return nil
    }

    /// The identity of a folder right now, or nil when it is not a plain folder Room can verify.
    public nonisolated static func identity(of url: URL) -> (device: UInt64, inode: UInt64)? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        var parent = stat()
        guard lstat(url.deletingLastPathComponent().path, &parent) == 0, parent.st_dev == info.st_dev else { return nil }
        return (UInt64(info.st_dev), UInt64(info.st_ino))
    }

    // MARK: Move and restore

    public func move(_ requests: [FolderTrashRequest]) -> FolderTrashReceipt {
        var receipt = FolderTrashReceipt(id: UUID(), date: Date(), items: requests.map {
            FolderTrashItem(originalPath: $0.url.standardizedFileURL.path, trashPath: nil, bytes: $0.bytes,
                            device: $0.device, inode: $0.inode, status: .pending, message: nil)
        })
        // The receipt exists before anything moves, so an interrupted move can still be traced.
        save(receipt)
        for index in receipt.items.indices {
            let item = receipt.items[index]
            let url = URL(fileURLWithPath: item.originalPath, isDirectory: true)
            if let problem = check(url, device: item.device, inode: item.inode) {
                receipt.items[index].status = .failed
                receipt.items[index].message = problem
                continue
            }
            do {
                let destination = try trash(url)
                receipt.items[index].trashPath = destination.path
                receipt.items[index].status = .trashed
            } catch {
                receipt.items[index].status = .failed
                receipt.items[index].message = "Trash refused this folder. It is where it was."
            }
            save(receipt)
        }
        save(receipt)
        return receipt
    }

    /// Puts trashed folders back when the Trash item is still the same folder and nothing has taken its place.
    public func restore(receiptID: UUID) -> FolderTrashReceipt? {
        guard var receipt = load(receiptID) else { return nil }
        for index in receipt.items.indices where receipt.items[index].status == .trashed {
            let item = receipt.items[index]
            guard let trashPath = item.trashPath else { continue }
            let source = URL(fileURLWithPath: trashPath, isDirectory: true)
            let destination = URL(fileURLWithPath: item.originalPath, isDirectory: true)
            var info = stat()
            guard lstat(source.path, &info) == 0, UInt64(info.st_ino) == item.inode, UInt64(info.st_dev) == item.device else {
                receipt.items[index].message = "The folder is no longer in Trash."
                continue
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                receipt.items[index].message = "Something else is at the original place now. The folder stays in Trash."
                continue
            }
            guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else {
                receipt.items[index].message = "Its original folder is gone. The folder stays in Trash."
                continue
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                receipt.items[index].status = .restored
                receipt.items[index].message = nil
            } catch {
                receipt.items[index].message = "Room could not put it back. It is still in Trash."
            }
        }
        save(receipt)
        return receipt
    }

    public func history() -> [FolderTrashReceipt] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(FolderTrashReceipt.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    private func check(_ url: URL, device: UInt64, inode: UInt64) -> String? {
        let resolved = url.standardizedFileURL
        if let protection = Self.protection(for: resolved, home: home) {
            return protection.sentence(name: resolved.lastPathComponent)
        }
        // A link anywhere above it could point outside home: the real path must still be inside.
        let real = resolved.resolvingSymlinksInPath()
        guard Self.protection(for: real, home: home) == nil, real.path == resolved.path else {
            return "The folder moved or became a link. It stays."
        }
        guard let now = Self.identity(of: resolved) else { return "Room could not check this folder, so it stays." }
        guard now.device == device, now.inode == inode else { return "The folder changed since the review. It stays." }
        guard !directory.standardizedFileURL.path.hasPrefix(resolved.path + "/") else { return "Room keeps its own records here." }
        return nil
    }

    private func save(_ receipt: FolderTrashReceipt) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(receipt) {
            try? data.write(to: directory.appendingPathComponent(receipt.id.uuidString + ".json"), options: .atomic)
        }
    }

    private func load(_ id: UUID) -> FolderTrashReceipt? {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(FolderTrashReceipt.self, from: $0) }
    }
}
