import Darwin
import Foundation

extension CacheConfiguration {
    /// A sandboxed catalogue is built only from explicitly approved physical
    /// folders. Construction never enumerates a directory or probes a known
    /// cache path outside those approvals. Unknown selected data is inspect-only.
    public static func store(approvedFolders: [URL], userHome: URL,
                             npmContinuation: String? = nil) -> CacheConfiguration {
        let home = userHome.roomLexicallyNormalized
        guard userHome.isFileURL, home.path != "/" else {
            return CacheConfiguration(roots: [], homeDirectory: home,
                inspectionIssues: [ScanIssue(url: home, message: "Choose a valid user home and approve the folders to inspect.")],
                readAccessRoots: [])
        }
        var issues: [ScanIssue] = []
        var folders: [URL] = []
        for supplied in approvedFolders.prefix(32) {
            let folder = supplied.roomLexicallyNormalized
            guard supplied.isFileURL, folder.path != "/", StoreFolderBoundary.isPhysicalOwnedDirectory(folder) else {
                issues.append(ScanIssue(url: folder, message: "The approved folder is unavailable, linked or not owned by this user. Approve its physical location again."))
                continue
            }
            if !folders.contains(where: { $0.path == folder.path }) { folders.append(folder) }
        }
        if approvedFolders.count > 32 {
            issues.append(ScanIssue(url: home, message: "This scan is limited to 32 approved folders. Other folders were not inspected."))
        }
        folders = folders.filter { candidate in
            !folders.contains { $0.path != candidate.path && StoreFolderBoundary.contains(candidate, in: $0) }
        }.sorted { $0.path < $1.path }

        let base = standard(home: home)
        var catalogue = base.roots
        func add(_ id: String, _ title: String, _ path: String, _ processes: [String],
                 category: String = "developer", scope: CacheScope = .children,
                 age: TimeInterval = 7 * 86_400) {
            catalogue.append(CacheRoot(id: id, title: title, subtitle: path,
                symbol: category == "agents" ? "terminal" : "shippingbox", category: category,
                url: home.appendingPathComponent(path),
                consequence: "Known rebuildable cache data may be downloaded or rebuilt by its owning tool. User work and installed resources remain protected.",
                minimumAge: age, guardedProcesses: processes, scope: scope))
        }
        add("claude-model-catalog", "Claude model catalog", ".claude/cache/model-catalog", ["claude", "node"], category: "agents")
        add("claude-shell-snapshots", "Claude environment snapshots", ".claude/shell-snapshots", ["claude", "node"], category: "agents", age: 30 * 86_400)
        add("npm-exec", "npm execution downloads", ".npm/_npx", ["node", "npm", "npx"])
        for folder in ["manifests", "package-metadata", "repositories", "artifacts"] {
            add("swiftpm-\(folder)", "Swift packages", "Library/Caches/org.swift.swiftpm/\(folder)", ["swift", "swift-build", "xcode", "xcodebuild", "sourcekit"])
        }
        add("swiftpm-prebuilts", "Swift prebuilt downloads", "Library/Caches/org.swift.swiftpm/prebuilts/swift-syntax", ["swift", "xcode", "xcodebuild", "sourcekit"])
        add("go-build", "Go build cache", "Library/Caches/go-build", ["go", "gopls"])
        add("go-downloads", "Go module downloads", "go/pkg/mod/cache/download", ["go", "gopls"])
        add("cargo", "Rust packages", ".cargo/registry/cache", ["cargo", "rustc", "rust-analyzer"])
        for folder in ["gen", "npm", "remote"] {
            add("deno-\(folder)", "Deno", "Library/Caches/deno/\(folder)", ["deno"])
        }
        for (app, processes) in [("Code", ["code", "code helper", "node"]), ("Cursor", ["cursor", "cursor helper", "node"])] {
            for child in ["Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "CachedData"] {
                let id = "store-" + app.lowercased() + "-" + child.lowercased().replacingOccurrences(of: " ", with: "-")
                add(id, "\(app) · \(child)", "Library/Application Support/\(app)/\(child)", processes, category: "apps")
            }
        }

        let protected = base.protectedLocations.filter { location in
            folders.contains { StoreFolderBoundary.contains(location.url, in: $0) }
        }
        var npmDiscovery: NPMDiscoveryCoverage? = nil
        #if ROOM_APP_STORE
        let npm = StoreNPMCatalogue.discover(approvedFolders: folders, userHome: home,
                                             continuation: npmContinuation)
        npmDiscovery = npm.coverage
        issues.append(contentsOf: npm.issues)
        // The mutable parent remains visible as inventory. Only independently
        // verified immutable leaves have the exception; no index/tmp bucket can move.
        catalogue = catalogue.map { root in
            guard root.id == "npm" else { return root }
            return CacheRoot(id: root.id, title: "npm cache inventory", subtitle: root.subtitle,
                symbol: root.symbol, category: root.category, url: root.url,
                consequence: "Mutable indexes, temporary content and unsupported objects stay inspect-only. Only separately verified old SHA512 download objects can be reviewed for Trash.",
                minimumAge: root.minimumAge, scope: root.scope,
                cleanupPolicy: .inspectOnly("Mutable npm index/tmp data is inspect-only. Review individual verified SHA512 objects instead."),
                excludedURLs: npm.roots.map(\.url), inspectionNodeLimit: root.inspectionNodeLimit,
                inspectionTimeLimit: root.inspectionTimeLimit)
        }
        catalogue.append(contentsOf: npm.roots)
        #endif
        let known = catalogue.filter { root in folders.contains { StoreFolderBoundary.contains(root.url, in: $0) } }
        var roots = known
        for folder in folders {
            // A selected known root has its own measurement; do not inventory it
            // a second time. Selecting a subfolder never promotes it to a cache.
            if known.contains(where: { $0.url.path == folder.path }) { continue }
            let excludes = (known.map(\.url) + protected.map(\.url)).filter {
                StoreFolderBoundary.contains($0, in: folder)
            }
            let reason = "This selected folder may contain user work, persistent app state or installed resources. It is inspect-only; names and locations do not establish that files are unnecessary."
            roots.append(CacheRoot(id: "store-selected-" + folder.path, title: folder.lastPathComponent,
                subtitle: folder.path, symbol: "folder", category: "apps", url: folder,
                consequence: reason, cleanupPolicy: .inspectOnly(reason), excludedURLs: excludes,
                inspectionNodeLimit: 25_000, inspectionTimeLimit: 2))
        }
        return CacheConfiguration(roots: roots, protectedLocations: protected,
            homeDirectory: home, inspectionIssues: issues, readAccessRoots: folders,
            npmDiscovery: npmDiscovery)
    }

