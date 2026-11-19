import Foundation
import Observation

/// Keeps the last completed scan separate from the in-progress Caches review.
@Observable @MainActor
final class RoomCachesCheckStore {
    private var savedCheck: RoomCachesCheck?
    private var savedInvalidatedAt: Date?
    private var historySuspended = false
    var check: RoomCachesCheck? { historySuspended ? nil : savedCheck }
    var invalidatedAt: Date? { historySuspended ? nil : savedInvalidatedAt }
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
        self.savedCheck = check
        persist()
    }

    func invalidateBeforeFileChange(at date: Date) async {
        invalidate(at: date)
        await writer?.flush(deadline: .milliseconds(500))
    }

    func invalidate(at date: Date) {
        guard !readOnly else { return }
        if let savedInvalidatedAt, date <= savedInvalidatedAt { return }
        revision += 1
        savedInvalidatedAt = date
        persist()
    }

    func suspendHistory(_ suspended: Bool) { historySuspended = suspended }

    func clearInMemory() {
        revision += 1
        savedCheck = nil
        savedInvalidatedAt = nil
        writer?.discardPending(for: .reports)
    }

    private func apply(_ reports: RoomReports) {
        savedCheck = reports.caches.map { RoomCachesCheck(at: $0.at, bytes: $0.bytes, partial: $0.partial) }
        savedInvalidatedAt = reports.invalidatedAt ?? reports.caches?.invalidatedAt
    }

    private func persist() {
        let record = savedCheck.map { RoomLegacyCachesCheck(at: $0.at, bytes: $0.bytes, partial: $0.partial, invalidatedAt: savedInvalidatedAt) }
        if let writer {
            writer.submit(RoomReports(caches: record, invalidatedAt: savedInvalidatedAt), to: .reports)
        } else {
            let keys = RoomLegacyCachesCheck.keys
            if let check = savedCheck {
                defaults.set(check.bytes, forKey: keys.bytes)
                defaults.set(check.partial, forKey: keys.partial)
                defaults.set(check.at, forKey: keys.at)
            }
            defaults.set(savedInvalidatedAt, forKey: keys.invalidatedAt)
        }
    }
}
