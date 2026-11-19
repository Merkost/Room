import Foundation

nonisolated struct RoomStoredFile<Payload: Codable & Sendable>: Codable, Sendable {
    var schema: Int
    var writtenAt: Date
    var appVersion: String
    var payload: Payload
}

/// One persisted concern under `Application Support/Room/State/`. Each job owns the schema of its own files;
/// Job A owns this type, the directory and the rules every file follows.
nonisolated struct RoomStateFile: Hashable, Sendable {
    let name: String            // file name inside State/ (a subfolder is allowed for trees)
    let schema: Int             // the schema this build writes
    let maxBytes: Int           // a write larger than this is refused (02 §12: all state ≤ 2 MB)
    let survivesForget: Bool    // DP-9 and D-FND-6: kept by "Forget history…"

    // Owned by Job A
    static let rooms = RoomStateFile(name: "rooms.json", schema: 1, maxBytes: 128_000, survivesForget: true)
    static let roomSizes = RoomStateFile(name: "room-sizes.json", schema: 1, maxBytes: 512_000, survivesForget: false)
    static let volumeSamples = RoomStateFile(name: "snapshots.json", schema: 1, maxBytes: 256_000, survivesForget: false)
    static let reports = RoomStateFile(name: "reports.json", schema: 1, maxBytes: 128_000, survivesForget: false)
    static let weeklyCheck = RoomStateFile(name: "weekly-check.json", schema: 1, maxBytes: 4_000, survivesForget: false)
    // Named here so names never collide; schemas are owned by Jobs B, C, D (ASSUMED there).
    static let ledger = RoomStateFile(name: "ledger.json", schema: 1, maxBytes: 256_000, survivesForget: true)
    static let ignore = RoomStateFile(name: "ignore.json", schema: 1, maxBytes: 128_000, survivesForget: true)
    static let views = RoomStateFile(name: "views.json", schema: 1, maxBytes: 64_000, survivesForget: true)
    static let pressure = RoomStateFile(name: "pressure.json", schema: 1, maxBytes: 512_000, survivesForget: false)
    static func tree(rootID: String) -> RoomStateFile {
        // rootID is a RoomFileAccess record id (Store) or a SHA-256 hex (Direct): never a path.
        let safe = String(rootID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(80))
        return RoomStateFile(name: "trees/\(safe).json", schema: 1, maxBytes: 1_500_000, survivesForget: false)
    }
}

/// What the bytes on disk are, before anything is decoded into a payload.
nonisolated enum RoomStateClassification: Equatable, Sendable {
    case legacy                 // valid JSON without an envelope: a 1.x / pre-store file (rooms.json was a bare array)
    case current
    case older(Int)
    case newer(Int)
    case corrupt
}

/// The outcome a model receives. It never throws and never blocks launch (04 §5).
nonisolated enum RoomStateLoad<Payload: Sendable>: Sendable {
    case missing                                 // empty state, no message
    case loaded(Payload, rewrite: Bool)          // rewrite = write it back once in the current envelope
    case damaged                                 // the caller moves the file aside, starts empty, Settings shows one line
    case newerReadOnly(Payload?)                 // a newer build wrote it: never overwrite; payload only if it still decodes

    var value: Payload? {
        switch self {
        case .loaded(let payload, _): payload
        case .newerReadOnly(let payload): payload
        case .missing, .damaged: nil
        }
    }

    var isReadOnly: Bool {
        if case .newerReadOnly = self { return true }
        return false
    }
}

