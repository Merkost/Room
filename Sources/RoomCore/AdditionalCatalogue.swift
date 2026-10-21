import Darwin
import Foundation

extension CacheConfiguration {
    /// Additional exact cache families and managed storage. Managed resources are
    /// measured only; a cache-like name never grants cleanup permission.
    static func addingAdditionalSources(to base: CacheConfiguration,
                                        environment: [String: String] = ProcessInfo.processInfo.environment,
                                        maximumSandboxRoots: Int = 0,
                                        sandboxParentLimit: Int = 1_536,
                                        sandboxDiscoveryTimeLimit: TimeInterval = 2,
                                        metadataDirectoryOpener: ((URL) -> Int32)? = nil) -> CacheConfiguration {
        let home = base.homeDirectory
        let sandboxLimit = max(0, min(32, maximumSandboxRoots))
        let openDirectory = metadataDirectoryOpener ?? CatalogueMetadata.openDirectory
        func location(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: false).roomLexicallyNormalized }
        func intersects(_ a: URL, _ b: URL) -> Bool {
            a.path == b.path || a.path.hasPrefix(b.path + "/") || b.path.hasPrefix(a.path + "/")
        }
        func requiresContainerApproval(_ url: URL) -> Bool {
            automaticContainerApprovalRequired(for: url, home: home)
        }
        func automaticPathAllowed(_ url: URL) -> Bool {
            !requiresContainerApproval(url) && CatalogueMetadata.hasPhysicalExistingAncestors(url)
        }
        let deferredProtected = sandboxLimit == 0 ? base.protectedLocations.filter { !automaticPathAllowed($0.url) } : []
        func retainedRoot(_ root: CacheRoot) -> CacheRoot {
            guard case .allowed = root.cleanupPolicy,
                  let protection = deferredProtected.first(where: { intersects($0.url, root.url) }) else { return root }
            // A broad protected ancestor cannot be measured without entering a
            // container. Omit that measurement, but never relax its cleanup hold.
            return CacheRoot(id: root.id, title: root.title, subtitle: root.subtitle, symbol: root.symbol,
                category: root.category, url: root.url, consequence: protection.reason,
                minimumAge: root.minimumAge, guardedProcesses: root.guardedProcesses, scope: root.scope,
                cleanupPolicy: .inspectOnly(protection.reason), candidateDepth: root.candidateDepth,
                excludedURLs: root.excludedURLs, childNameRule: root.childNameRule,
                excludedChildNameRules: root.excludedChildNameRules, inspectionNodeLimit: root.inspectionNodeLimit,
                inspectionTimeLimit: root.inspectionTimeLimit, contentValidation: root.contentValidation)
        }
        var roots = base.roots.filter { sandboxLimit > 0 || automaticPathAllowed($0.url) }.map(retainedRoot)
        var protected = base.protectedLocations
        let measurementExclusions = base.protectedMeasurementExclusions + deferredProtected.map(\.url).filter {
            !base.protectedMeasurementExclusions.contains($0)
        }
        var inspectionIssues = base.inspectionIssues
        func configuration() -> CacheConfiguration {
            CacheConfiguration(roots: roots, protectedLocations: protected, homeDirectory: home,
                inspectionIssues: inspectionIssues, readAccessRoots: base.readAccessRoots,
                protectedMeasurementExclusions: measurementExclusions)
        }
        @discardableResult
        func add(_ id: String, _ title: String, _ path: String, _ reason: String,
                 processes: [String] = [], inspect: Bool = true, category: String = "developer",
                 scope: CacheScope = .children, existingOnly: Bool = true,
                 nodes: Int = 25_000, seconds: TimeInterval = 2) -> Bool {
            let url = location(path)
            guard sandboxLimit > 0 || automaticPathAllowed(url) else { return false }
            if existingOnly && !CatalogueMetadata.isPhysicalItem(url, directory: scope == .children, opener: openDirectory) { return false }
            guard !roots.contains(where: { $0.id == id || intersects($0.url, url) }),
                  !protected.contains(where: { $0.url.path != url.path && intersects($0.url, url) }) else { return false }
            roots.append(retainedRoot(CacheRoot(id: id, title: title, subtitle: path,
                symbol: inspect ? "externaldrive" : "shippingbox", category: category,
                url: url, consequence: reason, guardedProcesses: processes, scope: scope,
                cleanupPolicy: inspect ? .inspectOnly(reason) : .allowed,
                inspectionNodeLimit: nodes, inspectionTimeLimit: seconds)))
            // An exact managed-store measurement replaces the old informational
            // measurement, while keeping that location unconditionally inspect-only.
            if inspect { protected.removeAll { $0.url.path == url.path } }
            return true
        }
        let swift = ["swift", "swift-build", "xcode", "xcodebuild", "sourcekit"]
        add("swiftpm-prebuilts", "Swift prebuilt downloads", "Library/Caches/org.swift.swiftpm/prebuilts/swift-syntax",
            "Downloaded swift-syntax archives and manifests can be fetched again. The sibling noprebuilts preference and project checkouts stay in place.",
            processes: swift, inspect: false, existingOnly: false)
        for (id, path) in [("cargo-index", ".cargo/registry/index"), ("cargo-git-db", ".cargo/git/db")] {
            add(id, "Rust package metadata", path,
                "Cargo rebuilds registry metadata or fetches repository mirrors again. Offline builds may need the network; installed binaries, credentials and source checkouts stay in place.",
                processes: ["cargo", "rustc", "rust-analyzer", "git"], inspect: false, existingOnly: false)
        }
        // Electron's HTTP cache is separate from storage data. Never include
        // IndexedDB, Local Storage, Service Worker, profiles, sessions or plugins.
        let apps: [(String, String, String, [String], String)] = [
            ("codex", "Codex", "Codex", ["codex", "chatgpt"], "agents"),
            ("claude", "Claude", "Claude", ["claude", "node"], "agents"),
            ("vscode", "VS Code", "Code", ["code", "code helper"], "developer"),
            ("cursor", "Cursor", "Cursor", ["cursor", "node"], "agents"),
            ("antigravity", "Antigravity", "Antigravity", ["antigravity", "node"], "agents"),
            ("slack", "Slack", "Slack", ["slack"], "apps"),
            ("discord", "Discord", "discord", ["discord"], "apps"),
            ("notion", "Notion", "Notion", ["notion"], "apps"),
            ("figma", "Figma", "Figma", ["figma"], "apps"),
            ("obsidian", "Obsidian", "obsidian", ["obsidian"], "apps"),
            ("postman", "Postman", "Postman", ["postman"], "developer"),
            ("insomnia", "Insomnia", "Insomnia", ["insomnia"], "developer"),
            ("lmstudio-render", "LM Studio interface", "LM Studio", ["lm studio", "lmstudio"], "apps")
        ]
        let renderFolders = ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GPUPersistentCache", "GraphiteDawnCache"]
        for (id, title, support, processes, category) in apps {
            let parent = "Library/Application Support/" + support
            guard sandboxLimit > 0 || !requiresContainerApproval(location(parent)),
                  CatalogueMetadata.isPhysicalItem(location(parent), directory: true, opener: openDirectory) else { continue }
            for folder in renderFolders {
                let suffix = folder.lowercased().replacingOccurrences(of: " ", with: "-")
                add("\(id)-http-render-\(suffix)", title, parent + "/" + folder,
                    "HTTP downloads and compiled graphics data rebuild. Conversations, documents, credentials, extensions and persistent app storage are excluded.",
                    processes: processes, inspect: false, category: category, existingOnly: false)
            }
        }
        let managed: [(String, String, String, String, String)] = [
            ("pnpm-store", "pnpm package store", "Library/pnpm/store", "developer", "Packages can be linked into projects. Use pnpm store prune to remove unreferenced packages; Room only measures this store."),
            ("pnpm-store-legacy", "pnpm package store", ".pnpm-store", "developer", "Packages can be linked into projects. Manage this store with pnpm; Room never moves its files."),
            ("bun-store", "Bun package store", ".bun/install/cache", "developer", "Bun links may be referenced by projects using its global store. Manage these packages through Bun; inspect only."),
            ("uv-managed", "uv managed cache", ".cache/uv", "developer", "uv requires its own cache clean or cache prune commands for consistency. Room never modifies this store."),
            ("maven-repository", "Maven local repository", ".m2/repository", "developer", "May contain locally published artifacts unavailable elsewhere. Inspect only; manage artifacts through Maven or their projects."),
            ("nuget-packages", "NuGet packages", ".nuget/packages", "developer", "Packages include installed build and runtime references. Inspect only; manage them through NuGet."),
            ("ivy-cache", "Ivy package store", ".ivy2/cache", "developer", "Dependency artifacts may be referenced by builds or available only locally. Inspect only; manage them through Ivy."),
            ("cargo-sources", "Rust package sources", ".cargo/registry/src", "developer", "Unpacked dependency source can contain local edits. Inspect only; Cargo manages this source tree."),
            ("cargo-checkouts", "Rust Git checkouts", ".cargo/git/checkouts", "developer", "Dependency checkouts can contain local edits. Inspect only; Cargo manages these working trees."),
            ("gradle-distributions", "Gradle distributions", ".gradle/wrapper/dists", "developer", "Installed Gradle versions are used by projects and offline builds. Inspect only; manage them through Gradle."),
            ("konan-toolchains", "Kotlin Native toolchains", ".konan/dependencies", "developer", "Installed compilers and native dependencies are required by builds. Inspect only."),
            ("android-sdk", "Android SDK", "Library/Android/sdk", "developer", "Installed platforms, compilers and system images are required by projects. Use SDK Manager to manage them; inspect only."),
            ("android-devices", "Android virtual devices", ".android/avd", "developer", "Virtual devices contain installed apps and user data. Use Device Manager; inspect only."),
            ("apple-simulators", "Apple simulators", "Library/Developer/CoreSimulator/Devices", "developer", "Simulator devices contain apps and user data. Manage devices through Xcode; inspect only."),
            ("playwright-runtime", "Playwright browsers", "Library/Caches/ms-playwright", "developer", "Installed browsers are used by tests and agent tools. Manage installations through Playwright; inspect only."),
            ("puppeteer-runtime", "Puppeteer browsers", ".cache/puppeteer", "developer", "Installed browsers are used by tests and agent tools. Manage installations through Puppeteer; inspect only."),
            ("firebase-emulators", "Firebase emulators", ".cache/firebase/emulators", "developer", "Installed emulator binaries are tools, not disposable downloads. Manage them through Firebase; inspect only."),
            ("claude-installations", "Claude installations", ".local/share/claude/versions", "agents", "Installed agent executables are required by tools. Manage versions through Claude; inspect only."),
            ("claude-staging", "Claude runtime staging", ".cache/claude", "agents", "Runtime installation and staging data may be active or installed tooling. Inspect only."),
            ("codex-runtimes", "Codex runtimes", ".cache/codex-runtimes", "agents", "Installed runtimes used by agent tools. Inspect only; these are not disposable downloads."),
            ("codex-runtime-packages", "Codex runtime packages", ".codex/packages", "agents", "Installed standalone tools and app-server packages. Inspect only."),
            ("lmstudio-models-legacy", "Local model files", ".cache/lm-studio/models", "agents", "Model files may be imported originals and can be expensive to replace. Manage them through their model app; inspect only."),
            ("lmstudio-models", "Local model files", ".lmstudio/models", "agents", "Model files may be imported originals. Inspect only; Room never removes model weights."),
            ("ollama-models", "Ollama models", ".ollama/models", "agents", "Installed local models are retained. Manage model versions through Ollama; inspect only."),
            ("huggingface-models", "Hugging Face models", ".cache/huggingface", "agents", "Model snapshots and shared blobs can be referenced by local tools. Manage them through Hugging Face; inspect only."),
            ("copilot-indexes", "Copilot project indexes", ".cache/github-copilot", "agents", "Project indexes and context can be valuable active agent state. Inspect only.")
        ]
        for (id, title, path, category, reason) in managed { add(id, title, path, reason, category: category) }
        if sandboxLimit > 0 {
            for (id, path) in [("docker-disk", "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
                               ("docker-disk-legacy", "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.qcow2")] {
                add(id, "Docker disk image", path,
                    "This disk image contains containers, images and persistent volumes. Room measures allocated disk space only. Manage storage through Docker; never move this file directly.", scope: .singleFile)
            }
        }
        // Only documented cache/model location overrides, strictly inside the
        // physical home. Overrides remain inspect-only even for known tools.
        for (variable, id, title) in [
            ("UV_CACHE_DIR", "uv", "uv cache"), ("BUN_INSTALL_CACHE_DIR", "bun", "Bun store"),
            ("NPM_CONFIG_CACHE", "npm", "npm cache"), ("PIP_CACHE_DIR", "pip", "pip cache"),
            ("HOMEBREW_CACHE", "homebrew", "Homebrew cache"), ("GOCACHE", "go", "Go cache"),
            ("PLAYWRIGHT_BROWSERS_PATH", "playwright", "Playwright browsers"),
            ("PUPPETEER_CACHE_DIR", "puppeteer", "Puppeteer browsers"),
            ("HF_HOME", "huggingface", "Hugging Face store"), ("OLLAMA_MODELS", "ollama", "Ollama models")
        ] {
            guard let value = environment[variable], value.hasPrefix("/"), !value.contains("\0"),
                  !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  value.hasPrefix(home.path + "/") else { continue }
            let relative = String(value.dropFirst(home.path.count + 1))
            add("custom-\(id)", title, relative,
                "Custom \(variable) location. It may contain installed or referenced resources. Inspect only; manage it through the owning tool.")
        }
        guard sandboxLimit > 0 else {
            inspectionIssues.append(containerFolderApprovalIssue(home: home))
            return configuration()
        }
        let deadline = Date().addingTimeInterval(max(0, sandboxDiscoveryTimeLimit))
        var sandboxCount = 0
        var sandboxPartial = false
        outer: for (parent, suffixes) in [
            ("Library/Containers", ["Data/Library/Caches"]),
            ("Library/Group Containers", ["Library/Caches", "Data/Library/Caches"])
        ] {
            let inventory = CatalogueMetadata.directoryNames(location(parent), limit: max(0, sandboxParentLimit), opener: openDirectory)
            sandboxPartial = sandboxPartial || inventory.partial
            let names = inventory.names.sorted { left, right in
                    let leftApple = left.contains("com.apple."), rightApple = right.contains("com.apple.")
                    return leftApple == rightApple ? left < right : !leftApple
                }
            for name in names {
                if Task.isCancelled || Date() >= deadline || sandboxCount >= sandboxLimit { sandboxPartial = true; break outer }
                for suffix in suffixes {
                    if Task.isCancelled || Date() >= deadline || sandboxCount >= sandboxLimit { sandboxPartial = true; break outer }
                    let path = parent + "/" + name + "/" + suffix
                    let inspected = CatalogueMetadata.isNonemptyPhysicalDirectory(location(path), opener: openDirectory)
                    sandboxPartial = sandboxPartial || inspected.denied
                    guard inspected.nonempty else { continue }
                    let note = "App sandbox cache; inspect only because the owning app determines what is safe. Discovery checks at most \(max(0, sandboxParentLimit)) names per container parent, \(sandboxLimit) nonempty cache folders and a \(max(0, sandboxDiscoveryTimeLimit))-second aggregate discovery window. Each folder measurement is limited to 4,000 entries or 0.5 seconds; other sandbox contents are excluded."
                    if add("sandbox-cache-" + CatalogueMetadata.stableID(path), name + " cache", path, note,
                           category: "apps", nodes: 4_000, seconds: 0.5) { sandboxCount += 1 }
                }
            }
        }
        if sandboxPartial {
            inspectionIssues.append(ScanIssue(url: location("Library/Containers"), message:
                "Sandbox cache discovery was limited by permissions, its time window, parent-name limit or folder cap. Only discovered cache folders were measured; other container contents remain excluded."))
        }
        return configuration()
    }

