import Foundation
import RoomCore

/// Where Developer looks without being told: known tool folders, and the projects found in the home.
nonisolated struct RoomDeveloperDiscovery: Sendable {
    /// Finds project folders in the home, leaving out the skipped paths.
    let projects: @Sendable (URL, Set<String>) async -> DeveloperProjectFinder.Result
    /// Finds projects of every kind and measures their build folders. `progress` hears the project being measured.
    var buildFolders: (@Sendable (URL, Set<String>, @escaping @Sendable (String) -> Void) async -> DeveloperProjectScan)?

    init(projects: @escaping @Sendable (URL, Set<String>) async -> DeveloperProjectFinder.Result,
         buildFolders: (@Sendable (URL, Set<String>, @escaping @Sendable (String) -> Void) async -> DeveloperProjectScan)? = nil) {
        self.projects = projects
        self.buildFolders = buildFolders
    }

    static let standard = RoomDeveloperDiscovery(projects: { home, skipped in
        await detached { DeveloperProjectFinder.find(home: home, excluding: skipped) }
    }, buildFolders: { home, skipped, progress in
        await detached { await DeveloperProjectScanner.scan(home: home, excluding: skipped, progress: progress) }
    })

    /// A detached task does not inherit cancellation, and Stop must reach the walk.
    private static func detached<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let walk = Task.detached(priority: .userInitiated) { await work() }
        return await withTaskCancellationHandler { await walk.value } onCancel: { walk.cancel() }
    }
}