nonisolated enum RoomStateCodec {
    private struct Header: Decodable { let schema: Int; let writtenAt: Date; let appVersion: String }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]                       // DP-7: stable diffs
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func classify(_ data: Data, currentSchema: Int) -> RoomStateClassification {
        guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { return .corrupt }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["payload"] != nil {
            guard let header = try? decoder().decode(Header.self, from: data), header.schema >= 0 else { return .corrupt }
            if header.schema == currentSchema { return .current }
            return header.schema < currentSchema ? .older(header.schema) : .newer(header.schema)
        }
        return .legacy
    }

    /// `legacy` reads a pre-envelope file; `migrate` lifts an older envelope's raw payload (schema n) to the current one.
    static func decode<Payload: Codable & Sendable>(
        _ data: Data?, as type: Payload.Type, file: RoomStateFile,
        legacy: ((Data) throws -> Payload)? = nil,
        migrate: ((Int, Data) throws -> Payload)? = nil) -> RoomStateLoad<Payload> {
        guard let data else { return .missing }
        switch classify(data, currentSchema: file.schema) {
        case .corrupt: return .damaged
        case .current:
            guard let file = try? decoder().decode(RoomStoredFile<Payload>.self, from: data) else { return .damaged }
            return .loaded(file.payload, rewrite: false)
        case .legacy:
            guard let legacy, let value = try? legacy(data) else { return .damaged }
            return .loaded(value, rewrite: true)
        case .older(let n):
            guard let migrate, let value = try? migrate(n, data) else { return .damaged }
            return .loaded(value, rewrite: true)
        case .newer:
            return .newerReadOnly((try? decoder().decode(RoomStoredFile<Payload>.self, from: data))?.payload)
        }
    }

    /// Encodes the envelope; refuses a payload over the file's cap rather than writing a partial or giant file.
    static func encode<Payload: Codable & Sendable>(_ payload: Payload, file: RoomStateFile,
                                                    writtenAt: Date, appVersion: String) throws -> Data {
        let data = try encoder().encode(RoomStoredFile(schema: file.schema, writtenAt: writtenAt,
                                                       appVersion: appVersion, payload: payload))
        guard data.count <= file.maxBytes else { throw RoomStateError.tooLarge(file.name, data.count) }
        return data
    }
}

nonisolated enum RoomStateError: Error, Equatable, Sendable {
    case tooLarge(String, Int)
    case readOnlyNewerSchema(String)
    case unsafeLocation(String)
}

/// `State/Damaged/<stem>-<UTC stamp>.json`, keep the newest three per file (04 §5). No colons: Finder-safe.
nonisolated enum RoomStateDamaged {
    static let keep = 3
    static func name(for file: RoomStateFile, at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stem = file.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".json", with: "")
        return "\(stem)-\(f.string(from: date)).json"
    }
    /// Names to delete after a new damaged copy was added; only this file's copies are considered.
    static func toDelete(existing: [String], for file: RoomStateFile) -> [String] {
        let stem = file.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".json", with: "")
        let mine = existing.filter { $0.hasPrefix(stem + "-") && $0.hasSuffix(".json") }.sorted()
        return Array(mine.dropLast(keep))
    }
}

/// Models call `submit` from the main actor; the actor may receive two writes for one file out of order
/// (two `Task`s). A per-file generation stamped on the main actor makes the newest value win (D-FND-5).
nonisolated struct RoomStateWriteGate: Sendable {
    private(set) var written: [String: UInt64] = [:]
    /// True if this write should reach disk; a stale generation is dropped.
    mutating func admit(_ file: RoomStateFile, generation: UInt64) -> Bool {
        if let last = written[file.name], generation <= last { return false }
        written[file.name] = generation
        return true
    }
}

/// DP-9 amended (D-FND-6): Forget history removes measurements, never what Restore or approvals need.
nonisolated enum RoomStateForget {
    static func filesToRemove(present: [RoomStateFile]) -> [RoomStateFile] {
        present.filter { !$0.survivesForget }
    }
}

/// One-time copy of 1.x defaults into `reports.json` (FOUNDATION-SPEC §4.4). The legacy keys stay readable for
/// a downgrade but are never written again by 2.0 code.
nonisolated struct RoomLegacyCachesCheck: Codable, Equatable, Sendable {
    var at: Date
    var bytes: Int64
    var partial: Bool
    var invalidatedAt: Date?

    static let keys = (at: "RoomLastCachesCheckAt", bytes: "RoomLastCachesCheckBytes",
                       partial: "RoomLastCachesCheckPartial", invalidatedAt: "RoomOverviewCachesInvalidatedAt")

    /// All three core keys must be present and sane; otherwise nothing is migrated (never a zero summary).
    static func read(at: Any?, bytes: Any?, partial: Any?, invalidatedAt: Any?, now: Date) -> RoomLegacyCachesCheck? {
        guard let at = at as? Date, let number = bytes as? NSNumber, let partial = partial as? Bool else { return nil }
        let value = number.int64Value
        guard value >= 0, at <= now else { return nil }
        return .init(at: at, bytes: value, partial: partial, invalidatedAt: invalidatedAt as? Date)
    }
}

/// reports.json: one optional summary per tool. Job A owns the container and `caches` until Job C's richer
/// report replaces it (schema 2, owned by Job C); `diskMap`, `developer`, `memory` stay nil until B / D add them.
nonisolated struct RoomReports: Codable, Equatable, Sendable {
    var caches: RoomLegacyCachesCheck?
    var invalidatedAt: Date? = nil
}
