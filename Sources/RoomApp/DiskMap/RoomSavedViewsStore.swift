import Foundation
import Observation
import RoomCore

nonisolated enum RoomSavedViewMode: String, Codable, Sendable {
    case map, largest
}

nonisolated struct RoomSavedView: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let root: RoomTreeLocation
    let nodePath: String
    let kind: StorageKind?
    let mode: RoomSavedViewMode

    static let limit = 32

    var isValid: Bool {
        Self.cleanName(name) == name &&
            !root.approvalID.isEmpty && root.approvalID.utf8.count <= 80 &&
            Self.isRelative(root.relativePath) && Self.isRelative(nodePath)
    }

    static func cleanName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, name.utf8.count <= 256,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return name
    }

    private static func isRelative(_ value: String) -> Bool {
        value.isEmpty || (!value.utf8.contains(0) && value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })
    }
}

nonisolated enum RoomSavedViewOpenResult: Equatable, Sendable {
    case opened, rootOnly, needsAccess, unavailable
}

nonisolated struct RoomSavedViewDisplay: Equatable, Sendable {
    let requestID: UUID
    let view: RoomSavedView
    let result: RoomSavedViewOpenResult?

    var showsMap: Bool { result == .opened || result == .rootOnly }
}

@Observable @MainActor
final class RoomSavedViewsStore {
    private(set) var entries: [RoomSavedView] = []
    private(set) var isReady = false
    private(set) var isReadOnly = false
    private var stagedRemovals: Set<UUID> = []
    @ObservationIgnored private let writer: RoomStateWriter
    @ObservationIgnored private var loading: Task<RoomStateLoad<[RoomSavedView]>, Never>?

    var visible: [RoomSavedView] { entries.filter { !stagedRemovals.contains($0.id) } }
    var canEdit: Bool { isReady && !isReadOnly }
    var canAdd: Bool { canEdit && entries.count < RoomSavedView.limit }

    init(writer: RoomStateWriter = .shared) { self.writer = writer }

    func load() async {
        guard !isReady else { return }
        if loading == nil {
            loading = Task { [writer] in
                await writer.store.load([RoomSavedView].self, from: .views)
            }
        }
        guard let result = await loading?.value, !isReady else { return }
        var seen: Set<UUID> = []
        entries = Array((result.value ?? []).filter { $0.isValid && seen.insert($0.id).inserted }
            .prefix(RoomSavedView.limit))
        isReadOnly = result.isReadOnly
        isReady = true
        loading = nil
    }

    @discardableResult
    func add(name: String, root: RoomTreeLocation, nodePath: String, kind: StorageKind?, mode: RoomSavedViewMode) -> RoomSavedView? {
        guard canAdd, let name = RoomSavedView.cleanName(name) else { return nil }
        let view = RoomSavedView(id: UUID(), name: name, root: root, nodePath: nodePath, kind: kind, mode: mode)
        guard view.isValid, save(entries + [view]) else { return nil }
        return view
    }

    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        guard canEdit, let name = RoomSavedView.cleanName(name),
              let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        if entries[index].name == name { return true }
        var updated = entries
        updated[index].name = name
        return save(updated)
    }

    func stageRemoval(_ id: UUID) {
        guard canEdit, entries.contains(where: { $0.id == id }) else { return }
        stagedRemovals.insert(id)
    }

    func undoRemoval(_ id: UUID) { stagedRemovals.remove(id) }

    func commitRemoval(_ id: UUID) {
        guard canEdit, stagedRemovals.remove(id) != nil else { return }
        _ = save(entries.filter { $0.id != id })
    }

    private func save(_ pending: [RoomSavedView]) -> Bool {
        let envelope = RoomStoredFile(schema: RoomStateFile.views.schema, writtenAt: .now,
                                      appVersion: "0", payload: pending)
        guard let count = try? RoomStateCodec.encoder().encode(envelope).count,
              count <= RoomStateFile.views.maxBytes - 128 else { return false }
        entries = pending
        writer.submit(pending, to: .views)
        return true
    }
}
