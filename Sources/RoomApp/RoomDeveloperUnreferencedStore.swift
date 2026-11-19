import Foundation

nonisolated struct RoomDevUnreferenced: Codable, Equatable, Sendable {
    var since: [String: Date] = [:]   // RoomDevArtifact.key → first complete scan that found it unreferenced

    /// Only a complete, uncancelled scan may start, keep or clear a date: a partial scan could miss the project that
    /// references a version, so it neither extends nor resets anything.
    func updated(orphanKeys: Set<String>, referencedKeys: Set<String>, scanComplete: Bool, now: Date) -> Self {
        guard scanComplete else { return self }
        var next = Self()
        for key in orphanKeys { next.since[key] = since[key].map { min($0, now) } ?? now }
        _ = referencedKeys     // a referenced key simply drops out
        return next
    }

    static let preferenceKey = "RoomUnpinnedFlagDays"
    static let defaultThreshold = 90
    static let thresholdChoices = [30, 60, 90, 180]   // Settings › General, default 90 (RoomUnpinnedFlagDays)

    static func caption(since: Date?, now: Date, thresholdDays: Int) -> String? {
        guard let since, thresholdChoices.contains(thresholdDays) else { return nil }
        let days = Int(now.timeIntervalSince(since) / 86_400)
        guard days >= thresholdDays else { return nil }
        let span = days >= 60 ? "\(days / 30) months" : "\(days / 7) weeks"
        return "Not referenced for \(span)"
    }
}

struct RoomDeveloperUnreferencedStore {
    var directory: URL = RoomRoomsStore.defaultDirectory
    private var file: URL { directory.appendingPathComponent("developer-unreferenced.json") }

    func load() -> RoomDevUnreferenced {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 512 * 1_024, let data = try? Data(contentsOf: file),
              let record = try? JSONDecoder().decode(RoomDevUnreferenced.self, from: data) else {
            return RoomDevUnreferenced()
        }
        return record
    }

    func save(_ record: RoomDevUnreferenced) {
        do {
            let data = try JSONEncoder().encode(record)
            guard data.count <= 512 * 1_024 else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            // The current session still knows which versions lacked a reference.
        }
    }
}
