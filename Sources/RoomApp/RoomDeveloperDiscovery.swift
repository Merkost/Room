import Foundation
import RoomCore

/// Where Developer looks without being told: known tool folders, and the projects found in the home.
nonisolated struct RoomDeveloperDiscovery: Sendable {
    /// Finds project folders in the home, leaving out the skipped paths.
    let projects: @Sendable (URL, Set<String>) async -> DeveloperProjectFinder.Result

    static let standard = RoomDeveloperDiscovery { home, skipped in
        await Task.detached(priority: .userInitiated) {
            #if ROOM_APP_STORE
            let scoped = home.startAccessingSecurityScopedResource()
            defer { if scoped { home.stopAccessingSecurityScopedResource() } }
            #endif
            return DeveloperProjectFinder.find(home: home, excluding: skipped)
        }.value
    }
}
