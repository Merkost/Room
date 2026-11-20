import Foundation

/// Coalesces model updates on the main actor and writes through the state-store actor.
@MainActor
final class RoomStateWriter {
    static let shared = RoomStateWriter(store: .shared)

    let store: RoomStateStore
    private let debounce: Duration
    private var generations: [String: UInt64] = [:]
    private var pending: [String: Pending] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var active: [UUID: Running] = [:]
    private var isForgettingHistory = false

    private struct Running {
        let history: Bool
        let task: Task<Void, Never>
    }

    private struct Pending {
        let generation: UInt64
        let history: Bool
        let write: @Sendable () async -> Void
    }

    init(store: RoomStateStore, debounce: Duration = .seconds(1)) {
        self.store = store
        self.debounce = debounce
    }

    var hasPendingWrites: Bool { !pending.isEmpty || !active.isEmpty }

    func submit<Value: Codable & Sendable>(_ value: Value, to file: RoomStateFile) {
        guard !isForgettingHistory || file.survivesForget else { return }
        let generation = generations[file.name, default: 0] + 1
        generations[file.name] = generation
        pending[file.name] = Pending(generation: generation, history: !file.survivesForget) { [store] in
            do {
                try await store.write(value, to: file, generation: generation)
            } catch {
                RoomStateStore.logger.error("Could not write \(file.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
            }
        }

        timers[file.name]?.cancel()
        timers[file.name] = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, self.pending[file.name]?.generation == generation else { return }
            self.start(file.name)
        }
    }

    func discardPending(for file: RoomStateFile) {
        discardPending(named: file.name)
    }

    private func discardPending(named name: String) {
        pending[name] = nil
        timers.removeValue(forKey: name)?.cancel()
    }

    func forgetHistory(preparing: @escaping () async -> Void = {}, completion: @escaping ([String]) -> Void) {
        guard !isForgettingHistory else { return }
        isForgettingHistory = true
        for name in pending.filter({ $0.value.history }).keys { discardPending(named: name) }
        let previousWrites = active.values.filter(\.history).map(\.task)
        let id = UUID()
        let task = Task { [weak self, store] in
            await preparing()
            for write in previousWrites { await write.value }
            let forgotten = await store.forgetHistory()
            guard let self else { return }
            self.active[id] = nil
            self.isForgettingHistory = false
            completion(forgotten)
        }
        active[id] = Running(history: true, task: task)
    }

    func flush(deadline: Duration) async {
        for name in Array(pending.keys) { start(name) }
        let running = active.values.map(\.task)
        guard !running.isEmpty else { return }

        // Waiting for the deadline must not wait for a cancelled filesystem operation.
        let (result, done) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let completion = Task {
            for task in running { await task.value }
            done.yield(())
        }
        let timeout = Task {
            do { try await Task.sleep(for: deadline) } catch { return }
            done.yield(())
        }
        var iterator = result.makeAsyncIterator()
        _ = await iterator.next(isolation: #isolation)
        done.finish()
        completion.cancel()
        timeout.cancel()
    }

    private func start(_ name: String) {
        timers.removeValue(forKey: name)?.cancel()
        guard let entry = pending.removeValue(forKey: name) else { return }
        let id = UUID()
        let task = Task { [weak self] in
            await entry.write()
            self?.active[id] = nil
        }
        active[id] = Running(history: entry.history, task: task)
    }
}

extension Notification.Name {
    static let roomSavedHistoryForgotten = Notification.Name("RoomSavedHistoryForgotten")
}
