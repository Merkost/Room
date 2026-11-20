import Foundation
import Observation
import RoomCore

nonisolated struct RoomIgnoreRule: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var path: String                 // absolute, lexically normalized (Direct and Store; Store keeps accessFolderID too)
    var accessFolderID: String?
    var addedAt: Date
}

nonisolated enum RoomIgnoreFilter {
    /// A group is ignored when its root equals or lies inside an ignored path. Ignoring never changes engine eligibility;
    /// it removes the group's bytes from Clearable and from the selectable set and lists it in What stays.
    static func isIgnored(rootPath: String, rules: [RoomIgnoreRule]) -> Bool {
        rules.contains { rootPath == $0.path || rootPath.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
    }
}

@Observable @MainActor
final class RoomIgnoreStore {
    static let maximumRules = 500
    private(set) var rules: [RoomIgnoreRule] = []
    @ObservationIgnored private let state: RoomStateStore
    @ObservationIgnored private var loading: Task<RoomStateLoad<[RoomIgnoreRule]>, Never>?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var generation: UInt64 = 0

    init(state: RoomStateStore = .shared) { self.state = state }

    func load() async {
        guard !loaded else { return }
        if loading == nil {
            loading = Task { [state] in await state.load([RoomIgnoreRule].self, from: .ignore) }
        }
        let result = await loading?.value
        guard !loaded else { return }
        rules = result?.value ?? []
        loaded = true
        loading = nil
    }

    func add(_ folders: [(url: URL, accessFolderID: String?)]) async throws -> Set<UUID> {
        await load()
        var existing = Set(rules.map(\.path))
        let added = folders.compactMap { folder -> RoomIgnoreRule? in
            let path = folder.url.roomLexicallyNormalized.path
            guard folder.url.isFileURL, path.hasPrefix("/"), path != "/", existing.insert(path).inserted else { return nil }
            return RoomIgnoreRule(id: UUID(), path: path, accessFolderID: folder.accessFolderID, addedAt: Date())
        }
        guard !added.isEmpty else { return [] }
        guard rules.count + added.count <= Self.maximumRules else { throw RoomIgnoreError.limit }
        let next = rules + added
        try await save(next)
        return Set(added.map(\.id))
    }

    func remove(_ ids: Set<UUID>) async throws {
        await load()
        let next = rules.filter { !ids.contains($0.id) }
        if next != rules { try await save(next) }
    }

    private func save(_ next: [RoomIgnoreRule]) async throws {
        let previous = rules
        generation &+= 1
        let write = generation
        rules = next
        do { try await state.write(next, to: .ignore, generation: write) }
        catch {
            if generation == write { rules = previous }
            throw error
        }
    }
}

enum RoomIgnoreError: LocalizedError {
    case outsideApprovedFolder, limit

    var errorDescription: String? {
        switch self {
        case .outsideApprovedFolder: "Choose a folder inside a location Room already has permission to check."
        case .limit: "Room can remember up to 500 Never Suggest folders."
        }
    }
}
