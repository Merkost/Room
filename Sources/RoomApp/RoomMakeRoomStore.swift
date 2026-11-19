import AppKit
import Darwin
import Foundation
import Observation
import RoomCore

@Observable @MainActor
final class RoomMakeRoomStore {
    private(set) var entries: [RoomMakeRoomEntry] = []
    private(set) var hadWriteFailure = false
    @ObservationIgnored var didObserveGain: ((RoomMakeRoomEntry) -> Void)?
    @ObservationIgnored private let state: RoomStateStore
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let sample: @Sendable () async -> RoomCapacitySample?
    @ObservationIgnored private var receipts: [UUID: ActivityReceipt] = [:]
    @ObservationIgnored private var loading: Task<RoomStateLoad<[RoomMakeRoomEntry]>, Never>?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var receiptRevision: UInt64 = 0

    init(state: RoomStateStore = .shared, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         sample: @escaping @Sendable () async -> RoomCapacitySample? = RoomMakeRoomStore.readSample) {
        self.state = state
        self.home = home
        self.sample = sample
    }

    var summary: RoomHistorySummary { RoomHistorySummary.make(entries) }
    var latest: RoomMakeRoomEntry? { entries.max { $0.movedAt < $1.movedAt } }

    func entry(for receiptID: UUID) -> RoomMakeRoomEntry? { entries.first { $0.id == receiptID } }

    func returnedBytes(since mapDate: Date?) -> Int64 {
        entries.lazy.filter { $0.lastChangedAt > (mapDate ?? .distantPast) }
            .reduce(0) { $0 + $1.observedGain }
    }

    func recordMove(receipt: ActivityReceipt) async {
        guard receipt.trashedCount > 0 else { return }
        let measured = await sample()
        await load()
        let devices = Set(receipt.items.filter { $0.status == .trashed }.map(\.originalIdentity.device))
        guard let entry = RoomMakeRoomEntry.stageOne(receiptID: receipt.id, movedAt: receipt.date,
            movedBytes: receipt.trashedBytes, itemCount: receipt.trashedCount,
            itemsDevice: devices.count == 1 ? devices.first : nil, sample: measured) else { return }
        receipts[receipt.id] = receipt
        receiptRevision &+= 1
        entries.removeAll { $0.id == receipt.id }
        entries.append(entry)
        await save()
        scheduleCheck()
    }

    func updateReceipts(_ history: [ActivityReceipt]) async {
        await load()
        for receipt in history { receipts[receipt.id] = receipt }
        receiptRevision &+= 1
        let known = Set(entries.map(\.id))
        let adopted = history.filter { !known.contains($0.id) }.compactMap {
            RoomMakeRoomEntry.adopted(receiptID: $0.id, movedAt: $0.date, movedBytes: $0.trashedBytes, itemCount: $0.trashedCount)
        }
        if !adopted.isEmpty {
            entries.append(contentsOf: adopted)
            await save()
        }
        scheduleCheck()
    }

    func checkNow() async {
        await load()
        guard !checking, RoomMakeRoomLedger.needsChecks(entries) else { return }
        checking = true
        defer { checking = false; scheduleCheck() }
        let revision = receiptRevision
        let observed = entries.filter { $0.isObserved && $0.stage != .unobservable }.compactMap { receipts[$0.id] }
        guard !observed.isEmpty, let measurement = await sample() else { return }
        let observations = await Self.probe(observed, home: home)
        guard revision == receiptRevision else { return }
        let next = RoomMakeRoomLedger.advance(entries, observations: observations, sample: measurement, now: measurement.at)
        guard next != entries else { return }
        let previousGains = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.observedGain) })
        entries = next
        await save()
        for entry in next where entry.observedGain > (previousGains[entry.id] ?? 0) {
            didObserveGain?(entry)
        }
    }

    private func load() async {
        guard !loaded else { return }
        if loading == nil {
            loading = Task { [state] in await state.load([RoomMakeRoomEntry].self, from: .ledger) }
        }
        let result = await loading?.value
        guard !loaded else { return }
        if case .loaded(let entries, _) = result { self.entries = entries }
        loaded = true
        loading = nil
    }

    private func save() async {
        generation &+= 1
        do { try await state.write(entries, to: .ledger, generation: generation) }
        catch { hadWriteFailure = true }
    }

    private func scheduleCheck() {
        guard RoomMakeRoomLedger.needsChecks(entries) else {
            checkTask?.cancel()
            checkTask = nil
            return
        }
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(RoomMakeRoomLedger.checkInterval)) }
            catch { return }
            self?.checkTask = nil
            await self?.checkNow()
        }
    }

    @concurrent private static func probe(_ receipts: [ActivityReceipt], home: URL) async -> [UUID: RoomTrashObservation] {
        var observations: [UUID: RoomTrashObservation] = [:]
        for receipt in receipts {
            observations[receipt.id] = RoomTrashProbe.observation(receipt, home: home)
        }
        return observations
    }

    @concurrent nonisolated static func readSample() async -> RoomCapacitySample? {
        guard let capacity = try? RoomVolumeCapacity.read() else { return nil }
        var attributes = stat()
        guard lstat(FileManager.default.homeDirectoryForCurrentUser.path, &attributes) == 0 else { return nil }
        return .init(freeBytes: capacity.freeBytes, device: UInt64(UInt32(bitPattern: attributes.st_dev)), at: Date())
    }
}
