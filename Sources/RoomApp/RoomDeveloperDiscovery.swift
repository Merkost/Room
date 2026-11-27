import Foundation
import RoomCore

/// Where Developer looks without being told: known tool folders, and the projects found in the home.
nonisolated struct RoomDeveloperDiscovery: Sendable {
    /// Finds project folders in the home, leaving out the skipped paths.
    let projects: @Sendable (URL, Set<String>) async -> DeveloperProjectFinder.Result

    static let standard = RoomDeveloperDiscovery { home, skipped in
        let walk = Task.detached(priority: .userInitiated) {
            DeveloperProjectFinder.find(home: home, excluding: skipped)
        }
        // A detached task does not inherit cancellation, and Stop must reach the walk.
        return await withTaskCancellationHandler { await walk.value } onCancel: { walk.cancel() }
    }
}
