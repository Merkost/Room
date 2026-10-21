import Darwin
import Foundation

extension CacheConfiguration {
    /// Known rebuildable caches plus bounded, read-only inventory of other cache,
    /// log and current-user temporary locations. Never treats a name as permission to delete.
    public static var full: CacheConfiguration {
        addingDiscoveredSources(to: addingAdditionalSources(to: .deep, maximumSandboxRoots: 0), temporaryDirectory: FileManager.default.temporaryDirectory, userCacheDirectory: currentUserCacheDirectory())
    }

    static func addingDiscoveredSources(to base: CacheConfiguration, temporaryDirectory: URL,
                                       userCacheDirectory: URL? = nil, inspectionNodeLimit: Int = 100_000,
                                       inspectionTimeLimit: TimeInterval = 10) -> CacheConfiguration {
        let home = base.homeDirectory
        var inspectionIssues = base.inspectionIssues
        var deferredContainerDirectory = false
        func automaticDirectory(_ url: URL) -> URL? {
            guard !automaticContainerApprovalRequired(for: url, home: home) else {
                deferredContainerDirectory = true
                return nil
            }
            let physical = physicalSystemDirectory(url) ?? url.roomLexicallyNormalized
            guard !automaticContainerApprovalRequired(for: physical, home: home) else {
                deferredContainerDirectory = true
                return nil
            }
            return physical
        }
        var roots = base.roots.map { root in
            CacheRoot(id: root.id, title: root.title, subtitle: root.subtitle, symbol: root.symbol,
                category: root.category, url: root.url, consequence: root.consequence,
                minimumAge: root.minimumAge, guardedProcesses: root.guardedProcesses, scope: root.scope,
                cleanupPolicy: root.cleanupPolicy,
                candidateDepth: root.id == "gradle" ? 3 : (root.id == "npm" ? 5 : root.candidateDepth),
                excludedURLs: root.excludedURLs, childNameRule: root.childNameRule, excludedChildNameRules: root.excludedChildNameRules, inspectionNodeLimit: root.inspectionNodeLimit,
                inspectionTimeLimit: root.inspectionTimeLimit, contentValidation: root.contentValidation)
        }
        let temporary = automaticDirectory(temporaryDirectory)
        let generated = temporary.map { generatedKarmaFolders(in: $0) } ?? []
        if let temporary {
            roots.append(CacheRoot(id: "temporary-karma", title: "Karma build output", subtitle: temporary.path,
                symbol: "curlybraces", category: "developer", url: temporary,
                consequence: "Generated webpack test bundles are rebuilt on the next test run. Only exact generated folder names older than 7 days are considered.",
                guardedProcesses: ["node", "npm", "npx", "karma", "webpack"], childNameRule: .karmaWebpack))
        }
        let boundaries = roots.flatMap { root in
            root.childNameRule != nil ? generated.map { root.url.appendingPathComponent($0, isDirectory: false) } : [root.url]
        } + base.protectedLocations.map(\.url)
        var locations: [(String, String, URL, String, String)] = [
            ("discovered-app-caches", "Other app caches", home.appendingPathComponent("Library/Caches", isDirectory: true), "apps", "App cache locations can contain installed tools or recovery data. Inspect these items in Disk Map; they are never selected for cleanup."),
            ("discovered-hidden-caches", "Other developer caches", home.appendingPathComponent(".cache", isDirectory: true), "developer", "Hidden cache folders can contain models, installed runtimes and credentials. Inspect only; no automatic cleanup.")
        ]
        if let temporary {
            locations.append(("discovered-temporary", "Temporary files", temporary, "apps", "Temporary files may belong to running apps or unfinished work. Inspect only; Room never moves unknown temporary items."))
        }
        locations.append(("discovered-logs", "Other app logs", home.appendingPathComponent("Library/Logs", isDirectory: true), "apps", "Logs may be needed for troubleshooting or auditing. Inspect only; only separately listed known diagnostics can be cleaned."))
        if let userCacheDirectory, let physicalCache = automaticDirectory(userCacheDirectory) {
            locations.append(("discovered-user-cache", "macOS user caches", physicalCache, "apps",
                "Per-user system caches can include live app state. Inspect only; manage these through macOS or the owning app."))
        }
        var seen = Set(roots.filter { $0.childNameRule == nil }.map { $0.url.path })
        let discovered = locations.compactMap { id, title, url, category, reason -> CacheRoot? in
            guard !automaticContainerApprovalRequired(for: url, home: home) else {
                deferredContainerDirectory = true
                return nil
            }
            guard seen.insert(url.path).inserted else { return nil }
            let exclusions = boundaries.filter { $0.path == url.path || $0.path.hasPrefix(url.path + "/") }
            return CacheRoot(id: id, title: title, subtitle: url.path, symbol: id == "discovered-temporary" ? "clock" : "folder",
                category: category, url: url, consequence: reason,
                cleanupPolicy: .inspectOnly(reason), excludedURLs: exclusions,
                excludedChildNameRules: id == "discovered-temporary" ? [.karmaWebpack] : [],
                inspectionNodeLimit: inspectionNodeLimit, inspectionTimeLimit: inspectionTimeLimit)
        }
        if deferredContainerDirectory && !inspectionIssues.contains(where: { $0 == containerFolderApprovalIssue(home: home) }) {
            inspectionIssues.append(containerFolderApprovalIssue(home: home))
        }
        return CacheConfiguration(roots: roots + discovered, protectedLocations: base.protectedLocations, homeDirectory: home,
            inspectionIssues: inspectionIssues, readAccessRoots: base.readAccessRoots,
            protectedMeasurementExclusions: base.protectedMeasurementExclusions)
    }
    /// Only OS-supplied discovery parents use POSIX canonicalization. Foundation
    /// may shorten /private/var back to the /var symlink after resolving it.
    /// Discovered children are never resolved and still use no-follow traversal.
    private static func physicalSystemDirectory(_ url: URL) -> URL? {
        guard url.isFileURL, let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer), isDirectory: true).roomLexicallyNormalized
    }

    private static func currentUserCacheDirectory() -> URL? {
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard length > 1, length < 16_384 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
    }

    private static func generatedKarmaFolders(in url: URL) -> [String] {
        let components = url.pathComponents.filter { $0 != "/" }
        var descriptor = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return [] }
        for (index, component) in components.enumerated() {
            let next = openat(descriptor, component,
                (index == components.count - 1 ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { return [] }
            descriptor = next
        }
        defer { close(descriptor) }
        var root = stat()
        guard fstat(descriptor, &root) == 0, root.st_uid == getuid() else { return [] }
        let copied = dup(descriptor)
        guard copied >= 0 else { return [] }
        guard let directory = fdopendir(copied) else { close(copied); return [] }
        defer { closedir(directory) }
        var names: [String] = []
        var inspected = 0
        while inspected < 10_000, let entry = readdir(directory) {
            inspected += 1
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard CacheChildNameRule.karmaWebpack.matches(name) else { continue }
            var item = stat()
            guard fstatat(descriptor, name, &item, AT_SYMLINK_NOFOLLOW) == 0,
                  item.st_uid == getuid(), item.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { continue }
            names.append(name)
        }
        return names.sorted()
    }

}
