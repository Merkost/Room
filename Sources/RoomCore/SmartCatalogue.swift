import Darwin
import Foundation

extension CacheConfiguration {
    /// Caches found by what they are rather than where one app puts them: Chromium and Electron apps' rendering
    /// caches, app updates that were downloaded and never needed again, and a few more tool caches and logs.
    /// Each is still a named, rebuildable kind of folder; an unknown folder is never made removable.
    static func addingSmartSources(to base: CacheConfiguration,
                                   opener: ((URL) -> Int32)? = nil,
                                   installedApps: [String]? = nil) -> CacheConfiguration {
        let home = base.homeDirectory
        let open = opener ?? CatalogueMetadata.openDirectory
        let week: TimeInterval = 7 * 86_400
        let month: TimeInterval = 30 * 86_400
        var roots = base.roots
        func location(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: false).roomLexicallyNormalized }
        func intersects(_ a: URL, _ b: URL) -> Bool {
            a.path == b.path || a.path.hasPrefix(b.path + "/") || b.path.hasPrefix(a.path + "/")
        }
        func taken(_ url: URL) -> Bool {
            roots.contains { intersects($0.url, url) } || base.protectedLocations.contains { intersects($0.url, url) }
        }
        func add(_ id: String, _ title: String, _ path: String, category: String, symbol: String,
                 processes: [String], consequence: String, age: TimeInterval = week, lock: URL? = nil) {
            let url = location(path)
            guard !automaticContainerApprovalRequired(for: url, home: home),
                  CatalogueMetadata.hasPhysicalExistingAncestors(url), !taken(url),
                  !roots.contains(where: { $0.id == id }) else { return }
            roots.append(CacheRoot(id: id, title: title, subtitle: path, symbol: symbol, category: category, url: url,
                consequence: consequence, minimumAge: age, guardedProcesses: processes, runningLock: lock))
        }
        func folders(_ path: String) -> [String] {
            let url = location(path)
            guard !automaticContainerApprovalRequired(for: url, home: home) else { return [] }
            return CatalogueMetadata.directoryNames(url, limit: 1_536, opener: open).names.sorted()
        }
        func exists(_ path: String) -> Bool {
            var info = stat()
            return lstat(location(path).path, &info) == 0
        }

