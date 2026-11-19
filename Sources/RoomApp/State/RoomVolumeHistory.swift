import Foundation
import Observation

/// One capacity reading as `RoomVolumeCapacity` produced it, plus the volume's identity when macOS gave one.
nonisolated struct RoomVolumeSample: Codable, Equatable, Sendable {
    var at: Date
    var capacityBytes: Int64
    var freeBytes: Int64
    var volumeID: String?          // URLResourceKey.volumeUUIDStringKey; nil = unknown, never compared as equal

    /// Same rule as RoomVolumeCapacity: only a sane reading is ever recorded.
    var isValid: Bool { capacityBytes > 0 && freeBytes >= 0 && freeBytes <= capacityBytes }
    func sameVolume(as other: RoomVolumeSample) -> Bool {
        guard let a = volumeID, let b = other.volumeID else { return false }
        return a == b && capacityBytes == other.capacityBytes
    }
}

/// The last sample of one Monday-week. Kind totals only from a complete home map that week (never zeros, never a guess).
nonisolated struct RoomVolumeWeek: Codable, Equatable, Sendable {
    var weekStart: Date
    var last: RoomVolumeSample
    var kindBytes: [String: Int64]?        // StorageKind raw value → bytes; nil = not mapped that week
}

nonisolated enum RoomVolumeTrigger: Sendable { case launch, activation, monitorTick, scanCompleted }

nonisolated enum RoomVolumeChange: Equatable, Sendable {
    case tracking                                   // nothing earlier this week (or last week) to compare with
    case volumeChanged                              // the baseline was another volume or capacity: no delta
    case since(label: String, usedBytes: Int64)     // baseline.free − latest.free; negative = free space rose
}

nonisolated struct RoomVolumeSampleLog: Codable, Equatable, Sendable {
    static let hourlyWindow: TimeInterval = 48 * 3600
    static let dailyDays = 14                        // this week + the last point of last week (the Monday baseline)
    static let weeks = 104
    static let activationStale: TimeInterval = 6 * 3600

    private(set) var hourly: [RoomVolumeSample] = []   // one per local hour, newest last
    private(set) var daily: [RoomVolumeSample] = []    // one per local day, newest last
    private(set) var weekly: [RoomVolumeWeek] = []     // one per Monday-week, newest last (the current week is live)

    var latest: RoomVolumeSample? { hourly.last }

    /// 04 §3.5: launch, scans and stale activations always record; the 20 s monitor at most once per local hour.
    func shouldRecord(_ trigger: RoomVolumeTrigger, now: Date, calendar: Calendar) -> Bool {
        guard let last = latest else { return true }
        guard now >= last.at else { return false }                   // a clock that went backwards
        switch trigger {
        case .launch, .scanCompleted: return true
        case .activation: return now.timeIntervalSince(last.at) > Self.activationStale
                                 || !calendar.isDate(last.at, equalTo: now, toGranularity: .hour)
        case .monitorTick: return !calendar.isDate(last.at, equalTo: now, toGranularity: .hour)
        }
    }

    /// Returns true when a bucket was added (the caller persists then; replacing within a bucket is held in memory
    /// and flushed on terminate, so the 20 s loop never writes more than once an hour).
    @discardableResult
    mutating func record(_ sample: RoomVolumeSample, calendar: Calendar) -> Bool {
        guard sample.isValid else { return false }
        if let last = latest, sample.at < last.at { return false }
        var added = false
        func upsert(_ list: inout [RoomVolumeSample], _ granularity: Calendar.Component) {
            if let last = list.last, calendar.isDate(last.at, equalTo: sample.at, toGranularity: granularity) {
                list[list.count - 1] = sample
            } else { list.append(sample); added = true }
        }
        upsert(&hourly, .hour)
        upsert(&daily, .day)
        let week = RoomSizeLog.weekStart(containing: sample.at, calendar: calendar)
        if let last = weekly.last, last.weekStart == week {
            let keep = last.last.sameVolume(as: sample) ? last.kindBytes : nil   // kinds of another volume are dropped
            weekly[weekly.count - 1] = RoomVolumeWeek(weekStart: week, last: sample, kindBytes: keep)
        } else {
            weekly.append(RoomVolumeWeek(weekStart: week, last: sample, kindBytes: nil)); added = true
        }
        hourly.removeAll { sample.at.timeIntervalSince($0.at) > Self.hourlyWindow }
        if let cutoff = calendar.date(byAdding: .day, value: -Self.dailyDays, to: sample.at) { daily.removeAll { $0.at < cutoff } }
        if weekly.count > Self.weeks + 1 { weekly.removeFirst(weekly.count - Self.weeks - 1) }
        return added
    }

    /// Job B reports a home map. Stored only if complete, of the home root, and for the latest sample's volume.
    mutating func recordKinds(_ kinds: [String: Int64], at: Date, complete: Bool, volumeID: String?, calendar: Calendar) {
        guard complete, let volumeID, !kinds.isEmpty, kinds.values.allSatisfy({ $0 >= 0 }) else { return }
        let week = RoomSizeLog.weekStart(containing: at, calendar: calendar)
        guard let i = weekly.lastIndex(where: { $0.weekStart == week }), weekly[i].last.volumeID == volumeID else { return }
        weekly[i].kindBytes = kinds
    }

    /// "Since Monday" for the volume, with RoomSizeLog's baseline rule: the last point of last week (≤ 7 days before
    /// Monday), else the first point of this week named by its weekday. Never an older point; never across volumes.
    func change(now: Date, calendar: Calendar) -> RoomVolumeChange {
        let weekStart = RoomSizeLog.weekStart(containing: now, calendar: calendar)
        guard let latest = daily.last, latest.at >= weekStart, latest.at <= now else { return .tracking }
        let earlier = daily.dropLast()
        let floor = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let baseline: RoomVolumeSample
        let label: String
        if let before = earlier.last(where: { $0.at < weekStart && $0.at >= floor }) {
            baseline = before; label = "Monday"
        } else if let first = earlier.first(where: { $0.at >= weekStart }) {
            baseline = first; label = RoomSizeLog.weekdayName(first.at, calendar: calendar)
        } else { return .tracking }
        guard baseline.sameVolume(as: latest) else { return .volumeChanged }
        return .since(label: label, usedBytes: baseline.freeBytes - latest.freeBytes)
    }

    /// Seven slots Monday…Sunday for the week containing `date`; nil = Room did not see that day (drawn as a gap).
    func days(inWeekContaining date: Date, calendar: Calendar) -> [RoomVolumeSample?] {
        let start = RoomSizeLog.weekStart(containing: date, calendar: calendar)
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return daily.last { calendar.isDate($0.at, inSameDayAs: day) }
        }
    }

    /// The last `count` complete weeks before the current one, oldest first; missing weeks are nil, never zero.
    func pastWeeks(_ count: Int, now: Date, calendar: Calendar) -> [RoomVolumeWeek?] {
        let current = RoomSizeLog.weekStart(containing: now, calendar: calendar)
        return (1...max(1, count)).reversed().map { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: current) else { return nil }
            return weekly.first { $0.weekStart == RoomSizeLog.weekStart(containing: start, calendar: calendar) }
        }
    }
}