    /// Lexical only: checking whether approval is needed must never itself open
    /// a protected app container. Broad ancestors are deferred as well because
    /// their recursive measurement would otherwise enter that container.
    static func automaticContainerApprovalRequired(for url: URL, home: URL) -> Bool {
        let path = url.roomLexicallyNormalized.path.lowercased()
        let components = path.split(separator: "/")
        if zip(components, components.dropFirst()).contains(where: {
            $0.0 == "library" && ($0.1 == "containers" || $0.1 == "group containers")
        }) { return true }
        return ["Library/Containers", "Library/Group Containers"].contains { relative in
            let boundary = home.appendingPathComponent(relative, isDirectory: true).roomLexicallyNormalized.path.lowercased()
            return path == boundary || path.hasPrefix(boundary + "/") ||
                boundary.hasPrefix(path == "/" ? "/" : path + "/")
        }
    }

    static func containerFolderApprovalIssue(home: URL) -> ScanIssue {
        ScanIssue(url: home.appendingPathComponent("Library/Containers", isDirectory: true), message:
            "App container storage requires folder approval. Automatic scans skip Library/Containers and Library/Group Containers, including Docker disk images. Choose a folder in Disk Map to inspect it.")
    }
}

/// Metadata-only, descriptor-relative discovery. No child aliases are resolved.
enum CatalogueMetadata {
    /// Missing ancestors remain valid catalogue entries for a later scan. An
    /// existing alias or inaccessible ancestor is omitted before full-path
    /// metadata calls can resolve it into protected app storage.
    static func hasPhysicalExistingAncestors(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let components = url.roomLexicallyNormalized.pathComponents.filter { $0 != "/" }.dropLast()
        var descriptor = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        for component in components {
            var info = stat()
            guard fstatat(descriptor, component, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return errno == ENOENT }
            guard info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { return false }
            let next = openat(descriptor, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return false }
            close(descriptor)
            descriptor = next
        }
        return true
    }