        // Xcode and its simulators.
        let xcode = ["xcode", "xcodebuild", "devicectl", "simulator", "launchd_sim"]
        for os in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            add("xcode-device-support-\(os.lowercased())", "\(os) device support", "Library/Developer/Xcode/\(os) DeviceSupport",
                category: "developer", symbol: "hammer", processes: xcode,
                consequence: "Xcode copies a device’s debug symbols again the next time you connect one running that version, which can take a few minutes. Versions copied in the last month stay.",
                age: month)
        }
        add("xcode-previews", "SwiftUI previews", "Library/Developer/Xcode/UserData/Previews/Simulator Devices",
            category: "developer", symbol: "hammer", processes: xcode + ["xcpreviewagent"],
            consequence: "Xcode sets up its preview simulators again the next time a preview runs.")
        add("xcode-playground-devices", "Playground simulators", "Library/Developer/XCPGDevices",
            category: "developer", symbol: "hammer", processes: xcode,
            consequence: "Xcode sets up a playground’s simulator again the next time it runs.")
        add("simulator-logs", "Simulator logs", "Library/Logs/CoreSimulator", category: "developer", symbol: "hammer",
            processes: xcode, consequence: "Simulator logs older than 30 days move to Trash.", age: month)

        // Downloads tools fetch again by themselves. Not here: Yarn's global cache (Plug'n'Play projects run from
        // it) and pre-commit's (its database points at each environment, so clearing some breaks commits).
        let node = ["node", "npm", "npx", "pnpm", "yarn", "corepack"]
        for (id, title, path, processes, consequence) in [
            ("corepack", "Corepack", ".cache/node/corepack", node,
             "Package manager versions are downloaded again when a project asks for them."),
            ("github-cli", "GitHub CLI", ".cache/gh", ["gh"], "Saved API answers and downloaded run logs are fetched again when needed."),
            ("pkg-native", "Packaged tool runtimes", ".cache/pkg", ["node", "copilot", "pkg"],
             "Tools built with pkg unpack these files again the next time they start."),
            ("prisma-engines", "Prisma", ".cache/prisma", node, "Prisma downloads its engines again when a project needs them."),
            ("selenium", "Selenium", ".cache/selenium", ["selenium-manager", "java", "python", "python3", "node", "chromedriver"],
             "Browser drivers are downloaded again the next time a test asks for one."),
            ("poetry-cache", "Poetry", "Library/Caches/pypoetry/cache", ["poetry", "python", "python3"],
             "Package metadata and downloads are fetched again. Poetry’s virtual environments stay in place."),
            ("poetry-artifacts", "Poetry", "Library/Caches/pypoetry/artifacts", ["poetry", "python", "python3"],
             "Downloaded package files are fetched again. Poetry’s virtual environments stay in place."),
            ("pipenv", "Pipenv", "Library/Caches/pipenv", ["pipenv", "python", "python3"],
             "Package downloads are fetched again during future installs."),
            ("python-bytecode", "Python bytecode", "Library/Caches/com.apple.python", ["python", "python3"],
             "Python compiles these files again the next time it runs the same scripts."),
            ("blender-kernels", "Blender render kernels", ".cache/cycles", ["blender"],
             "Blender compiles its render kernels again; the first render after may take longer."),
        ] {
            add(id, title, path, category: "developer", symbol: "shippingbox", processes: processes, consequence: consequence)
        }

        // AI tools' logs.
        for (id, title, path, processes) in [
            ("codex-app-logs", "Codex logs", "Library/Logs/com.openai.codex", ["codex", "chatgpt"]),
            ("claude-app-logs", "Claude logs", "Library/Logs/Claude", ["claude"]),
            ("ollama-logs", "Ollama logs", ".ollama/logs", ["ollama"]),
            ("lmstudio-logs", "LM Studio logs", "Library/Logs/LM Studio", ["lm studio", "lmstudio"]),
        ] {
            add(id, title, path, category: "agents", symbol: "sparkle", processes: processes,
                consequence: "Logs older than 30 days move to Trash. Recent ones stay for troubleshooting.", age: month)
        }
        add("chatgpt-cache", "ChatGPT", "Library/Caches/com.openai.chat", category: "agents", symbol: "sparkle",
            processes: ["chatgpt"], consequence: "Downloaded images and web content are fetched again. Conversations stay in your account.")

        // App updates already downloaded: Squirrel's ShipIt folders and electron-updater's.
        for name in folders("Library/Caches") where name.hasSuffix(".ShipIt") || name.hasSuffix("-updater") {
            let owner = Self.updateOwner(name)
            add("update-" + CatalogueMetadata.stableID(name), owner.title, "Library/Caches/" + name, category: "apps",
                symbol: "app", processes: owner.processes + ["shipit"],
                consequence: "A downloaded app update. The app downloads it again if it still needs it; installed apps stay as they are.")
        }
        for name in folders("Library/Application Support/Caches") where name.hasSuffix("-updater") {
            let owner = Self.updateOwner(name)
            add("update-" + CatalogueMetadata.stableID("support/" + name), owner.title, "Library/Application Support/Caches/" + name,
                category: "apps", symbol: "app", processes: owner.processes,
                consequence: "A downloaded app update. The app downloads it again if it still needs it; installed apps stay as they are.")
        }

        // Chromium and Electron apps, known by their profile's shape rather than their name. Only the HTTP and
        // compiled-graphics caches: never storage, cookies, sessions, service workers or extensions.
        let render = ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
                      "GPUPersistentCache", "GraphiteDawnCache"]
        // Apps the catalogue already names keep their own rows.
        let supportPrefix = location("Library/Application Support").path + "/"
        let named = Set(roots.compactMap { root -> String? in
            guard root.url.path.hasPrefix(supportPrefix) else { return nil }
            return root.url.path.dropFirst(supportPrefix.count).split(separator: "/").first.map(String.init)
        })
        let apps = Self.appNames(installedApps ?? Self.installedAppNames(home: home))
        for name in folders("Library/Application Support") where !named.contains(name) {
            let parent = "Library/Application Support/" + name
            guard Self.isChromiumProfile(exists: { exists(parent + "/" + $0) }) else { continue }
            let app = Self.appIdentity(name, installed: apps)
            var profiles = [parent]
            for partition in folders(parent + "/Partitions").prefix(16) {
                let path = parent + "/Partitions/" + partition
                if Self.isChromiumProfile(exists: { exists(path + "/" + $0) }) { profiles.append(path) }
            }
            // VS Code and its forks also keep compiled extension data and downloaded extension archives.
            let editor = exists(parent + "/User") && exists(parent + "/CachedData")
            for profile in profiles {
                for folder in render + (editor && profile == parent ? ["CachedData", "CachedExtensionVSIXs"] : []) {
                    guard exists(profile + "/" + folder) else { continue }
                    add("app:" + CatalogueMetadata.stableID(name) + ":" + CatalogueMetadata.stableID(profile + "/" + folder),
                        app.title, profile + "/" + folder, category: app.category, symbol: app.category == "agents" ? "sparkle" : "app",
                        processes: app.processes,
                        consequence: "Downloaded web content and compiled graphics are recreated. The app’s documents, sign-in, settings and stored data stay.",
                        lock: location(parent + "/SingletonLock"))
                }
            }
        }

        return CacheConfiguration(roots: roots, protectedLocations: base.protectedLocations, homeDirectory: home,
            inspectionIssues: base.inspectionIssues, readAccessRoots: base.readAccessRoots,
            protectedMeasurementExclusions: base.protectedMeasurementExclusions)
    }

    /// A Chromium user-data folder: preferences, plus the network state or caches every Chromium app writes.
    static func isChromiumProfile(exists: (String) -> Bool) -> Bool {
        (exists("Preferences") || exists("Local State"))
            && (exists("Network Persistent State") || exists("Code Cache") || exists("GPUCache"))
    }

    /// Installed apps' names ("Yandex Music", "Logi Options+"), from the app folders' listings only.
    static func installedAppNames(home: URL) -> [String] {
        ["/Applications", "/Applications/Utilities", home.appendingPathComponent("Applications").path].flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) }
        }
    }

    /// Letters and digits only, so "YandexMusic", "yandex-music" and "Yandex Music" meet.
    static func appKey(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func appNames(_ names: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for name in names.sorted() where !appKey(name).isEmpty { map[appKey(name)] = map[appKey(name)] ?? name }
        return map
    }

    /// Folder names apps use that aren't the app's name, and the AI and developer apps among them.
    static func appIdentity(_ folder: String, installed: [String: String] = [:]) -> (title: String, processes: [String], category: String) {
        let known: [String: (String, [String], String)] = [
            "RealtimeBoard": ("Miro", ["miro", "realtimeboard"], "apps"),
            "UnityHub": ("Unity Hub", ["unity hub", "unityhub"], "developer"),
            "Docker Desktop": ("Docker Desktop", ["docker desktop", "com.docker.backend"], "developer"),
            "t3code-v2": ("T3 Code", ["t3 code", "t3code"], "agents"),
            "Windsurf": ("Windsurf", ["windsurf"], "agents"),
            "Kiro": ("Kiro", ["kiro"], "agents"),
            "Trae": ("Trae", ["trae"], "agents"),
            "Void": ("Void", ["void"], "agents"),
            "Zed": ("Zed", ["zed"], "agents"),
            "Jan": ("Jan", ["jan"], "agents"),
            "Msty": ("Msty", ["msty"], "agents"),
            "Perplexity": ("Perplexity", ["perplexity"], "agents"),
            "ChatGPT": ("ChatGPT", ["chatgpt"], "agents"),
            "lm-studio": ("LM Studio", ["lm studio", "lmstudio"], "agents"),
            "GitHub Desktop": ("GitHub Desktop", ["github desktop"], "developer"),
            "apidog": ("Apidog", ["apidog"], "developer"),
        ]
        if let known = known[folder] { return (known.0, known.1, known.2) }
        let lower = folder.lowercased()
        var processes = Set([lower, lower.replacingOccurrences(of: "-", with: " ")])
        // The installed app's own name reads better and is what its process is called.
        let app = installed[appKey(folder)] ?? installed[appKey(folder.replacingOccurrences(of: "Plus", with: "+"))]
        if let app { processes.insert(app.lowercased()) }
        return (app ?? readable(folder), processes.sorted(), "apps")
    }

    /// "YandexMusic" → "Yandex Music", "appium-inspector" → "Appium Inspector"; "1Password" stays.
    static func readable(_ folder: String) -> String {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in folder {
            if character == "-" || character == "_" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase, current.count > 1 {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// "com.linear.ShipIt" → Linear; "@lineardesktop-updater" → Linear; "apidog-updater" → Apidog.
    static func updateOwner(_ folder: String) -> (title: String, processes: [String]) {
        var name = folder
        if name.hasSuffix(".ShipIt") {
            name = String(name.dropLast(".ShipIt".count))
            name = name.split(separator: ".").last.map(String.init) ?? name
        } else {
            name = String(name.dropLast("-updater".count))
            if name.hasPrefix("@") { name.removeFirst() }
        }
        for suffix in ["desktop", "fordesktop", "-desktop", "app"] where name.lowercased().hasSuffix(suffix) && name.count > suffix.count {
            name = String(name.dropLast(suffix.count))
        }
        let named: [String: String] = ["claude": "Claude", "claudefor": "Claude", "linear": "Linear", "apidog": "Apidog",
                                       "github": "GitHub Desktop", "slack": "Slack", "discord": "Discord", "notion": "Notion",
                                       "figma": "Figma", "cursor": "Cursor", "postman": "Postman"]
        let lower = name.lowercased()
        let title = named[lower] ?? (lower.prefix(1).uppercased() + lower.dropFirst())
        return ("\(title) update", Array(Set([lower, title.lowercased()])).sorted())
    }
}
