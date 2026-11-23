import Foundation

nonisolated enum RoomPressureLevel: Int, Codable, Comparable, Sendable, CaseIterable {
    case normal = 0, elevated = 1, critical = 2
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    /// MemoryPressure.rawValue from RoomCore; "unknown" (and anything else) is dropped, not counted as normal.
    init?(memoryPressureRaw raw: String) {
        switch raw { case "normal": self = .normal; case "elevated": self = .elevated; case "critical": self = .critical; default: return nil }
    }
    var word: String { switch self { case .normal: "Normal"; case .elevated: "Elevated"; case .critical: "Critical" } }
    var title: String { "\(word) pressure" }
    /// Pocket fill for RoomPocketShape: hollow / half / full (shape carries the level, colour confirms).
    var pocketFill: Double { switch self { case .normal: 0; case .elevated: 0.5; case .critical: 1 } }
}

nonisolated struct RoomPressureBucket: Codable, Equatable, Sendable {
    var index: Int64             // floor(epoch seconds / bucketSeconds)
    var worst: RoomPressureLevel
    var usedSum: Double
    var count: Int
    var lastSwapBytes: Int64?
    var meanUsedBytes: Int64 { count > 0 ? Int64(clamping: UInt64(usedSum / Double(count))) : 0 }
}

/// One fixed-resolution series. Board v4 draws 24 h at 15 min (96 columns) and 7 d at 2 h (84 columns).
nonisolated struct RoomPressureSeries: Codable, Equatable, Sendable {
    let bucketSeconds: Int64
    let capacity: Int
    private(set) var buckets: [RoomPressureBucket] = []    // ascending index, no duplicates

    init(bucketSeconds: Int64, capacity: Int) { self.bucketSeconds = bucketSeconds; self.capacity = capacity }

    func bucketIndex(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 / Double(bucketSeconds)).rounded(.down)) }

    mutating func record(_ level: RoomPressureLevel, usedBytes: Int64?, swapBytes: Int64?, at date: Date) {
        let i = bucketIndex(date)
        if let last = buckets.last, i < last.index { return }          // clock went backwards: ignored
        if let last = buckets.last, last.index == i {
            var b = last
            b.worst = max(b.worst, level)
            if let used = usedBytes, used > 0 { b.usedSum += Double(used); b.count += 1 }
            if let swapBytes { b.lastSwapBytes = swapBytes }
            buckets[buckets.count - 1] = b
        } else {
            let used = usedBytes.flatMap { $0 > 0 ? $0 : nil }
            buckets.append(.init(index: i, worst: level, usedSum: used.map(Double.init) ?? 0, count: used == nil ? 0 : 1, lastSwapBytes: swapBytes))
        }
        let floor = i - Int64(capacity) + 1
        buckets.removeAll { $0.index < floor }
    }

    /// Exactly `capacity` columns ending with the bucket that contains `now`; nil = Room wasn't running (or asleep).
    func columns(now: Date) -> [RoomPressureBucket?] {
        let end = bucketIndex(now), start = end - Int64(capacity) + 1
        let byIndex = Dictionary(uniqueKeysWithValues: buckets.map { ($0.index, $0) })
        return (start...end).map { byIndex[$0] }
    }

    func start(of index: Int64) -> Date { Date(timeIntervalSince1970: Double(index) * Double(bucketSeconds)) }
}

nonisolated struct RoomPressureHistory: Codable, Equatable, Sendable {
    static let dayBucket: Int64 = 900, dayCount = 96       // 24 h · every 15 minutes
    static let weekBucket: Int64 = 7_200, weekCount = 84   // 7 days · every 2 hours
    var day = RoomPressureSeries(bucketSeconds: dayBucket, capacity: dayCount)
    var week = RoomPressureSeries(bucketSeconds: weekBucket, capacity: weekCount)

    /// Fed from the existing 20 s monitor scan and from Memory-screen scans (one sampling path, ME-1).
    mutating func record(pressureRaw: String, usedBytes: Int64?, swapBytes: Int64?, at date: Date) {
        guard let level = RoomPressureLevel(memoryPressureRaw: pressureRaw) else { return }
        day.record(level, usedBytes: usedBytes, swapBytes: swapBytes, at: date)
        week.record(level, usedBytes: usedBytes, swapBytes: swapBytes, at: date)
    }
}

// MARK: - Finding sentence (ME-6) and episodes

