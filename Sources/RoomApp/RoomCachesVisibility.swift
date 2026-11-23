import Foundation

/// Caches uses the same persisted preference as the shell until its Hide environment is connected.
nonisolated enum RoomCachesVisibility {
    static let preferenceKey = "RoomHideSizes"

    static func figure(_ text: String, hidden: Bool) -> String {
        guard hidden else { return text }
        return String(text.map { $0.isNumber ? "•" : $0 })
    }

    @MainActor static func bytes(_ bytes: Int64, hidden: Bool) -> String {
        figure(RoomFormat.overviewBytes(bytes), hidden: hidden)
    }
}
