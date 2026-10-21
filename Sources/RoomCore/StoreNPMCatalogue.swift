#if ROOM_APP_STORE
import Darwin
import Foundation

/// Discovers only fixed-depth prefix buckets beneath explicit read grants.
/// Approval of one bucket never opens or enumerates its siblings or parents.
enum StoreNPMCatalogue {
    static func discover(approvedFolders: [URL], userHome: URL) -> (roots: [CacheRoot], issues: [ScanIssue]) {
        let base = userHome.appendingPathComponent(".npm/_cacache/content-v2/sha512", isDirectory: true)
        let budget = BucketBudget()
        var found: [String: CacheRoot] = [:]
        func add(_ url: URL) throws {
            try budget.check()
            guard let prefixes = NPMContentPolicy.bucketPrefixes(url) else { return }
            let fd = try openDirectory(url)
            close(fd)
            guard found[url.path] == nil else { return }
            guard found.count < 256 else { throw BucketLimit.reached }
            found[url.path] = CacheRoot(id: "store-npm-sha512-\(prefixes.0)-\(prefixes.1)",
                title: "npm downloads · \(prefixes.0)/\(prefixes.1)", subtitle: url.path,
                symbol: "shippingbox", category: "developer", url: url,
                consequence: NPMContentPolicy.consequence, minimumAge: NPMContentPolicy.minimumAge,
                inspectionNodeLimit: 4_096, inspectionTimeLimit: 8, contentValidation: .npmSHA512)
        }
        func inspect(_ root: URL, depth: Int) throws {
            try budget.check()
            if depth == 0 { try add(root); return }
            let fd = try openDirectory(root)
            defer { close(fd) }
            let copy = dup(fd)
            guard copy >= 0, let stream = fdopendir(copy) else {
                if copy >= 0 { close(copy) }
                throw BucketLimit.unavailable
            }
            defer { closedir(stream) }
            while true {
                try budget.check()
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { throw BucketLimit.unavailable }
                    break
                }
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(validatingCString: $0) }
                }
                guard let name else { throw BucketLimit.unavailable }
                if name == "." || name == ".." { continue }
                budget.nodes += 1
                guard NPMContentPolicy.hex(name, count: 2) else { continue }
                var metadata = stat()
                guard fstatat(fd, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                      metadata.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR), metadata.st_uid == getuid(),
                      metadata.st_mode & 0o022 == 0 else { continue }
                do { try inspect(root.appendingPathComponent(name, isDirectory: true), depth: depth - 1) }
                catch BucketLimit.unavailable { continue }
            }
        }
        var issues: [ScanIssue] = []
        do {
            for approved in approvedFolders {
                if contains(base, in: approved) {
                    // A missing known location is normal; never look elsewhere.
                    do { try inspect(base, depth: 2) } catch BucketLimit.unavailable { }
                } else if contains(approved, in: base) {
                    let relative = String(approved.path.dropFirst(base.path.count + 1))
                    let parts = relative.split(separator: "/").map(String.init)
                    guard (1...2).contains(parts.count), parts.allSatisfy({ NPMContentPolicy.hex($0, count: 2) }) else { continue }
                    do { try inspect(approved, depth: 2 - parts.count) } catch BucketLimit.unavailable { }
                }
            }
        } catch is CancellationError {
            issues.append(ScanIssue(url: base, message: "npm prefix discovery was cancelled. Uninspected buckets stay held."))
        } catch {
            issues.append(ScanIssue(url: base, message: "npm prefix discovery reached its bounded folder or time limit. Other buckets remain inspect-only; approve an exact prefix bucket to review it."))
        }
        return (found.values.sorted { $0.url.path < $1.url.path }, issues)
    }

    private static func contains(_ child: URL, in parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }

    private static func openDirectory(_ url: URL) throws -> Int32 {
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BucketLimit.unavailable }
        let components = url.pathComponents.filter { $0 != "/" }
        for (index, component) in components.enumerated() {
            let mode = index == components.count - 1 ? O_RDONLY : O_SEARCH
            let next = openat(fd, component, mode | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw BucketLimit.unavailable }
            fd = next
        }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(), metadata.st_mode & 0o022 == 0 else {
            close(fd); throw BucketLimit.unavailable
        }
        return fd
    }
}

private enum BucketLimit: Error { case reached, unavailable }
private final class BucketBudget {
    let deadline = Date().addingTimeInterval(1)
    var nodes = 0
    func check() throws {
        try Task.checkCancellation()
        guard nodes < 4_096, Date() < deadline else { throw BucketLimit.reached }
    }
}
#endif
