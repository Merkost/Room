import Foundation

/// Finds the folders in a home that hold Gradle or Xcode projects, so Developer needs no folder choice.
/// It reads names only, follows no links, and stops at its limits.
public enum DeveloperProjectFinder {
    public struct Result: Sendable, Equatable {
        /// Project folders, or their parents when there are more than the limit.
        public let projects: [URL]
        /// The walk or the list was cut short.
        public let partial: Bool

        public init(projects: [URL], partial: Bool) {
            self.projects = projects
            self.partial = partial
        }
    }

    private static let skipped: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public",
                                               "node_modules", "build", "dist", "Pods", "vendor", "DerivedData"]
    private static let packages: Set<String> = ["app", "bundle", "framework", "photoslibrary", "musiclibrary",
                                                "tvlibrary", "xcarchive"]
    private static let markers: Set<String> = ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"]

    public static func find(home: URL, excluding: Set<String> = [], maximumDepth: Int = 5,
                            maximumDirectories: Int = 6_000, timeLimit: TimeInterval = 8, limit: Int = 32) -> Result {
        let home = home.roomLexicallyNormalized
        let deadline = Date().addingTimeInterval(timeLimit)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var queue: [(url: URL, depth: Int)] = [(home, 0)]
        var next = 0
        var found: [String] = []
        var partial = false
        while next < queue.count {
            if next >= maximumDirectories || Date() >= deadline || Task.isCancelled { partial = true; break }
            let (folder, depth) = queue[next]
            next += 1
            // An unreadable folder (permission not granted) is simply not searched.
            guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
            else { continue }
            if depth > 0, isProject(folder, children: children) {
                found.append(folder.path)
                continue
            }
            guard depth < maximumDepth else { continue }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = child.lastPathComponent
                guard !name.hasPrefix("."), !skipped.contains(name), !packages.contains(child.pathExtension.lowercased()),
                      let values = try? child.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let path = folder.appendingPathComponent(name, isDirectory: true).roomLexicallyNormalized
                guard !excluding.contains(path.path) else { continue }
                queue.append((path, depth + 1))
            }
        }
        let (paths, cut) = collapse(found, home: home.path, limit: max(1, limit))
        return Result(projects: paths.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) },
                      partial: partial || cut)
    }

    private static func isProject(_ folder: URL, children: [URL]) -> Bool {
        let names = Set(children.map(\.lastPathComponent))
        if !names.isDisjoint(with: markers) { return true }
        if children.contains(where: { $0.pathExtension == "xcodeproj" }) { return true }
        return names.contains("gradle") && FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties").path)
    }

    /// Replaces the busiest sibling group with its parent until the list fits. The home itself is never used.
    private static func collapse(_ paths: [String], home: String, limit: Int) -> ([String], Bool) {
        var paths = Set(paths)
        while paths.count > limit {
            let groups = Dictionary(grouping: paths) { ($0 as NSString).deletingLastPathComponent }
                .filter { $0.key != home && $0.value.count > 1 }
            guard let busiest = groups.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) else {
                return (Array(paths.sorted().prefix(limit)), true)
            }
            paths = paths.filter { !$0.hasPrefix(busiest.key + "/") }
            paths.insert(busiest.key)
        }
        return (Array(paths), false)
    }
}