    static func openDirectory(_ url: URL) -> Int32 {
        guard url.isFileURL else { return -1 }
        let components = url.pathComponents.filter { $0 != "/" }
        var descriptor = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return -1 }
        for (index, component) in components.enumerated() {
            let next = openat(descriptor, component,
                (index == components.count - 1 ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { return -1 }
            descriptor = next
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid() else { close(descriptor); return -1 }
        return descriptor
    }
    static func isPhysicalItem(_ url: URL, directory: Bool, opener: (URL) -> Int32) -> Bool {
        if directory {
            let fd = opener(url)
            guard fd >= 0 else { return false }
            close(fd)
            return true
        }
        let parent = opener(url.deletingLastPathComponent())
        guard parent >= 0 else { return false }
        defer { close(parent) }
        var info = stat()
        return fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0
            && info.st_uid == getuid() && info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG)
    }
    static func directoryNames(_ url: URL, limit: Int, opener: (URL) -> Int32) -> (names: [String], partial: Bool) {
        let descriptor = opener(url)
        guard descriptor >= 0 else { return ([], errno == EACCES || errno == EPERM) }
        defer { close(descriptor) }
        let copied = dup(descriptor)
        guard copied >= 0 else { return ([], true) }
        guard let stream = fdopendir(copied) else { close(copied); return ([], true) }
        defer { closedir(stream) }
        var result: [String] = []
        var count = 0
        while count < limit, let entry = readdir(stream) {
            let name = name(of: entry)
            guard name != ".", name != ".." else { continue }
            count += 1
            var info = stat()
            guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_uid == getuid(), info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { continue }
            result.append(name)
        }
        return (result, count >= limit)
    }
    static func isNonemptyPhysicalDirectory(_ url: URL, opener: (URL) -> Int32) -> (nonempty: Bool, denied: Bool) {
        let descriptor = opener(url)
        guard descriptor >= 0 else { return (false, errno == EACCES || errno == EPERM) }
        defer { close(descriptor) }
        let copied = dup(descriptor)
        guard copied >= 0 else { return (false, true) }
        guard let stream = fdopendir(copied) else { close(copied); return (false, true) }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
            let value = name(of: entry)
            if value != ".", value != ".." { return (true, false) }
        }
        return (false, false)
    }
    static func name(of entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
        }
    }
    static func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}
