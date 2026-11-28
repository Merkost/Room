import Darwin
import Foundation
import Synchronization

/// The languages and build tools a project folder is recognised by.
public enum DeveloperProjectKind: String, Codable, CaseIterable, Sendable {
    case node, rust, swiftPackage, xcode, gradle, flutter, python, go, ruby, php, dotnet, cmake, unity, maven, elixir

    public var title: String {
        switch self {
        case .node: "Node"
        case .rust: "Rust"
        case .swiftPackage: "Swift"
        case .xcode: "Xcode"
        case .gradle: "Gradle"
        case .flutter: "Flutter"
        case .python: "Python"
        case .go: "Go"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .dotnet: ".NET"
        case .cmake: "CMake"
        case .unity: "Unity"
        case .maven: "Maven"
        case .elixir: "Elixir"
        }
    }
}

/// One folder a project's tools build again by themselves: node_modules, target, .build, .venv and so on.
public struct DeveloperBuildFolder: Codable, Equatable, Sendable, Identifiable {
    public let url: URL
    /// Relative to the project: "node_modules", "app/build", "packages/web/.next".
    public let name: String
    public let kind: DeveloperProjectKind
    /// Space moving it frees: files linked from elsewhere (a pnpm store, say) are left out.
    public let bytes: Int64
    /// The walk stopped at its limit, so `bytes` is a lower bound.
    public let partial: Bool
    /// Some files are hard links shared with another place, so less space comes back than the folder holds.
    public let sharesFiles: Bool
    public var id: String { url.path }

    public init(url: URL, name: String, kind: DeveloperProjectKind, bytes: Int64, partial: Bool, sharesFiles: Bool) {
        self.url = url; self.name = name; self.kind = kind; self.bytes = bytes
        self.partial = partial; self.sharesFiles = sharesFiles
    }
}

/// A project folder (a repository, usually) and what its tools left behind in it.
public struct DeveloperFoundProject: Codable, Equatable, Sendable, Identifiable {
    public let url: URL
    public let kinds: [DeveloperProjectKind]
    public let buildFolders: [DeveloperBuildFolder]
    /// When anything in the project itself last changed: its files, its folders' lists, or its Git history.
    public let lastChanged: Date?
    /// The search read all of the project it meant to. When it stopped partway, `lastChanged` may be too old.
    public let fullyRead: Bool
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var buildBytes: Int64 { buildFolders.reduce(0) { $0 + $1.bytes } }
    public var partial: Bool { buildFolders.contains(where: \.partial) }

    public init(url: URL, kinds: [DeveloperProjectKind], buildFolders: [DeveloperBuildFolder], lastChanged: Date?,
                fullyRead: Bool = true) {
        self.url = url; self.kinds = kinds; self.buildFolders = buildFolders; self.lastChanged = lastChanged
        self.fullyRead = fullyRead
    }
}

public struct DeveloperProjectScan: Codable, Equatable, Sendable {
    public let projects: [DeveloperFoundProject]
    /// The search or the measuring stopped at a limit; some projects or sizes are missing.
    public let partial: Bool
    public let scannedAt: Date

    public init(projects: [DeveloperFoundProject], partial: Bool, scannedAt: Date = Date()) {
        self.projects = projects; self.partial = partial; self.scannedAt = scannedAt
    }

    public var buildBytes: Int64 { projects.reduce(0) { $0 + $1.buildBytes } }
}

/// Finds projects of every common kind in a home and measures the folders their tools rebuild. Reads names, sizes
/// and .gitignore files only, follows no links, and stops at its limits. The blocking work runs on its own queue, so
/// it never holds Swift's shared threads.
public enum DeveloperProjectScanner {
    public struct Limits: Sendable {
        public var maximumDepth = 6
        public var maximumDirectories = 20_000
        public var searchTime: TimeInterval = 15
        /// Levels Room still looks into below a project, for monorepos and nested apps.
        public var depthInsideProject = 3
        public var measureTime: TimeInterval = 60
        public var maximumEntriesPerFolder = 1_500_000
        public var maximumProjects = 600
        /// Folders measured at the same time.
        public var measuringAtOnce = 4
        /// Smaller folders are left out: they free nothing worth a review row.
        public var smallestFolder: Int64 = 1_000_000
        public init() {}
    }