    /// Reconstructs only exact known npm parents after the native recovery review
    /// has approved them. Recovery must not depend on which discovery page would
    /// currently contain a receipt's bucket. This does not discover children,
    /// accept an ancestor in place of a bucket, or preserve old cleanup IDs.
    /// CacheEngine still authenticates the persisted receipt, parents, contents,
    /// exact Trash item and destination immediately before returning anything.
    public static func storeRecovery(approvedParentFolders: [URL], userHome: URL) -> CacheConfiguration {
        let home = userHome.roomLexicallyNormalized
        guard userHome.isFileURL, home.path != "/" else {
            return CacheConfiguration(roots: [], homeDirectory: home,
                inspectionIssues: [ScanIssue(url: home, message: "Choose a valid user home before reviewing recovery access.")],
                readAccessRoots: [])
        }
        let base = home.appendingPathComponent(".npm/_cacache/content-v2/sha512", isDirectory: true)
        var issues: [ScanIssue] = []
        var roots: [String: CacheRoot] = [:]
        for supplied in approvedParentFolders {
            let folder = supplied.roomLexicallyNormalized
            guard supplied.isFileURL,
                  folder.deletingLastPathComponent().deletingLastPathComponent().path == base.path,
                  let prefixes = NPMContentPolicy.bucketPrefixes(folder),
                  StoreFolderBoundary.isPhysicalOwnedDirectory(folder, requireSafePermissions: true) else {
                issues.append(ScanIssue(url: folder, message: "Recovery needs the exact original physical npm SHA512 bucket. Broad folders, linked folders, unsafe permissions and other locations cannot replace this approval."))
                continue
            }
            // Do not collapse these parents beneath an existing broad read
            // bookmark or apply discovery's 32-folder / 256-bucket page limits.
            roots[folder.path] = CacheRoot(id: "store-npm-sha512-\(prefixes.0)-\(prefixes.1)",
                title: "npm downloads · \(prefixes.0)/\(prefixes.1)", subtitle: folder.path,
                symbol: "shippingbox", category: "developer", url: folder,
                consequence: NPMContentPolicy.consequence, minimumAge: NPMContentPolicy.minimumAge,
                inspectionNodeLimit: 4_096, inspectionTimeLimit: 8, contentValidation: .npmSHA512)
        }
        let exactRoots = roots.values.sorted { $0.url.path < $1.url.path }
        return CacheConfiguration(roots: exactRoots, homeDirectory: home,
            inspectionIssues: issues, readAccessRoots: exactRoots.map(\.url))
    }
}

private enum StoreFolderBoundary {
    static func contains(_ child: URL, in parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }

    static func isPhysicalOwnedDirectory(_ url: URL, requireSafePermissions: Bool = false) -> Bool {
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        for component in url.pathComponents where component != "/" {
            let next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return false }
            close(fd); fd = next
        }
        var info = stat()
        return fstat(fd, &info) == 0 && info.st_uid == getuid()
            && info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR)
            && (!requireSafePermissions || info.st_mode & 0o022 == 0)
    }
}
