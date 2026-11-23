#if DEBUG
import Foundation

extension RoomDeveloperModel {
    /// Debug launch hook for screenshots: `ROOM_DEBUG_DEVELOPER_ROOT` names a throwaway folder holding
    /// `projects`, `gradle`, `sdk`, `derived`, `konan` (and optionally `avd`, `simulators`, `ai-codex`). It runs against isolated defaults
    /// and bookmarks so the real app state is never touched. `ROOM_DEBUG_DEVELOPER_SCAN=1` scans on launch and
    /// `ROOM_DEBUG_DEVELOPER_SECTION` picks the tab.
    static func debugFixture() -> RoomDeveloperModel? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["ROOM_DEBUG_DEVELOPER_ROOT"] else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let defaults = UserDefaults(suiteName: "RoomDeveloperDebugFixture") else { return nil }
        defaults.removePersistentDomain(forName: "RoomDeveloperDebugFixture")
        let model = RoomDeveloperModel(access: RoomFileAccess(defaults: defaults), defaults: defaults,
                                       unreferencedStore: RoomDeveloperUnreferencedStore(directory: root.appendingPathComponent("state", isDirectory: true)),
                                       activityCenter: nil)
        if environment["ROOM_DEBUG_DEVELOPER_EMPTY"] == nil {
            let roles: [(String, RoomDeveloperFolderRole)] = [
                ("projects", .project), ("gradle", .gradle), ("sdk", .sdk), ("derived", .xcode), ("konan", .konan),
                ("avd", .android), ("simulators", .simulators), ("ai-codex", .codex)]
            for (folder, role) in roles {
                let url = root.appendingPathComponent(folder, isDirectory: true)
                if FileManager.default.fileExists(atPath: url.path) { model.debugRemember(url, role: role) }
            }
        }
        if let raw = environment["ROOM_DEBUG_DEVELOPER_SECTION"], let section = RoomDeveloperSection(rawValue: raw) {
            model.section = section
        }
        if environment["ROOM_DEBUG_DEVELOPER_SCAN"] != nil { Task { @MainActor in model.scan() } }
        return model
    }
}
#endif
