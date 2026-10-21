import CryptoKit
import Darwin
import Foundation

/// An explicitly reviewed exception for completed npm content objects. This is
/// not a running-process observation and never authorizes index/tmp eviction.
public enum CacheContentValidation: Sendable, Equatable {
    case npmSHA512
}

struct NPMContentLimits: Sendable {
    var maximumFileBytes: Int64 = 64 * 1_024 * 1_024
    var maximumScanBytes: Int64 = 512 * 1_024 * 1_024
    var maximumFiles: Int = 4_096
    var timeLimit: TimeInterval = 8
    static let standard = NPMContentLimits()
}

/// Confined to one CacheEngine operation. Reservations bound unsuccessful reads
/// as well as successful hashes; limits can only hold more content in place.
final class NPMContentBudget {
    let limits: NPMContentLimits
    lazy var deadline: Date = Date().addingTimeInterval(max(0, limits.timeLimit))
    private(set) var bytes: Int64 = 0
    private(set) var files = 0
    private(set) var limited = false
    init(_ limits: NPMContentLimits = .standard) {
        self.limits = limits
    }
    func check() throws {
        try Task.checkCancellation()
        guard Date() < deadline else {
            limited = true
            throw NPMContentError.message("The bounded npm content check reached its time limit. This item stays in place.")
        }
    }
    func reserve(_ size: Int64) throws {
        try check()
        guard size >= 0, size <= max(0, limits.maximumFileBytes) else {
            throw NPMContentError.message("This npm object exceeds the bounded content-read size. Inspect it manually.")
        }
        guard files < max(0, limits.maximumFiles), size <= max(0, limits.maximumScanBytes) - bytes else {
            limited = true
            throw NPMContentError.message("The bounded npm content check reached its file or byte limit. This item stays in place.")
        }
        files += 1
        bytes += size
    }
}

enum NPMContentPolicy {
    static let minimumAge: TimeInterval = 30 * 86_400
    static let consequence = "Only verified npm SHA512 download objects modified over 30 days ago can move to Trash. Installs may download them again; active installs may retry and offline installs may fail. This does not prove an object is unused. Indexes, temporary data and installed packages stay in place. Trash must be emptied to release its disk space."

    static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// A bucket is fixed to the known layout. Unknown formats fail closed.
    static func bucketPrefixes(_ url: URL) -> (String, String)? {
        let pieces = url.pathComponents
        guard url.isFileURL, url.path == url.roomLexicallyNormalized.path, pieces.count >= 7,
              Array(pieces.suffix(6).prefix(4)) == [".npm", "_cacache", "content-v2", "sha512"],
              hex(pieces[pieces.count - 2], count: 2), hex(pieces[pieces.count - 1], count: 2) else { return nil }
        return (pieces[pieces.count - 2], pieces[pieces.count - 1])
    }

    static func expectedDigest(originalURL: URL, root: CacheRoot) -> String? {
        guard root.contentValidation == .npmSHA512, root.scope == .children,
              let prefixes = bucketPrefixes(root.url), originalURL.isFileURL,
              originalURL.path == originalURL.roomLexicallyNormalized.path,
              originalURL.deletingLastPathComponent().path == root.url.path,
              hex(originalURL.lastPathComponent, count: 124) else { return nil }
        return prefixes.0 + prefixes.1 + originalURL.lastPathComponent
    }

    /// `source` may be an exact returned Trash item; its original path remains
    /// the digest authority because Finder can rename the moved item.
    static func verify(source: URL, originalURL: URL, root: CacheRoot,
                       identity expected: FileIdentity, budget: NPMContentBudget,
                       exactTrashItem: Bool = false) throws {
        guard source.isFileURL, source.path == source.roomLexicallyNormalized.path,
              let digest = expectedDigest(originalURL: originalURL, root: root) else {
            throw NPMContentError.message("This is not an allowlisted npm SHA512 content object. It stays in place.")
        }
        try budget.check()
        // An exact Trash bookmark need not authorize opening the whole Trash
        // directory. Core has already validated its fixed path and ancestry.
        let parent: Int32? = exactTrashItem ? nil : try openDirectory(source.deletingLastPathComponent())
        defer { if let parent { close(parent) } }
        // O_NONBLOCK prevents a replaced FIFO from blocking before fstat rejects it.
        // Darwin rejects O_NOFOLLOW combined with O_NOFOLLOW_ANY (EINVAL).
        // Use the component flag for openat and the full-path flag for the
        // exact bookmarked item; both branches refuse symbolic links.
        let flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC
        let fd = parent.map { openat($0, source.lastPathComponent, flags | O_NOFOLLOW) }
            ?? open(source.path, flags | O_NOFOLLOW_ANY)
        guard fd >= 0 else { throw NPMContentError.message("The npm object could not be opened without following links. It stays in place.") }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, identity(before) == expected,
              before.st_uid == getuid(), before.st_nlink == 1,
              before.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG), before.st_mode & 0o022 == 0 else {
            throw NPMContentError.message("The npm object changed, has shared links or has unsafe ownership/permissions. It stays in place.")
        }
        try budget.reserve(Int64(before.st_size))
        var hasher = SHA512()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var total: Int64 = 0
        while true {
            try budget.check()
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw NPMContentError.message("The npm object could not be completely read. It stays in place.")
            }
            if count == 0 { break }
            total += Int64(count)
            guard total <= Int64(before.st_size), total <= budget.limits.maximumFileBytes else {
                throw NPMContentError.message("The npm object grew during verification. Scan again.")
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        guard total == Int64(before.st_size), fstat(fd, &after) == 0,
              identity(after) == expected, after.st_uid == getuid(), after.st_nlink == 1 else {
            throw NPMContentError.message("The npm object changed during content verification. Scan again.")
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == digest else {
            throw NPMContentError.message("The file contents do not match their npm SHA512 address. This item stays in place.")
        }
    }

    static func identity(_ info: stat) -> FileIdentity {
        FileIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec),
            byteCount: Int64(info.st_size), mode: info.st_mode)
    }

    /// Search-only traversal above the selected parent does not enumerate or
    /// inspect an unapproved ancestor. Every component is opened no-follow.
    private static func openDirectory(_ url: URL) throws -> Int32 {
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw NPMContentError.message("The npm object parent is unavailable.") }
        for component in url.pathComponents where component != "/" {
            let next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw NPMContentError.message("The npm object path is unavailable or linked. It stays in place.") }
            fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
            close(fd)
            throw NPMContentError.message("The npm object parent has unsafe ownership or permissions. It stays in place.")
        }
        return fd
    }
}

enum NPMContentError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
}
