import Foundation

extension CacheConfiguration {
    /// A deeper catalogue still names individual, regenerable locations. A folder
    /// being hidden, temporary, or named Caches does not establish disposability.
    public static var deep: CacheConfiguration { addingDeepSources(to: .standard) }

    static func addingDeepSources(to base: CacheConfiguration) -> CacheConfiguration {
        let home = base.homeDirectory
        var roots = base.roots
        var protected = base.protectedLocations
        let week: TimeInterval = 7 * 86_400
        let month: TimeInterval = 30 * 86_400
        func location(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: false) }
        func add(_ id: String, _ title: String, _ path: String, _ category: String,
                 _ symbol: String, _ processes: [String], _ consequence: String,
                 age: TimeInterval = week, scope: CacheScope = .children) {
            roots.append(CacheRoot(id: id, title: title, subtitle: path, symbol: symbol,
                category: category, url: location(path), consequence: consequence,
                minimumAge: age, guardedProcesses: processes, scope: scope))
        }
        func keep(_ id: String, _ title: String, _ path: String, _ reason: String) {
            protected.append(ProtectedLocation(id: id, title: title, url: location(path), reason: reason))
        }
        // Local installation discovery is shallow and skips substituted directories.
        func folders(_ path: String) -> [String] {
            let url = location(path)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let children = try? FileManager.default.contentsOfDirectory(at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
            return children.compactMap { child in
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                return child.lastPathComponent
            }.sorted()
        }
        func slug(_ value: String) -> String {
            value.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        }

        add("claude-model-catalog", "Claude model catalog", ".claude/cache/model-catalog", "agents", "sparkle", ["claude", "node"],
            "Downloaded model discovery metadata is fetched again. Credentials and settings stay protected.")
        for folder in ["shell-snapshots", "session-env"] {
            add("claude-\(folder)", "Claude environment snapshots", ".claude/\(folder)", "agents", "sparkle", ["claude", "node"],
                "Environment snapshots older than 30 days move to Trash. Current sessions and their history stay protected.", age: month)
        }
        // Chromium/Electron rendering caches only; no IndexedDB, Local Storage,
        // profiles, extension installations, browser cookies or session state.
        let renderFolders = ["Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache"]
        for (id, title, support, category, processes) in [
            ("vscode", "VS Code", "Code", "developer", ["code", "code helper"]),
            ("cursor", "Cursor", "Cursor", "agents", ["cursor", "node"]),
            ("antigravity", "Antigravity", "Antigravity", "agents", ["antigravity", "node"])
        ] {
            for folder in renderFolders + ["CachedData", "CachedExtensionVSIXs"] {
                add("\(id)-\(slug(folder))", title, "Library/Application Support/\(support)/\(folder)", category, "curlybraces", processes,
                    "Compiled interface data and extension download archives are recreated. Installed extensions, settings, backups and workspace state stay protected.")
            }
        }
        for (id, app) in [("codex", "Codex"), ("claude", "Claude")] {
            for profile in ["Default"] + folders("Library/Application Support/\(app)/Partitions").map({ "Partitions/" + $0 }) {
                for folder in renderFolders {
                    add("\(id)-profile-\(slug(profile))-\(slug(folder))", app,
                        "Library/Application Support/\(app)/\(profile)/\(folder)", "agents", id == "codex" ? "terminal" : "sparkle",
                        id == "codex" ? ["codex", "chatgpt"] : ["claude", "node"],
                        "This profile's graphics and compiled-code cache rebuilds. Browser history, cookies, conversations and preview files stay protected.")
                }
            }
        }
        add("npm-exec", "npm execution cache", ".npm/_npx", "developer", "shippingbox", ["node", "npm", "npx", "pnpm", "yarn"],
            "Downloaded npm-exec tools are downloaded again on their next run. Running Node tools keep this cache unavailable.")
        add("npm-logs", "npm diagnostics", ".npm/_logs", "developer", "shippingbox", ["node", "npm", "npx"],
            "Diagnostic logs older than 30 days move to Trash.", age: month)
        for folder in ["manifests", "package-metadata", "repositories", "artifacts"] {
            add("swiftpm-\(folder)", "Swift packages", "Library/Caches/org.swift.swiftpm/\(folder)", "developer", "swift", ["swift", "swift-build", "xcode", "xcodebuild", "sourcekit"],
                "Package metadata, repository mirrors and downloaded artifacts may be fetched or built again. Project checkouts stay in place.")
        }
        for (id, title, path, processes) in [
            ("cargo", "Rust packages", ".cargo/registry/cache", ["cargo", "rustc", "rust-analyzer"]),
            ("go-build", "Go build cache", "Library/Caches/go-build", ["go", "gopls"]),
            ("go-downloads", "Go module downloads", "go/pkg/mod/cache/download", ["go", "gopls"]),
            ("node-gyp", "Node build headers", "Library/Caches/node-gyp", ["node", "npm", "node-gyp"]),
            ("konan", "Kotlin Native cache", ".konan/cache", ["java", "konanc", "kotlinc"])
        ] {
            add(id, title, path, "developer", "shippingbox", processes,
                "Downloaded packages or generated build data may need to be downloaded or compiled again. Installed toolchains and project source stay protected.")
        }
        for folder in ["gen", "npm", "remote"] {
            add("deno-\(folder)", "Deno", "Library/Caches/deno/\(folder)", "developer", "shippingbox", ["deno"],
                "Cached remote modules, generated code and package downloads are fetched or built again.")
        }
        // JetBrains system folders also contain LocalHistory, plugins and project
        // state. Include only explicit index/compiler-cache children.
        for (parent, prefix, title) in [("Library/Caches/Google", "AndroidStudio", "Android Studio"),
                                        ("Library/Caches/JetBrains", "", "JetBrains")] {
            for version in folders(parent) where prefix.isEmpty || version.hasPrefix(prefix) {
                for cache in ["index", "caches", "compiler", "compile-server", "ModuleCache", "kotlin-native-forward-declarations", "vcs-log"] {
                    add("\(prefix.isEmpty ? "jetbrains" : "androidstudio")-\(slug(version))-\(slug(cache))", title,
                        "\(parent)/\(version)/\(cache)", "developer", "hammer", ["java", "studio", "idea", "pycharm", "webstorm", "clion"],
                        "Indexes and compiler caches rebuild on the next IDE launch. Local History, installed plugins, terminal state and project metadata stay protected.")
                }
                keep("ide-history-\(slug(parent))-\(slug(version))", "\(title) Local History", "\(parent)/\(version)/LocalHistory",
                    "IDE recovery history. A folder under Library/Caches can still contain valuable work; this is never cleaned.")
            }
        }
        for (id, title, path, processes) in [
            ("chrome", "Chrome", "Library/Caches/Google/Chrome", ["google chrome", "chrome", "chromium"]),
            ("brave", "Brave", "Library/Caches/BraveSoftware/Brave-Browser", ["brave browser", "brave"]),
            ("edge", "Edge", "Library/Caches/Microsoft Edge", ["microsoft edge", "edge"]),
            ("firefox", "Firefox", "Library/Caches/Firefox/Profiles", ["firefox"]),
            ("safari", "Safari", "Library/Caches/com.apple.Safari", ["safari", "webkit"]),
            ("spotify", "Spotify", "Library/Caches/com.spotify.client", ["spotify"])
        ] {
            add(id, title, path, "apps", "app", processes,
                "Cached downloads and web resources are recreated. The app's Application Support data, browser history, cookies, and saved credentials are excluded.")
        }
        for (id, title, path, reason) in [
            ("codex-temporary", "Codex temporary work", ".codex/.tmp", "May contain repository clones, plugin staging and active work. Inspect with Disk Map; never cleaned automatically."),
            ("codex-runtimes", "Codex runtimes", ".cache/codex-runtimes", "Installed runtimes used by agent tools. The cache name does not make them disposable."),
            ("codex-runtime-packages", "Codex runtime packages", ".codex/packages", "Installed standalone tools and app-server packages. Keep these resources in place; inspect their size with Disk Map."),
            ("codex-project-files", "Codex project files", ".codex/.chatgpt-projects", "Project documents and workspace files. A hidden directory can contain user work; this is never cleaned."),
            ("claude-staging", "Claude runtime staging", ".cache/claude", "Runtime installation and staging data. Inspect with Disk Map; leave installed tooling in place."),
            ("claude-backups", "Claude configuration backups", ".claude/backups", "Recovery copies of configuration; kept for manual review."),
            ("claude-session-data", "Claude desktop sessions", "Library/Application Support/Claude/claude-code-sessions", "Conversation and session data, not a rendering cache."),
            ("cursor-work", "Cursor conversations and tools", ".cursor", "Projects, conversations, skills, installed extensions and plugins are user work."),
            ("gemini-work", "Gemini state and work", ".gemini", "Temporary project folders can contain conversations and installed binaries. Inspect only."),
            ("uv-managed", "uv managed cache", ".cache/uv", "uv requires its own cache-clean or cache-prune commands for cache consistency. Room maps it but never directly moves its files."),
            ("playwright-runtime", "Playwright browsers", "Library/Caches/ms-playwright", "Installed browser runtimes used by tools; not disposable downloads."),
            ("android-devices", "Android virtual devices", ".android/avd", "Virtual devices and their user data. Inspect only."),
            ("rust-toolchains", "Rust toolchains", ".rustup", "Installed compilers and SDKs. Inspect only.")
        ] { keep(id, title, path, reason) }

        var ids = Set<String>(), paths = Set<String>()
        let uniqueRoots = roots.filter { ids.insert($0.id).inserted && paths.insert($0.url.path).inserted }
        return CacheConfiguration(roots: uniqueRoots, protectedLocations: protected, homeDirectory: home, inspectionIssues: base.inspectionIssues)
    }
}
