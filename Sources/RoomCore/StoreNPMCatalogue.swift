#if ROOM_APP_STORE
import CryptoKit
import Darwin
import Foundation

/// Walks the fixed SHA512 prefix namespace in bounded, resumable batches.
/// A cursor is only an enumeration position; it never grants file access or
/// preserves cleanup IDs. Exact bucket approval never reads a sibling directory.
enum StoreNPMCatalogue {
    static func discover(approvedFolders: [URL], userHome: URL,
                         continuation: String? = nil) -> (roots: [CacheRoot], issues: [ScanIssue], coverage: NPMDiscoveryCoverage?) {
        let base = userHome.appendingPathComponent(".npm/_cacache/content-v2/sha512", isDirectory: true)
        let budget = BucketBudget()
        let approved = approvedFolders.prefix(32).filter(\.isFileURL).map(\.roomLexicallyNormalized)
        let folders = Dictionary(grouping: approved, by: \.path).compactMap { $0.value.first }
            .filter { candidate in !approved.contains { $0.path != candidate.path && contains(candidate, in: $0) } }
            .sorted { $0.path < $1.path }
        let ranges = folders.compactMap { authorizedRange(for: $0, base: base) }.sorted { $0.lower < $1.lower }
        guard userHome.isFileURL, userHome.path == userHome.roomLexicallyNormalized.path,
              !ranges.isEmpty else { return ([], [], nil) }

        var issues: [ScanIssue] = []
        var scopeRecords: [ScopeRecord] = []
        do {
            for folder in folders {
                try budget.reserveNode()
                let fd = try openDirectory(folder)
                defer { close(fd) }
                var metadata = stat()
                guard fstat(fd, &metadata) == 0 else { throw BucketLimit.unavailable }
                scopeRecords.append(ScopeRecord(path: folder.path,
                    device: UInt64(UInt32(bitPattern: metadata.st_dev)), inode: UInt64(metadata.st_ino),
                    owner: UInt32(metadata.st_uid), mode: UInt16(metadata.st_mode)))
            }
        } catch is CancellationError {
            return ([], [ScanIssue(url: base, message: "npm prefix discovery was cancelled. No complete discovery batch was produced.")], nil)
        } catch {
            return ([], [ScanIssue(url: base, message: "The approved npm scope could not be checked within its discovery limits. Approve the physical folders again and restart this scan.")], nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let manifest = ScopeManifest(home: userHome.path, folders: scopeRecords,
                                     ranges: ranges.map { [$0.lower, $0.upper] })
        guard let data = try? encoder.encode(manifest) else { return ([], [], nil) }
        let scopeID = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        var position = ranges[0].lower
        if let continuation {
            guard continuation.utf8.count <= 2_048, let data = Data(base64Encoded: continuation),
                  let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
                  cursor.version == 1, cursor.scopeID == scopeID,
                  ranges.contains(where: { $0.contains(cursor.nextBucket) }) else {
                let issue = ScanIssue(url: base, message: "This npm continuation does not match the approved folders or their physical identity. Restart the npm scan from the beginning.")
                return ([], [issue], NPMDiscoveryCoverage(inspectedBuckets: 0, hasMore: false, nextCursor: nil, scopeID: scopeID))
            }
            position = cursor.nextBucket
        }

        var roots: [CacheRoot] = []
        var inspected = 0
        var prefixFD: Int32?
        var openedPrefix: Int?
        defer { if let prefixFD { close(prefixFD) } }
        func resetPrefix() {
            if let prefixFD { close(prefixFD) }
            prefixFD = nil
            openedPrefix = nil
        }
        func nextAuthorized(_ index: Int) -> Int? {
            ranges.first(where: { $0.upper > index }).map { max(index, $0.lower) }
        }
        func noteUnavailable(_ url: URL) {
            // Keep feedback bounded as well as filesystem work.
            if issues.count < 32 {
                issues.append(ScanIssue(url: url, message: "This npm prefix is unavailable, linked or has unsafe ownership or permissions. Its objects stay held."))
            }
        }
        func addBucket(_ url: URL, descriptor: Int32) throws {
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, safeDirectory(metadata),
                  let prefixes = NPMContentPolicy.bucketPrefixes(url) else { throw BucketLimit.unavailable }
            inspected += 1 // Empty physical buckets count toward this batch too.
            roots.append(CacheRoot(id: "store-npm-sha512-\(prefixes.0)-\(prefixes.1)",
                title: "npm downloads · \(prefixes.0)/\(prefixes.1)", subtitle: url.path,
                symbol: "shippingbox", category: "developer", url: url,
                consequence: NPMContentPolicy.consequence, minimumAge: NPMContentPolicy.minimumAge,
                inspectionNodeLimit: 4_096, inspectionTimeLimit: 8, contentValidation: .npmSHA512))
        }

        do {
            while let index = nextAuthorized(position) {
                position = index
                try budget.check()
                guard inspected < 256 else { throw BucketLimit.reached }
                guard let range = ranges.first(where: { $0.contains(index) }) else { break }
                let first = index / 256, second = index % 256
                let firstName = String(format: "%02x", first)
                let secondName = String(format: "%02x", second)
                let bucket = base.appendingPathComponent(firstName, isDirectory: true)
                    .appendingPathComponent(secondName, isDirectory: true)

                if range.exactBucket {
                    // Opening this approved bucket walks ancestors with O_SEARCH
                    // only. It does not list or read a first-level prefix parent.
                    resetPrefix()
                    try budget.reserveNode()
                    do {
                        let fd = try openDirectory(bucket)
                        defer { close(fd) }
                        try addBucket(bucket, descriptor: fd)
                    } catch BucketLimit.missing { }
                    catch BucketLimit.unavailable { noteUnavailable(bucket) }
                    position = index + 1
                    continue
                }

                if openedPrefix != first {
                    resetPrefix()
                    try budget.reserveNode()
                    let prefixURL = base.appendingPathComponent(firstName, isDirectory: true)
                    do {
                        prefixFD = try openDirectory(prefixURL)
                        openedPrefix = first
                    } catch BucketLimit.missing {
                        position = (first + 1) * 256
                        continue
                    } catch BucketLimit.unavailable {
                        noteUnavailable(prefixURL)
                        position = (first + 1) * 256
                        continue
                    }
                }
                guard let prefixFD else { throw BucketLimit.unavailable }
                try budget.reserveNode()
                let fd = openat(prefixFD, secondName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if fd >= 0 {
                    defer { close(fd) }
                    do { try addBucket(bucket, descriptor: fd) }
                    catch BucketLimit.unavailable { noteUnavailable(bucket) }
                } else if errno != ENOENT {
                    noteUnavailable(bucket)
                }
                // Every checked slot advances, including missing and empty
                // buckets. A continuation cannot repeat a full empty batch.
                position = index + 1
            }
        } catch is CancellationError {
            issues.append(ScanIssue(url: base, message: "npm prefix discovery was cancelled. This batch is incomplete; uninspected buckets stay held."))
        } catch {
            // The next cursor resumes the first uninspected authorized slot.
        }

        let next = nextAuthorized(position)
        let nextCursor = next.flatMap { try? encoder.encode(Cursor(version: 1, scopeID: scopeID, nextBucket: $0)).base64EncodedString() }
        if next != nil && !Task.isCancelled {
            issues.append(ScanIssue(url: base, message: "This npm discovery batch inspected \(inspected) prefix buckets. More approved prefix space remains; continue the npm scan to inspect the next bounded batch."))
        }
        return (roots, issues, NPMDiscoveryCoverage(inspectedBuckets: inspected,
            hasMore: next != nil, nextCursor: nextCursor, scopeID: scopeID))
    }

    private struct Cursor: Codable { let version: Int; let scopeID: String; let nextBucket: Int }
    private struct ScopeRecord: Codable {
        let path: String
        let device: UInt64
        let inode: UInt64
        let owner: UInt32
        let mode: UInt16
    }
    private struct ScopeManifest: Codable { let home: String; let folders: [ScopeRecord]; let ranges: [[Int]] }
    private struct BucketRange {
        let lower: Int
        let upper: Int
        let exactBucket: Bool
        func contains(_ index: Int) -> Bool { lower <= index && index < upper }
    }
    private static func authorizedRange(for approved: URL, base: URL) -> BucketRange? {
        guard approved.isFileURL, approved.path != "/" else { return nil }
        if contains(base, in: approved) { return BucketRange(lower: 0, upper: 65_536, exactBucket: false) }
        guard contains(approved, in: base), approved.path != base.path else { return nil }
        let parts = approved.path.dropFirst(base.path.count + 1).split(separator: "/").map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ NPMContentPolicy.hex($0, count: 2) }),
              let first = Int(parts[0], radix: 16) else { return nil }
        let lower = first * 256 + (parts.count == 2 ? Int(parts[1], radix: 16)! : 0)
        return BucketRange(lower: lower, upper: lower + (parts.count == 2 ? 1 : 256), exactBucket: parts.count == 2)
    }
    private static func contains(_ child: URL, in parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }
    private static func safeDirectory(_ metadata: stat) -> Bool {
        metadata.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) && metadata.st_uid == getuid()
            && metadata.st_mode & 0o022 == 0
    }
    private static func openDirectory(_ url: URL) throws -> Int32 {
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BucketLimit.unavailable }
        let components = url.pathComponents.filter { $0 != "/" }
        for (index, component) in components.enumerated() {
            let mode = index == components.count - 1 ? O_RDONLY : O_SEARCH
            let next = openat(fd, component, mode | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(fd)
            guard next >= 0 else { throw failure == ENOENT ? BucketLimit.missing : BucketLimit.unavailable }
            fd = next
        }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, safeDirectory(metadata) else {
            close(fd); throw BucketLimit.unavailable
        }
        return fd
    }
}

private enum BucketLimit: Error { case reached, missing, unavailable }
private final class BucketBudget {
    private let clock = ContinuousClock()
    private let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    private var nodes = 0
    func check() throws {
        try Task.checkCancellation()
        guard nodes < 4_096, clock.now < deadline else { throw BucketLimit.reached }
    }
    func reserveNode() throws { try check(); nodes += 1 }
}
#endif
