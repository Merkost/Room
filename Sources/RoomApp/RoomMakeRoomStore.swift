import AppKit
import Darwin
import Foundation
import Observation
import OSLog
import RoomCore

@Observable @MainActor
final class RoomMakeRoomStore {
    private var storedEntries: [RoomMakeRoomEntry] = []
    #if DEBUG
    private var simulatedEntries: [RoomMakeRoomEntry]?
    #endif

    var entries: [RoomMakeRoomEntry] {
        #if DEBUG
        simulatedEntries ?? storedEntries
        #else
        storedEntries
        #endif
    }
    private(set) var hasReadReceipts = false
    private(set) var hadWriteFailure = false
    /// The last save error while `hadWriteFailure` is set; nil after the next successful save.
    private(set) var writeFailureMessage: String?
    @ObservationIgnored var didObserveGain: ((RoomMakeRoomEntry) -> Void)?
    @ObservationIgnored private let state: RoomStateStore
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let sample: @Sendable () async -> RoomCapacitySample?
    @ObservationIgnored private var receipts: [UUID: ActivityReceipt] = [:]
    @ObservationIgnored private var prunedIDs: [UUID] = []
    @ObservationIgnored private static let maxPrunedIDs = 2000
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
            .reduce(0) { $0 + Self.reportedGain($1) }
    }

    func recordMove(receipt: ActivityReceipt) async {
        guard receipt.trashedCount > 0 else { return }
        let measured = receipt.finalWriteFailed ? nil : await sample()
        await load()
        let devices = Set(receipt.items.filter { $0.status == .trashed }.map(\.originalIdentity.device))
        guard let entry = RoomMakeRoomEntry.stageOne(receiptID: receipt.id, movedAt: receipt.date,
            movedBytes: receipt.trashedBytes, itemCount: receipt.trashedCount,
            itemsDevice: devices.count == 1 ? devices.first : nil, sample: measured) else { return }
        receipts[receipt.id] = receipt
        receiptRevision &+= 1
        storedEntries.removeAll { $0.id == receipt.id }
        storedEntries.append(entry)
        await save()
        scheduleCheck()
    }

    func updateReceipts(_ history: [ActivityReceipt]) async {
        await load()
        for receipt in history { receipts[receipt.id] = receipt }
        receiptRevision &+= 1
        hasReadReceipts = true
        let known = Set(storedEntries.map(\.id)).union(prunedIDs)
        let adopted = history.filter { !known.contains($0.id) }.compactMap {
            RoomMakeRoomEntry.adopted(receiptID: $0.id, movedAt: $0.date, movedBytes: $0.trashedBytes, itemCount: $0.trashedCount)
        }
        if !adopted.isEmpty {
            storedEntries.append(contentsOf: adopted)
            await save()
        }
        hasReadReceipts = true
        scheduleCheck()
    }

    func checkNow() async {
        await load()
        guard !checking, RoomMakeRoomLedger.needsChecks(storedEntries) else { return }
        checking = true
        defer { checking = false; scheduleCheck() }
        let revision = receiptRevision
        let observed = storedEntries.filter { $0.isObserved && $0.stage != .unobservable }.compactMap { receipts[$0.id] }
        guard !observed.isEmpty, let measurement = await sample() else { return }
        let observations = await Self.probe(observed, home: home)
        guard revision == receiptRevision else { return }
        let next = RoomMakeRoomLedger.advance(storedEntries, observations: observations, sample: measurement, now: measurement.at)
        guard next != storedEntries else { return }
        let previousGains = Dictionary(uniqueKeysWithValues: storedEntries.map { ($0.id, Self.reportedGain($0)) })
        storedEntries = next
        await save()
        for entry in next where Self.reportedGain(entry) > (previousGains[entry.id] ?? 0) {
            didObserveGain?(entry)
        }
    }

    #if DEBUG
    func simulateTrash(at now: Date = Date()) async {
        await load()
        guard let simulation = RoomDebugTrashSimulator.simulate(storedEntries, now: now) else { return }
        let virtual = RoomMakeRoomLedger.advance(
            storedEntries, observations: simulation.observations, sample: simulation.sample, now: now
        )
        simulatedEntries = virtual
        let realGains = Dictionary(uniqueKeysWithValues: storedEntries.map { ($0.id, Self.reportedGain($0)) })
        if let gain = virtual.first(where: { Self.reportedGain($0) > (realGains[$0.id] ?? 0) }) {
            didObserveGain?(gain)
        }
    }

    func resetSimulatedTrash() { simulatedEntries = nil }
    #endif

    private func load() async {
        guard !loaded else { return }
        if loading == nil {
            loading = Task { [state] in await state.load([RoomMakeRoomEntry].self, from: .ledger) }
        }
        let result = await loading?.value
        guard !loaded else { return }
        if case .loaded(let entries, _) = result { self.storedEntries = entries }
        if case .loaded(let ids, _) = await state.load([UUID].self, from: .ledgerPruned) { prunedIDs = ids }
        loaded = true
        loading = nil
    }

    private static func reportedGain(_ entry: RoomMakeRoomEntry) -> Int64 {
        switch entry.stage {
        case .emptied, .partlyEmptied: entry.observedGain
        default: 0
        }
    }

    private func save() async {
        generation &+= 1
        if hasReadReceipts {
            let known = receipts
            let kept = RoomMakeRoomLedger.pruned(storedEntries, now: Date()) { known[$0]?.canRestore ?? false }
            if kept.count != storedEntries.count {
                let keptIDs = Set(kept.map(\.id))
                prunedIDs = Array((prunedIDs + storedEntries.map(\.id).filter { !keptIDs.contains($0) }).suffix(Self.maxPrunedIDs))
                storedEntries = kept
                do { try await state.write(prunedIDs, to: .ledgerPruned, generation: generation) }
                catch {
                    Logger(subsystem: "com.merkost.room", category: "ledger")
                        .error("Could not save ledger-pruned.json: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        do {
            try await state.write(storedEntries, to: .ledger, generation: generation)
            hadWriteFailure = false
            writeFailureMessage = nil
        } catch {
            hadWriteFailure = true
            writeFailureMessage = error.localizedDescription
            Logger(subsystem: "com.merkost.room", category: "ledger")
                .error("Could not save ledger.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleCheck() {
        guard RoomMakeRoomLedger.needsChecks(storedEntries) else {
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
