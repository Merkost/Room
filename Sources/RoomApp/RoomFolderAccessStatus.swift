import Foundation

nonisolated enum RoomFolderAccessStatus: Equatable, Sendable {
    case readsSizes, protectedByMacOS

    var isReadable: Bool { self == .readsSizes }
    var text: String { isReadable ? "Reads sizes" : "Protected by macOS" }

    static func status(for url: URL) -> Self {
        #if ROOM_APP_STORE
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        return FileManager.default.isReadableFile(atPath: url.path) ? .readsSizes : .protectedByMacOS
    }
}
