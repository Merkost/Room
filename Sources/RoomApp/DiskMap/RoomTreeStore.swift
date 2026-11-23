import Foundation
import OSLog
import RoomCore

nonisolated struct RoomTreeLocation: Codable, Equatable, Sendable {
    let approvalID: String
    let relativePath: String

    func resolve(under folder: URL) -> URL? {
        let components = relativePath.split(separator: "/")
        guard !relativePath.hasPrefix("/"),
              !components.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return relativePath.isEmpty ? folder : folder.appendingPathComponent(relativePath, isDirectory: true)
    }
}

actor RoomTreeStore {
    static let shared = RoomTreeStore()

    nonisolated struct Root: Codable, Sendable {
        let location: RoomTreeLocation
        var lastUsed: Date
        var changedAt: Date?
    }

    private nonisolated struct Index: Codable, Sendable {
        var homeRootID: String?
        var lastOpened: String?
        var roots: [String: Root] = [:]
    }

    private nonisolated struct Payload: Codable, Sendable {
        let current: RoomStoredTree
        let previous: RoomStoredTree?
    }

    private let state: RoomStateStore
    private var index = Index()
    private var catalog = RoomTreeCatalog()
    private var approved: [String: URL] = [:]
    private var loading: Task<Index?, Never>?
    private var loaded = false
    private var generation: UInt64 = 0
    private var pending: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<String>.Continuation] = [:]

    init(state: RoomStateStore = .shared) { self.state = state }

    var changes: AsyncStream<String> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(16))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(id) }
        }
        return stream
    }

    func setApprovals(_ approvals: [String: URL]) { approved = approvals }

    func current(rootID: String) async -> RoomStoredTree? { await payload(rootID)?.current }
    func previous(rootID: String) async -> RoomStoredTree? { await payload(rootID)?.previous }

    func home() async -> RoomStoredTree? {
        await prepare()
        guard let rootID = index.homeRootID else { return nil }
        return await current(rootID: rootID)
    }

    func root(for id: String) async -> Root? {
        await prepare()
        return index.roots[id]
    }

    func lastOpened() async -> (current: RoomStoredTree, previous: RoomStoredTree?, root: Root)? {
        await prepare()
        guard let id = index.lastOpened, let root = index.roots[id], let value = await payload(id) else { return nil }
        return (value.current, value.previous, root)
    }

    func record(_ map: RoomStoredTree, location: RoomTreeLocation, isHome: Bool) async {
        await prepare()
        let id = map.rootID
        if catalog.entries[id] == nil, let existing = await payload(id) {
            if let previous = existing.previous { catalog.record(previous, now: previous.scannedAt) }
            catalog.record(existing.current, now: index.roots[id]?.lastUsed ?? existing.current.scannedAt)
        }
        if isHome { catalog.homeRootID = id }
        guard catalog.record(map, now: map.scannedAt), let entry = catalog.entries[id] else { return }
        if isHome { index.homeRootID = id }
        let changedAt = index.roots[id]?.changedAt.flatMap { $0 > map.scannedAt ? $0 : nil }
        index.roots[id] = Root(location: location, lastUsed: map.scannedAt, changedAt: changedAt)
        index.lastOpened = id
        var removed: [String] = []
        while index.roots.count > RoomTreeCatalog.maxRoots,
              let victim = index.roots.filter({ $0.key != index.homeRootID }).min(by: {
                  $0.value.lastUsed == $1.value.lastUsed ? $0.key < $1.key : $0.value.lastUsed < $1.value.lastUsed
              })?.key {
            index.roots[victim] = nil
            catalog.forget(victim)
            removed.append(victim)
        }
        enqueue(
            id: id,
            value: Payload(current: entry.current, previous: entry.previous),
            removing: removed
        )
        publish(id)
    }

    func open(_ rootID: String, at date: Date = .now) async {
        await prepare()
        guard index.roots[rootID] != nil else { return }
        index.roots[rootID]?.lastUsed = date
        index.lastOpened = rootID
        catalog.touch(rootID, now: date)
        enqueue()
    }

    func markChanged(under url: URL, at date: Date) async {
        await prepare()
        let path = url.standardizedFileURL.path
        let affected = index.roots.compactMap { id, entry -> String? in
            guard let base = approved[entry.location.approvalID], let root = entry.location.resolve(under: base),
                  RoomHomeMap.nests(root.standardizedFileURL.path, path) else { return nil }
            return id
        }
        guard !affected.isEmpty else { return }
        for id in affected {
            let previous = index.roots[id]?.changedAt ?? date
            index.roots[id]?.changedAt = max(previous, date)
            publish(id)
        }
        enqueue()
    }

    func forget(approvalID: String) async {
        await prepare()
        let removed = index.roots.compactMap { $0.value.location.approvalID == approvalID ? $0.key : nil }
        guard !removed.isEmpty else { return }
        for id in removed {
            index.roots[id] = nil
            catalog.forget(id)
            if index.homeRootID == id { index.homeRootID = nil; catalog.homeRootID = nil }
            publish(id)
        }
        if let last = index.lastOpened, removed.contains(last) {
            index.lastOpened = index.roots.max(by: { $0.value.lastUsed < $1.value.lastUsed })?.key
        }
        enqueue(removing: removed)
    }

    func flush() async { await pending?.value }

    /// Wait for ordered writes before the application's explicit history erasure.
    func clearMemory() async {
        await prepare()
        await flush()
        let ids = Array(index.roots.keys)
        index = Index()
        catalog = RoomTreeCatalog()
        for id in ids { publish(id) }
    }

    private func stopObserving(_ id: UUID) { observers[id] = nil }
    private func publish(_ rootID: String) { for observer in observers.values { observer.yield(rootID) } }

    private func prepare() async {
        guard !loaded else { return }
        if loading == nil {
            loading = Task { [state] in await state.load(Index.self, from: .treeIndex).value }
        }
        let stored = await loading?.value
        guard !loaded else { return }
        index = stored ?? Index()
        catalog.homeRootID = index.homeRootID
        loaded = true
        loading = nil
    }

    private func payload(_ id: String) async -> Payload? {
        await prepare()
        guard index.roots[id] != nil else { return nil }
        if let entry = catalog.entries[id] {
            return Payload(current: entry.current, previous: entry.previous)
        }
        return await state.load(Payload.self, from: .tree(rootID: id)).value
    }

    private func enqueue(id: String? = nil, value: Payload? = nil, removing: [String] = []) {
        generation += 1
        let index = index
        let generation = generation
        pending = Task { [state, previous = pending] in
            await previous?.value
            do {
                if let id, let value {
                    try await state.write(value, to: .tree(rootID: id), generation: generation)
                }
                try await state.write(index, to: .treeIndex, generation: generation)
                for id in removing { await state.remove(.tree(rootID: id)) }
            } catch {
                RoomStateStore.logger.error("Could not save a map: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
