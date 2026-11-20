import Foundation

nonisolated enum RoomFolderAccessStatus: Equatable, Sendable {
    case readsSizes, protectedByMacOS, missing

    var isReadable: Bool { self == .readsSizes }
    var text: String {
        switch self {
        case .readsSizes: "Reads sizes"
        case .protectedByMacOS: "Protected by macOS"
        case .missing: "Folder not found"
        }
    }

    static func status(for url: URL) -> Self {
        #if ROOM_APP_STORE
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        return FileManager.default.isReadableFile(atPath: url.path) ? .readsSizes : .protectedByMacOS
    }
}