    /// Folders never searched for projects: system areas, and the build output this scanner measures instead.
    static let skipped: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public",
                                       "node_modules", "build", "dist", "Pods", "vendor", "DerivedData", "target",
                                       "bin", "obj", "venv", "deps", "_build", "Temp", "Logs"]
    /// Inside a project, folders that hold its own source or assets: never build output and seldom another
    /// project, so the search spends its time on modules and packages instead.
    static let sourceFolders: Set<String> = ["src", "Sources", "Source", "Tests", "test", "tests", "__tests__", "spec",
                                             "docs", "doc", "assets", "Assets.xcassets", "res", "resources", "Resources",
                                             "public", "static", "fixtures", "include", "scripts", "migrations",
                                             "locales", "i18n", "images", "fonts", "icons"]
    private static let packages: Set<String> = ["app", "bundle", "framework", "photoslibrary", "musiclibrary",
                                                "tvlibrary", "xcarchive", "xcodeproj", "xcworkspace", "playground"]

    // MARK: What a project is

    static func kinds(names: Set<String>, folder: URL) -> [DeveloperProjectKind] {
        var found: [DeveloperProjectKind] = []
        func has(_ any: String...) -> Bool { any.contains { names.contains($0) } }
        func hasExtension(_ ext: String...) -> Bool { names.contains { ext.contains(($0 as NSString).pathExtension) } }
        if has("package.json") { found.append(.node) }
        if has("Cargo.toml") { found.append(.rust) }
        if has("Package.swift") { found.append(.swiftPackage) }
        if hasExtension("xcodeproj", "xcworkspace") { found.append(.xcode) }
        if has("settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts") { found.append(.gradle) }
        if has("pubspec.yaml") { found.append(.flutter) }
        if has("pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile", "poetry.lock", "uv.lock") {
            found.append(.python)
        }
        if has("go.mod") { found.append(.go) }
        if has("Gemfile") { found.append(.ruby) }
        if has("composer.json") { found.append(.php) }
        if hasExtension("csproj", "fsproj", "sln") { found.append(.dotnet) }
        if has("CMakeLists.txt") { found.append(.cmake) }
        if has("ProjectSettings"), has("Assets"),
           exists(folder.appendingPathComponent("ProjectSettings/ProjectVersion.txt")) { found.append(.unity) }
        if has("pom.xml") { found.append(.maven) }
        if has("mix.exs") { found.append(.elixir) }
        return found
    }

    /// A build folder rule: its name, the project kind it belongs to, and what must be inside it to prove it is
    /// that tool's output and not a folder someone happened to name the same.
    struct Rule: Sendable {
        let name: String
        let kind: DeveloperProjectKind
        /// Any one of these inside the folder proves it. Empty: the name and the project kind are proof enough.
        let proof: [String]
        /// Committed to Git in some projects: needs to be named in the project's .gitignore when it has a .git.
        let mustBeIgnored: Bool

        init(_ name: String, _ kind: DeveloperProjectKind, proof: [String] = [], mustBeIgnored: Bool = false) {
            self.name = name; self.kind = kind; self.proof = proof; self.mustBeIgnored = mustBeIgnored
        }
    }

    static let rules: [Rule] = [
        Rule("node_modules", .node),
        Rule(".next", .node, proof: ["BUILD_ID", "cache", "server", "build-manifest.json", "trace"]),
        Rule(".nuxt", .node, proof: ["nuxt.d.ts", "tsconfig.json", "components.d.ts", "app.config.mjs"]),
        Rule(".svelte-kit", .node, proof: ["generated", "output", "ambient.d.ts", "tsconfig.json"]),
        Rule(".turbo", .node, proof: ["cache", "cookies", "daemon"]),
        Rule(".parcel-cache", .node, proof: ["data.mdb", "lock.mdb"]),
        Rule(".angular", .node, proof: ["cache"]),
        Rule(".docusaurus", .node, proof: ["client-modules.js", "routes.js", "docusaurus.config.mjs"]),
        Rule("target", .rust, proof: ["CACHEDIR.TAG", ".rustc_info.json"]),
        Rule(".build", .swiftPackage, proof: ["workspace-state.json", "checkouts", "artifacts", "debug", "release",
                                              "arm64-apple-macosx", "x86_64-apple-macosx"]),
        Rule("build", .gradle, proof: ["tmp", "intermediates", "classes", "generated", "kotlin", "outputs", "reports"]),
        Rule(".gradle", .gradle, proof: ["buildOutputCleanup", "file-system.probe", "vcs-1", "configuration-cache"]),
        Rule(".kotlin", .gradle, proof: ["sessions", "errors", "metadata"]),
        Rule(".dart_tool", .flutter, proof: ["package_config.json", "flutter_build", "dartpad", "build"]),
        Rule("build", .flutter, proof: [".last_build_id", "flutter_assets", "native_assets", "app", "ios", "macos", "web"]),
        Rule(".venv", .python, proof: ["pyvenv.cfg"]),
        Rule("venv", .python, proof: ["pyvenv.cfg"]),
        Rule(".pytest_cache", .python, proof: ["CACHEDIR.TAG", "v"]),
        Rule(".mypy_cache", .python, proof: ["CACHEDIR.TAG"]),
        Rule(".ruff_cache", .python, proof: ["CACHEDIR.TAG"]),
        Rule(".tox", .python, proof: [".tox-info.json", ".tox"]),
        Rule(".nox", .python),
        Rule("vendor/bundle", .ruby, proof: ["ruby"], mustBeIgnored: true),
        Rule("vendor", .php, proof: ["autoload.php"], mustBeIgnored: true),
        Rule("obj", .dotnet, proof: ["project.assets.json", "Debug", "Release"]),
        Rule("bin", .dotnet, proof: ["Debug", "Release"]),
        Rule("build", .cmake, proof: ["CMakeCache.txt"]),
        Rule("Library", .unity, proof: ["ArtifactDB", "SourceAssetDB", "PackageCache", "Artifacts"]),
        Rule("Temp", .unity, proof: ["UnityLockfile", "ProcessJobs"]),
        Rule("target", .maven, proof: ["classes", "maven-status", "maven-archiver", "test-classes"]),
        Rule("_build", .elixir, proof: ["dev", "test", "prod"]),
        Rule("deps", .elixir, proof: [], mustBeIgnored: true),
        Rule("build", .xcode, proof: ["XCBuildData"]),
        Rule("Pods", .xcode, proof: ["Manifest.lock"], mustBeIgnored: true),
    ]

    /// CMake's out-of-tree builds from CLion: cmake-build-debug, cmake-build-release and so on.
    private static func cmakeBuild(_ name: String) -> Bool { name.hasPrefix("cmake-build-") }

    /// Whether `url` is, on disk now, a build folder of the project that holds it. Cleanup checks this again just
    /// before anything moves, so a rescan's word is never the only proof.
    public static func isBuildFolder(_ url: URL, project: URL) -> Bool {
        let project = project.roomLexicallyNormalized, url = url.roomLexicallyNormalized
        guard url.path.hasPrefix(project.path + "/") else { return false }
        let relative = String(url.path.dropFirst(project.path.count + 1))
        let parts = relative.split(separator: "/").map(String.init)
        // The folder itself, or one inside a module or workspace package (at most this many levels down).
        // No project is found at the home itself, so nothing directly in it is a build folder.
        guard project.path != FileManager.default.homeDirectoryForCurrentUser.roomLexicallyNormalized.path,
              !parts.contains(where: { $0 == "." || $0 == ".." }) else { return false }
        for split in 0..<min(parts.count, 4) {
            let owner = parts.prefix(split).reduce(project) { $0.appendingPathComponent($1, isDirectory: true) }
            let name = parts.dropFirst(split).joined(separator: "/")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: owner.path) else { return false }
            let set = Set(names)
            if match(name: name, in: owner, names: set, kinds: kinds(names: set, folder: owner), projectRoot: project) != nil {
                return true
            }
        }
        return false
    }

    private static let ruleNames = Set(rules.map(\.name))

    /// The rule a child of `folder` called `name` matches, or nil. `names` and `kinds` describe `folder`.
    static func match(name: String, in folder: URL, names: Set<String>, kinds: [DeveloperProjectKind],
                      projectRoot: URL) -> Rule? {
        guard !kinds.isEmpty, ruleNames.contains(name) || cmakeBuild(name) else { return nil }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        guard isPhysicalDirectory(url) else { return nil }
        if cmakeBuild(name) {
            return kinds.contains(.cmake) && exists(url.appendingPathComponent("CMakeCache.txt")) ? Rule(name, .cmake) : nil
        }
        for rule in rules where rule.name == name && kinds.contains(rule.kind) {
            guard rule.proof.isEmpty || rule.proof.contains(where: { exists(url.appendingPathComponent($0)) }) else { continue }
            if rule.mustBeIgnored, !ignoredByGit(name, project: projectRoot, folder: folder) { continue }
            if rule.kind == .elixir, rule.name == "deps", !names.contains("mix.lock") { continue }
            return rule
        }
        return nil
    }

    /// Whether Git ignores the folder, so it can't hold committed work. Room finds the repository it is in (a
    /// folder in no repository up to the home can't have been committed), then reads every .gitignore from the
    /// folder up to that repository's root, anchoring "/name" and "a/b" entries at their own .gitignore as Git does.
    static func ignoredByGit(_ name: String, project: URL, folder: URL) -> Bool {
        let folder = folder.roomLexicallyNormalized
        let target = folder.appendingPathComponent(name).roomLexicallyNormalized
        let home = FileManager.default.homeDirectoryForCurrentUser.roomLexicallyNormalized.path
        var candidate = folder
        var repository: URL?
        while true {
            if exists(candidate.appendingPathComponent(".git")) { repository = candidate; break }
            if candidate.path == "/" || candidate.path == home { break }
            candidate = candidate.deletingLastPathComponent()
        }
        guard let repository else { return true }
        var current = folder
        while current.path == repository.path || current.path.hasPrefix(repository.path + "/") {
            if gitignore(in: current, ignores: String(target.path.dropFirst(current.path.count + 1))) { return true }
            if current.path == repository.path { break }
            current = current.deletingLastPathComponent()
        }
        return false
    }

    /// Whether the .gitignore in `folder` ignores `relative` (a path below that folder). Only plain names, paths and
    /// "**/" prefixes are understood; any other pattern is not counted, so an unclear rule never proves anything.
    static func gitignore(in folder: URL, ignores relative: String) -> Bool {
        let file = folder.appendingPathComponent(".gitignore")
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.utf8.count < 262_144 else { return false }
        let parts = relative.split(separator: "/").map(String.init)
        var ignored = false
        for line in text.split(whereSeparator: \.isNewline) {
            var entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
            let negated = entry.hasPrefix("!")
            if negated { entry.removeFirst() }
            while entry.hasSuffix("/") { entry.removeLast() }
            var anywhere = false
            if entry.hasPrefix("**/") { entry.removeFirst(3); anywhere = true }
            guard !entry.isEmpty, !entry.contains(where: { "*?[\\".contains($0) }) else { continue }
            let matches: Bool
            if !entry.contains("/") {
                matches = parts.contains(entry)
            } else if anywhere {
                matches = relative == entry || relative.hasPrefix(entry + "/") || relative.contains("/" + entry + "/")
                    || relative.hasSuffix("/" + entry)
            } else {
                let anchored = entry.hasPrefix("/") ? String(entry.dropFirst()) : entry
                matches = relative == anchored || relative.hasPrefix(anchored + "/")
            }
            if matches { ignored = !negated }
        }
        return ignored
    }

    // MARK: The search

    struct Found: Sendable {
        let url: URL
        var kinds: [DeveloperProjectKind]
        var folders: [(url: URL, name: String, kind: DeveloperProjectKind)]
        var changed: time_t
        var fullyRead = true
    }

    /// Stop for work running outside Swift's task tree, where `Task.isCancelled` can't be seen.
    final class StopFlag: Sendable {
        private let flag = Atomic<Bool>(false)
        func stop() { flag.store(true, ordering: .relaxed) }
        var isStopped: Bool { flag.load(ordering: .relaxed) }
    }

    /// Runs blocking file-system work on a queue of its own; cancelling the calling task sets its stop.
    static func offPool<T: Sendable>(_ work: @escaping @Sendable (StopFlag) -> T) async -> T {
        let flag = StopFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work(flag)) }
            }
        } onCancel: { flag.stop() }
    }

    /// Searches `home` and measures what it finds, a few folders at a time. Stop reaches it through task
    /// cancellation. `progress` hears the project being measured.
    public static func scan(home: URL, excluding: Set<String> = [], limits: Limits = Limits(),
                            progress: (@Sendable (String) -> Void)? = nil) async -> DeveloperProjectScan {
        let (found, searchPartial) = await offPool { stop in search(home: home, excluding: excluding, limits: limits, stop: stop) }
        var partial = searchPartial
        // A folder inside another measured one (packages/web/node_modules inside node_modules) counts once.
        struct Job: Sendable { let project: Int; let url: URL; let name: String; let kind: DeveloperProjectKind; let title: String }
        var jobs: [Job] = []
        for (index, item) in found.enumerated() {
            let folders = item.folders.sorted { $0.name < $1.name }
            for folder in folders where !folders.contains(where: { folder.url.path.hasPrefix($0.url.path + "/") }) {
                jobs.append(Job(project: index, url: folder.url, name: folder.name, kind: folder.kind, title: item.url.lastPathComponent))
            }
        }
        // Stalest projects first, since they are the likeliest to be cleared.
        jobs.sort { found[$0.project].changed == found[$1.project].changed ? $0.url.path < $1.url.path
                    : found[$0.project].changed < found[$1.project].changed }
        let deadline = Date().addingTimeInterval(limits.measureTime)
        let maximum = limits.maximumEntriesPerFolder
        var measured: [Int: [DeveloperBuildFolder]] = [:]
        await withTaskGroup(of: (Job, Size?).self) { group in
            var next = 0
            func start() {
                guard next < jobs.count else { return }
                let job = jobs[next]
                next += 1
                group.addTask {
                    guard Date() < deadline, !Task.isCancelled else { return (job, nil) }
                    progress?(job.title)
                    return (job, await offPool { stop in measure(job.url, maximumEntries: maximum, deadline: deadline, stop: stop) })
                }
            }
            for _ in 0..<max(1, limits.measuringAtOnce) { start() }
            for await (job, size) in group {
                start()
                guard let size else { partial = true; continue }
                partial = partial || size.partial
                guard size.entries > 0, size.partial || size.bytes >= limits.smallestFolder else { continue }
                measured[job.project, default: []].append(DeveloperBuildFolder(url: job.url, name: job.name, kind: job.kind,
                    bytes: size.bytes, partial: size.partial, sharesFiles: size.shared))
            }
        }
        let projects = found.enumerated().map { index, item in
            DeveloperFoundProject(url: item.url, kinds: item.kinds,
                                  buildFolders: (measured[index] ?? []).sorted { $0.name < $1.name },
                                  lastChanged: item.changed > 0 ? Date(timeIntervalSince1970: TimeInterval(item.changed)) : nil,
                                  fullyRead: item.fullyRead)
        }
        return DeveloperProjectScan(projects: projects.sorted { $0.url.path < $1.url.path }, partial: partial)
    }

    /// The walk: project folders, their kinds, and the build folders in them, not yet measured.
    static func search(home: URL, excluding: Set<String>, limits: Limits, stop: StopFlag = StopFlag()) -> (found: [Found], partial: Bool) {
        let home = home.roomLexicallyNormalized
        let deadline = Date().addingTimeInterval(limits.searchTime)
        var partial = false
        var found: [Found] = []
        // (folder, depth from home, index of the project it is inside, levels below that project)
        var queue: [(url: URL, depth: Int, owner: Int?, inside: Int)] = [(home, 0, nil, 0)]
        var next = 0
        while next < queue.count {
            if next >= limits.maximumDirectories || Date() >= deadline || stop.isStopped { partial = true; break }
            let (folder, depth, owner, inside) = queue[next]
            next += 1
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            let set = Set(names)
            var current = owner
            var level = inside
            // Desktop, Documents, Downloads or a synced folder is never one project, even with a stray
            // package.json in it: Room could not move anything from it, and its projects are searched one by one.
            let kinds = depth > 0 && FolderTrashEngine.protection(for: folder, home: home) == nil
                ? kinds(names: set, folder: folder) : []
            if !kinds.isEmpty {
                // A nested folder with its own Git is its own project; otherwise it belongs to the one above.
                if let owner, !set.contains(".git") {
                    for kind in kinds where !found[owner].kinds.contains(kind) { found[owner].kinds.append(kind) }
                } else if found.count < limits.maximumProjects {
                    found.append(Found(url: folder, kinds: kinds, folders: [], changed: 0))
                    current = found.count - 1
                    level = 0
                } else { partial = true }
            }
            if let current {
                let root = found[current].url
                for name in names.sorted() {
                    guard let rule = match(name: name, in: folder, names: set, kinds: kinds, projectRoot: root) else { continue }
                    let url = folder.appendingPathComponent(name, isDirectory: true)
                    let relative = String(url.path.dropFirst(root.path.count + 1))
                    found[current].folders.append((url, relative, rule.kind))
                }
                if set.contains("vendor"),
                   let rule = match(name: "vendor/bundle", in: folder, names: set, kinds: kinds, projectRoot: root) {
                    let url = folder.appendingPathComponent("vendor/bundle", isDirectory: true)
                    found[current].folders.append((url, String(url.path.dropFirst(root.path.count + 1)), rule.kind))
                }
                found[current].changed = max(found[current].changed, lastChange(folder, names: names, isRoot: level == 0))
            }
            let limit = current == nil ? limits.maximumDepth : min(limits.maximumDepth, depth + limits.depthInsideProject - level)
            guard depth < limit else { continue }
            let measured = Set(current.map { found[$0].folders.map(\.url.path) } ?? [])
            for name in names.sorted() {
                guard !name.hasPrefix("."), !skipped.contains(name), !cmakeBuild(name),
                      current == nil || !sourceFolders.contains(name),
                      !packages.contains((name as NSString).pathExtension.lowercased()) else { continue }
                let url = folder.appendingPathComponent(name, isDirectory: true).roomLexicallyNormalized
                guard !measured.contains(url.path), !excluding.contains(url.path), isPhysicalDirectory(url) else { continue }
                queue.append((url, depth + 1, current, current == nil ? 0 : level + 1))
            }
        }
        if found.count >= limits.maximumProjects { partial = true }
        // A project with folders still waiting may have changed somewhere Room did not get to.
        for item in queue[next...] { if let owner = item.owner { found[owner].fullyRead = false } }
        return (found, partial)
    }

    /// The newest change Room can see cheaply: the folder's own list, its files (not the build folders), and at the
    /// project's root, Git's record of the last commit, checkout or staging.
    static func lastChange(_ folder: URL, names: [String], isRoot: Bool) -> time_t {
        var newest: time_t = 0
        func look(_ path: String) {
            var info = stat()
            if lstat(path, &info) == 0 { newest = max(newest, info.st_mtimespec.tv_sec) }
        }
        look(folder.path)
        let buildNames = Set(rules.map(\.name))
        for name in names.prefix(400) where !buildNames.contains(name) && !cmakeBuild(name) && name != ".DS_Store" {
            look(folder.appendingPathComponent(name).path)
        }
        if isRoot {
            for git in [".git/HEAD", ".git/index", ".git/logs/HEAD", ".git/FETCH_HEAD"] {
                look(folder.appendingPathComponent(git).path)
            }
        }
        return newest
    }

    // MARK: Measuring

    struct Size: Equatable, Sendable { var bytes: Int64 = 0; var entries = 0; var partial = false; var shared = false }

    /// Space moving `url` frees: allocated bytes of every regular file below it, without following links or leaving
    /// its volume. Files with more than one link count once, and only when every link is inside. A copy-on-write
    /// clone (pnpm, Bun and uv make these from their stores) counts only the blocks it doesn't share.
    static func measure(_ url: URL, maximumEntries: Int, deadline: Date, stop: StopFlag = StopFlag()) -> Size {
        bulkMeasure(url, maximumEntries: maximumEntries, deadline: deadline, stop: stop)
            ?? walkMeasure(url, maximumEntries: maximumEntries, deadline: deadline, stop: stop)
    }

    /// One `getattrlistbulk` call reads a whole batch of a folder's entries: kind, file id, links, allocated size
    /// and the bytes no clone shares. nil when the volume does not support it, so the slower walk runs instead.
    static func bulkMeasure(_ url: URL, maximumEntries: Int, deadline: Date, stop: StopFlag) -> Size? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        func bits(_ values: [Int64]) -> attrgroup_t { values.reduce(0) { $0 | attrgroup_t(truncatingIfNeeded: $1) } }
        request.commonattr = bits([Int64(ATTR_CMN_RETURNED_ATTRS), Int64(ATTR_CMN_NAME), Int64(ATTR_CMN_DEVID),
                                   Int64(ATTR_CMN_OBJTYPE), Int64(ATTR_CMN_FILEID)])
        request.fileattr = bits([Int64(ATTR_FILE_LINKCOUNT), Int64(ATTR_FILE_ALLOCSIZE)])
        request.forkattr = attrgroup_t(truncatingIfNeeded: ATTR_CMNEXT_PRIVATESIZE)
        let options = UInt64(truncatingIfNeeded: Int64(FSOPT_PACK_INVAL_ATTRS) | Int64(FSOPT_ATTR_CMN_EXTENDED))
        let privateBit = UInt32(truncatingIfNeeded: ATTR_CMNEXT_PRIVATESIZE)
        var root = stat()
        guard lstat(url.path, &root) == 0, root.st_mode & S_IFMT == S_IFDIR else { return nil }
        var size = Size()
        var links: [UInt64: (count: Int, total: Int, bytes: Int64)] = [:]
        var pending = [url.path]
        let capacity = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }
        var first = true
        walk: while let folder = pending.popLast() {
            if Date() >= deadline || stop.isStopped { size.partial = true; break }
            let descriptor = open(folder, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { size.partial = true; continue }
            defer { close(descriptor) }
            while true {
                let count = getattrlistbulk(descriptor, &request, buffer, capacity, options)
                if count < 0 {
                    // Unsupported on this volume: say so before anything is counted, so the walk takes over.
                    if first, errno == ENOTSUP || errno == EINVAL { return nil }
                    size.partial = true
                    break
                }
                first = false
                if count == 0 { break }
                var entry = buffer
                for _ in 0..<count {
                    let length = Int(entry.loadUnaligned(as: UInt32.self))
                    defer { entry = entry.advanced(by: length) }
                    size.entries += 1
                    if size.entries > maximumEntries { size.partial = true; break walk }
                    // length (4), returned set (20: common, volume, directory, file, fork), then the values in order.
                    let returnedFork = entry.loadUnaligned(fromByteOffset: 20, as: UInt32.self)
                    let nameOffset = Int(entry.loadUnaligned(fromByteOffset: 24, as: Int32.self))
                    let device = entry.loadUnaligned(fromByteOffset: 32, as: Int32.self)
                    let kind = entry.loadUnaligned(fromByteOffset: 36, as: UInt32.self)
                    let fileID = entry.loadUnaligned(fromByteOffset: 40, as: UInt64.self)
                    let linkCount = entry.loadUnaligned(fromByteOffset: 48, as: UInt32.self)
                    let allocated = max(0, entry.loadUnaligned(fromByteOffset: 52, as: Int64.self))
                    let unshared = entry.loadUnaligned(fromByteOffset: 60, as: Int64.self)
                    guard device == root.st_dev else { continue }   // another volume mounted inside
                    switch kind {
                    case 2: // a folder
                        let name = String(cString: entry.advanced(by: 24 + nameOffset).assumingMemoryBound(to: CChar.self))
                        pending.append(folder + "/" + name)
                    case 1: // a regular file
                        let bytes = returnedFork & privateBit != 0 ? min(allocated, max(0, unshared)) : allocated
                        if linkCount > 1 {
                            var seen = links[fileID] ?? (0, Int(linkCount), bytes)
                            seen.count += 1
                            links[fileID] = seen
                        } else {
                            size.bytes += bytes
                        }
                    default:
                        break   // links and special items are neither followed nor counted
                    }
                }
            }
        }
        for link in links.values {
            if link.count >= link.total { size.bytes += link.bytes } else { size.shared = true }
        }
        return size
    }

    /// The portable walk: fts plus one attribute read per file for its unshared bytes.
    static func walkMeasure(_ url: URL, maximumEntries: Int, deadline: Date, stop: StopFlag) -> Size {
        var size = Size()
        guard let path = strdup(url.path) else { size.partial = true; return size }
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { size.partial = true; return size }
        defer { fts_close(fts) }
        var links: [UInt64: (count: Int, total: Int, bytes: Int64)] = [:]
        while let entry = fts_read(fts) {
            size.entries += 1
            if size.entries > maximumEntries { size.partial = true; break }
            if size.entries & 2047 == 0, Date() >= deadline || stop.isStopped { size.partial = true; break }
            switch Int32(entry.pointee.fts_info) {
            case FTS_F:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                var bytes = max(0, Int64(stat.st_blocks)) * 512
                if bytes > 0, let path = entry.pointee.fts_path, let unshared = privateSize(path) { bytes = min(bytes, unshared) }
                if stat.st_nlink > 1 {
                    let key = UInt64(stat.st_ino)
                    var seen = links[key] ?? (0, Int(stat.st_nlink), bytes)
                    seen.count += 1
                    links[key] = seen
                } else {
                    size.bytes += bytes
                }
            case FTS_DNR, FTS_ERR, FTS_NS:
                size.partial = true
            default:
                break
            }
        }
        for link in links.values {
            if link.count >= link.total { size.bytes += link.bytes } else { size.shared = true }
        }
        return size
    }

    /// The bytes of a file no clone shares, from APFS. nil where the volume does not say.
    static func privateSize(_ path: UnsafePointer<CChar>) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(truncatingIfNeeded: ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let options = UInt32(truncatingIfNeeded: FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)
        guard getattrlist(path, &request, &buffer, buffer.count, options) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> Int64? in
            // length (4), then the returned set: common, volume, directory, file, fork (4 each), then the value.
            let returnedFork = raw.loadUnaligned(fromByteOffset: 4 + 16, as: UInt32.self)
            guard returnedFork & UInt32(truncatingIfNeeded: ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return max(0, raw.loadUnaligned(fromByteOffset: 24, as: Int64.self))
        }
    }

    // MARK: Files

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func isPhysicalDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == getuid()
    }
}
