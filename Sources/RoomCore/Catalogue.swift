import Foundation

extension CacheConfiguration {
    /// Explicit, rebuildable locations only. Missing locations never produce cleanup candidates.
    public static var standard: CacheConfiguration {
        standard(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Pure catalogue construction; Store callers supply the real user home
    /// rather than deriving source paths from the sandbox container.
    static func standard(home: URL) -> CacheConfiguration {
        func location(_ path: String) -> URL { home.appendingPathComponent(path) }
        let week: TimeInterval = 7 * 86_400
        let month: TimeInterval = 30 * 86_400
        var roots: [CacheRoot] = []
        func add(_ id: String, _ title: String, _ path: String, _ category: String,
                 _ symbol: String, _ processes: [String], _ consequence: String,
                 age: TimeInterval = week, scope: CacheScope = .children) {
            roots.append(CacheRoot(id: id, title: title, subtitle: path, symbol: symbol,
                category: category, url: location(path), consequence: consequence,
                minimumAge: age, guardedProcesses: processes, scope: scope))
        }

        // Some desktop installations retain ChatGPT as the executable/app name.
        let codex = ["codex", "chatgpt"]
        // Claude's node-based CLI may appear only as `node` in the process list.
        // Conservatively hold Claude caches while any Node runtime is active.
        let claude = ["claude", "node"]
        add("codex-cache", "Codex", ".codex/cache", "agents", "terminal", codex,
            "Downloaded cache data may be fetched again. Conversations and worktrees stay protected.")
        add("codex-logs", "Codex logs", ".codex/log", "agents", "terminal", codex,
            "Diagnostic logs older than 30 days move to Trash. Keep logs needed for support.", age: month)
        add("codex-system", "Codex cache", "Library/Caches/Codex", "agents", "terminal", codex,
            "Codex may recreate cached interface resources on its next launch.")
        add("codex-bundle", "Codex app cache", "Library/Caches/com.openai.codex", "agents", "terminal", codex,
            "Codex may recreate cached interface resources on its next launch.")
        add("claude-changelog", "Claude changelog", ".claude/cache/changelog.md", "agents", "sparkle", claude,
            "The CLI can download its changelog again. Installed plugins remain protected.", scope: .singleFile)
        add("claude-debug", "Claude diagnostics", ".claude/debug", "agents", "sparkle", claude,
            "Diagnostic logs older than 30 days move to Trash. Keep logs needed for support.", age: month)
        add("claude-cli", "Claude CLI cache", "Library/Caches/claude-cli-nodejs", "agents", "sparkle", claude,
            "Claude CLI may download cached resources again.")

        let desktopFolders = ["Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GPUPersistentCache", "GraphiteDawnCache"]
        for app in ["Codex", "Claude"] {
            for folder in desktopFolders {
                add("\(app.lowercased())-desktop-\(folder.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    "\(app) · \(folder)", "Library/Application Support/\(app)/\(folder)", "agents",
                    app == "Codex" ? "terminal" : "sparkle", app == "Codex" ? codex : claude,
                    "The app recreates graphics and compiled code caches. Its databases and conversations stay protected.")
            }
        }

        add("xcode-derived", "Xcode", "Library/Developer/Xcode/DerivedData", "developer", "hammer", ["xcode", "xcodebuild", "swift", "sourcekit"],
            "Build products and indexes rebuild when you open a project. The next build may take longer.")
        add("gradle", "Gradle", ".gradle/caches", "developer", "shippingbox", ["gradle", "java", "studio"],
            "Gradle downloads dependencies and rebuilds cached outputs during future builds.")
        add("npm", "npm", ".npm/_cacache", "developer", "shippingbox", ["node", "npm", "pnpm", "yarn"],
            "Package archives download again during future installs.")
        add("yarn", "Yarn", "Library/Caches/Yarn", "developer", "shippingbox", ["node", "npm", "pnpm", "yarn"],
            "Package archives download again during future installs.")
        add("pip", "Python packages", "Library/Caches/pip", "developer", "shippingbox", ["pip", "python"],
            "Python package downloads and built wheels may need to be downloaded or rebuilt.")
        add("homebrew", "Homebrew", "Library/Caches/Homebrew", "developer", "shippingbox", ["brew", "ruby"],
            "Downloaded package archives will be fetched again. Installed packages stay in place.")

        let protected: [(String, String, String)] = [
            ("codex-sessions", "Codex conversations", ".codex/sessions"),
            ("codex-archived", "Archived Codex conversations", ".codex/archived_sessions"),
            ("codex-worktrees", "Codex worktrees", ".codex/worktrees"),
            ("codex-skills", "Codex skills", ".codex/skills"),
            ("codex-plugins", "Codex plugins", ".codex/plugins"),
            ("codex-thread-index", "Codex conversation index", ".codex/thread_history_1.sqlite"),
            ("codex-databases", "Codex databases", ".codex/sqlite"),
            ("codex-memories", "Codex memories", ".codex/memories"),
            ("codex-attachments", "Codex attachments", ".codex/attachments"),
            ("codex-images", "Codex images", ".codex/generated_images"),
            ("claude-projects", "Claude conversations", ".claude/projects"),
            ("claude-history", "Claude file history", ".claude/file-history"),
            ("claude-plans", "Claude plans", ".claude/plans"),
            ("claude-tasks", "Claude tasks", ".claude/tasks"),
            ("claude-todos", "Claude todos", ".claude/todos"),
            ("claude-paste", "Claude pasted content", ".claude/paste-cache"),
            ("claude-plugins", "Claude plugins", ".claude/plugins")
        ]
        let protectedLocations = protected.map {
            ProtectedLocation(id: $0.0, title: $0.1, url: location($0.2),
                reason: "User work and installed agent resources. Informational only; never included in cleanup.")
        }
        return CacheConfiguration(roots: roots, protectedLocations: protectedLocations, homeDirectory: home)
    }
}