/// One volume history shared by the free-space answer, maps and the weekly views.
@Observable @MainActor
final class RoomVolumeHistory {
    static let shared = RoomVolumeHistory(writer: .shared)

    private(set) var log = RoomVolumeSampleLog()
    @ObservationIgnored private let writer: RoomStateWriter?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var buffered: [Event]?
    @ObservationIgnored private var readOnly = false
    @ObservationIgnored private var loading: Task<Void, Never>?

    private enum Event {
        case capacity(RoomVolumeSample, RoomVolumeTrigger)
        case kinds([String: Int64], Date, Bool, String?)
    }

    init(writer: RoomStateWriter? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.writer = writer
        self.now = now
        self.calendar = calendar
        if let writer {
            buffered = []
            loading = Task { [weak self] in
                let stored = await writer.store.load(RoomVolumeSampleLog.self, from: .volumeSamples)
                guard let self else { return }
                switch stored {
                case .loaded(let value, _): self.log = value
                case .newerReadOnly(let value):
                    self.readOnly = true
                    if let value { self.log = value }
                case .missing, .damaged: break
                }
                let events = self.buffered ?? []
                self.buffered = nil
                for event in events { self.apply(event) }
            }
        }
    }

    func waitForLoad() async { await loading?.value }

    func record(_ capacity: RoomVolumeCapacity, volumeID: String?, trigger: RoomVolumeTrigger) {
        enqueue(.capacity(.init(at: now(), capacityBytes: capacity.capacityBytes,
                                freeBytes: capacity.freeBytes, volumeID: volumeID), trigger))
    }

    func recordKinds(_ kinds: [String: Int64], at: Date, complete: Bool, volumeID: String?) {
        enqueue(.kinds(kinds, at, complete, volumeID))
    }

    func prepareForTermination() {
        if dirty { persist() }
    }

    func clearInMemory() {
        buffered?.removeAll()
        log = RoomVolumeSampleLog()
        dirty = false
        writer?.discardPending(for: .volumeSamples)
    }

    private func enqueue(_ event: Event) {
        if buffered != nil {
            buffered?.append(event)
        } else {
            apply(event)
        }
    }

    private func apply(_ event: Event) {
        guard !readOnly else { return }
        switch event {
        case .capacity(let sample, let trigger):
            guard log.shouldRecord(trigger, now: sample.at, calendar: calendar) else { return }
            var next = log
            let rolled = next.record(sample, calendar: calendar)
            guard next != log else { return }
            log = next
            dirty = true
            if rolled { persist() }
        case .kinds(let kinds, let at, let complete, let volumeID):
            var next = log
            next.recordKinds(kinds, at: at, complete: complete, volumeID: volumeID, calendar: calendar)
            guard next != log else { return }
            log = next
            persist()
        }
    }

    private func persist() {
        writer?.submit(log, to: .volumeSamples)
        dirty = false
    }
}
