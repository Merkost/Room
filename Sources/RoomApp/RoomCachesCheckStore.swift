import Foundation
import Observation

/// Keeps the last completed scan separate from the in-progress Caches review.
@Observable @MainActor
final class RoomCachesCheckStore {
    private(set) var check: RoomCachesCheck?
    private(set) var invalidatedAt: Date?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let writer: RoomStateWriter?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var readOnly = false

    init(defaults: UserDefaults = .standard, writer: RoomStateWriter? = nil) {
        self.defaults = defaults
        self.writer = writer
        let keys = RoomLegacyCachesCheck.keys
        let legacy = RoomLegacyCachesCheck.read(at: defaults.object(forKey: keys.at),
            bytes: defaults.object(forKey: keys.bytes), partial: defaults.object(forKey: keys.partial),
            invalidatedAt: defaults.object(forKey: keys.invalidatedAt), now: Date())
        if let writer {
            loading = Task { [weak self] in
                let stored = await writer.store.load(RoomReports.self, from: .reports)
                guard let self else { return }
                if stored.isReadOnly { self.readOnly = true }
                guard self.revision == 0 else { return }
                if let payload = stored.value {
                    self.apply(payload)
                } else if case .missing = stored, !self.defaults.bool(forKey: Self.migrationFlag) {
                    do {
                        if let legacy {
                            let payload = RoomReports(caches: legacy)
                            let migrated = try await writer.store.writeIfMissing(payload, to: .reports)
                            if migrated, self.revision == 0 { self.apply(payload) }
                        }
                        self.defaults.set(true, forKey: Self.migrationFlag)
                    } catch {
                        RoomStateStore.logger.error("Could not migrate cache check: \(error.localizedDescription, privacy: .private)")
                    }
                }
            }
        } else {
            // A preferences-only store remains useful for isolated clients that do not have a state directory.
            apply(.init(caches: legacy, invalidatedAt: defaults.object(forKey: keys.invalidatedAt) as? Date))
        }
    }

    private static let migrationFlag = "RoomStateMigratedV1"

    func waitForLoad() async { await loading?.value }

    func save(_ check: RoomCachesCheck) {
        guard !readOnly else { return }
        revision += 1
        self.check = check
        persist()
    }

    func invalidate(at date: Date) {
        guard !readOnly else { return }
        if let invalidatedAt, date <= invalidatedAt { return }
        revision += 1
        invalidatedAt = date
        persist()
    }

    func clearInMemory() {
        revision += 1
        check = nil
        invalidatedAt = nil
        writer?.discardPending(for: .reports)
    }

    private func apply(_ reports: RoomReports) {
        check = reports.caches.map { RoomCachesCheck(at: $0.at, bytes: $0.bytes, partial: $0.partial) }
        invalidatedAt = reports.invalidatedAt ?? reports.caches?.invalidatedAt
    }

    private func persist() {
        let record = check.map { RoomLegacyCachesCheck(at: $0.at, bytes: $0.bytes, partial: $0.partial, invalidatedAt: invalidatedAt) }
        if let writer {
            writer.submit(RoomReports(caches: record, invalidatedAt: invalidatedAt), to: .reports)
        } else {
            let keys = RoomLegacyCachesCheck.keys
            if let check {
                defaults.set(check.bytes, forKey: keys.bytes)
                defaults.set(check.partial, forKey: keys.partial)
                defaults.set(check.at, forKey: keys.at)
            }
            defaults.set(invalidatedAt, forKey: keys.invalidatedAt)
        }
    }
}