nonisolated enum RoomPressureFinding {
    nonisolated struct Episodes: Equatable, Sendable { let elevated: Int; let critical: Int }

    /// A run is consecutive measured buckets at or above the level; a gap ends a run (we cannot say it continued).
    static func episodes(_ columns: [RoomPressureBucket?]) -> Episodes {
        var elevated = 0, critical = 0, inE = false, inC = false
        for c in columns {
            let lvl = c?.worst
            let e = lvl == .elevated, k = lvl == .critical
            if e && !inE { elevated += 1 }
            if k && !inC { critical += 1 }
            inE = e; inC = k
        }
        return .init(elevated: elevated, critical: critical)
    }

    /// Start of the current level's run. `boundedByRecord` is true when the bucket before is a gap or outside the
    /// record: Room only knows "since it started looking", and must say so rather than imply a change.
    static func currentRun(_ columns: [RoomPressureBucket?]) -> (level: RoomPressureLevel, startIndex: Int64, boundedByRecord: Bool)? {
        guard let last = columns.last ?? nil else { return nil }
        var start = last.index, bounded = true
        for c in columns.reversed().dropFirst() {
            guard let c else { bounded = true; break }
            if c.worst != last.worst { bounded = false; break }
            start = c.index
        }
        if columns.first.flatMap({ $0 })?.index == start { bounded = true }
        return (last.worst, start, bounded)
    }

    static func sentence(_ series: RoomPressureSeries, now: Date, rangeName: String, time: (Date) -> String) -> String {
        let cols = series.columns(now: now)
        guard let run = currentRun(cols) else {
            return cols.allSatisfy({ $0 == nil }) ? "Room starts keeping a 24-hour record now." : "Room can't read memory pressure right now. Activity Monitor can."
        }
        let at = time(series.start(of: run.startIndex))
        let lead = run.boundedByRecord ? "\(run.level.word) since \(at), when this record starts." : "\(run.level.word) since \(at)."
        let ep = episodes(cols)
        let tail: String
        switch (ep.elevated, ep.critical) {
        case (0, 0): tail = "No Elevated or Critical episodes in the \(rangeName)."
        case (let e, 0): tail = "\(e) Elevated episode\(e == 1 ? "" : "s") in the \(rangeName), none Critical."
        case (0, let k): tail = "No Elevated episodes in the \(rangeName), \(k) Critical."
        case (let e, let k): tail = "\(e) Elevated episode\(e == 1 ? "" : "s") and \(k) Critical in the \(rangeName)."
        }
        return lead + " " + tail + " High use is normal on a Mac; pressure is what tells you when to act."
    }

    /// Scrub readout (ME-3 timeline): "Thu 16:20 · Elevated for 45 min" or "Thu 03:00 · Room wasn't running".
    static func readout(_ columns: [RoomPressureBucket?], at i: Int, bucketSeconds: Int64, label: String) -> String {
        guard columns.indices.contains(i) else { return label }
        guard let b = columns[i] else { return "\(label) · Room wasn't running" }
        var j = i
        while j > 0, let p = columns[j - 1], p.worst == b.worst { j -= 1 }
        let minutes = Int64(i - j + 1) * bucketSeconds / 60
        let span = minutes >= 120 ? "\(minutes / 60) h" : "\(minutes) min"
        return "\(label) · \(b.worst.word) for \(span)"
    }
}

// MARK: - In use: Current and Average with an honest window (ME-9)

nonisolated enum RoomMemoryInUse {
    /// Average over the samples of the last hour; the caption names the window actually covered.
    /// Requires timestamps (the popover's RoomMemorySampleRing gains `at`; see MEMORY §3 in DMR spec).
    static func average(_ samples: [(at: Date, bytes: Int64)], now: Date) -> (bytes: Int64, caption: String)? {
        let window = samples.filter { $0.bytes > 0 && $0.at <= now && now.timeIntervalSince($0.at) <= 3_600 }
        guard window.count >= 3, let oldest = window.map(\.at).min() else { return nil }
        let mean = window.reduce(0.0) { $0 + Double($1.bytes) } / Double(window.count)
        let minutes = Int(now.timeIntervalSince(oldest) / 60)
        return (Int64(clamping: UInt64(mean)), minutes >= 50 ? "last hour" : "last \(max(1, minutes)) min")
    }
}

/// The standalone pressure record is small, app-owned and contains no paths or process data.
struct RoomPressureHistoryStore {
    let directory: URL

    init(directory: URL = RoomRoomsStore.defaultDirectory) { self.directory = directory }

    private var file: URL { directory.appendingPathComponent("memory-pressure.json") }

    func load() -> RoomPressureHistory {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128 * 1_024,
              let data = try? Data(contentsOf: file),
              let history = try? JSONDecoder().decode(RoomPressureHistory.self, from: data),
              Self.isValid(history) else {
            return RoomPressureHistory()
        }
        return history
    }

    func save(_ history: RoomPressureHistory) {
        do {
            let data = try JSONEncoder().encode(history)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            // Keep the in-memory record available when app-owned storage is unwritable.
        }
    }

    nonisolated static func isValid(_ history: RoomPressureHistory) -> Bool {
        isValid(history.day, seconds: RoomPressureHistory.dayBucket, count: RoomPressureHistory.dayCount)
            && isValid(history.week, seconds: RoomPressureHistory.weekBucket, count: RoomPressureHistory.weekCount)
    }

    private nonisolated static func isValid(_ series: RoomPressureSeries, seconds: Int64, count: Int) -> Bool {
        guard series.bucketSeconds == seconds, series.capacity == count,
              series.buckets.count <= count else { return false }
        var previous: Int64?
        for bucket in series.buckets {
            if let previous, previous >= bucket.index { return false }
            let mean = bucket.usedSum / Double(max(1, bucket.count))
            guard bucket.count >= 0, mean.isFinite, mean >= 0, mean <= Double(Int64.max),
                  bucket.lastSwapBytes.map({ $0 >= 0 }) != false else { return false }
            previous = bucket.index
        }
        return true
    }
}
