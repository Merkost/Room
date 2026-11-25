import Foundation
import Observation

/// What a place's engine reports right now. The sidebar turns a stream of these into row states.
nonisolated struct RoomRowSignal: Equatable, Sendable {
    var working = false
    var done = 0
    /// nil when the engine has no total (the ring stays a track and the dots are not counted).
    var of: Int?
    var sentence = ""
    /// What the row says once the work ends ("Found 22 GB", "All clear").
    var doneSentence = ""
    /// One plain sentence when the last run ended badly ("Could not read 2 places").
    var failure: String?

    static let idle = RoomRowSignal()
}

/// One row's progress (FEATURES › Navigation): working (ring, sentence, counted dots, Stop on hover), finished (check,
/// then the row settles 4 s later), unseen (dot and accent value until the place is opened), failed (one sentence).
nonisolated struct RoomRowActivity: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, working, finished, failed }

    private(set) var phase: Phase = .idle
    private(set) var done = 0
    private(set) var of: Int?
    private(set) var sentence = ""
    private(set) var unseen = false
    private(set) var finishedAt: Date?

    static let settleSeconds: TimeInterval = 4

    /// Ring fill, 0…1, or nil while the total is unknown.
    var fraction: Double? {
        switch phase {
        case .working: of.flatMap { $0 > 0 ? min(1, Double(done) / Double($0)) : nil }
        case .finished: 1
        case .idle, .failed: nil
        }
    }

    /// The second line shows while working, just after finishing, and after a failure.
    var showsSentence: Bool { phase != .idle }
    var showsCheck: Bool { phase == .finished }
    var isWorking: Bool { phase == .working }

    /// Counted dots while working: at most 12; `filled` of them are done, the last filled one is "now".
    var dots: (total: Int, filled: Int)? {
        guard phase == .working, let of, of > 0 else { return nil }
        let total = min(of, RoomTokens.Nav.dotMax)
        let filled = Int((Double(done) / Double(of) * Double(total)).rounded())
        return (total, min(total, max(0, filled)))
    }

    /// Returns true when the row has just finished (the caller schedules `settle`).
    @discardableResult
    mutating func apply(_ signal: RoomRowSignal, isOpen: Bool, now: Date) -> Bool {
        if signal.working {
            if phase != .working { unseen = false; finishedAt = nil }
            phase = .working
            done = signal.done
            of = signal.of
            sentence = signal.sentence
            return false
        }
        guard phase == .working else { return false }
        if let failure = signal.failure {
            phase = .failed
            sentence = failure
            return false
        }
        phase = .finished
        if let of { done = of }
        sentence = signal.doneSentence
        finishedAt = now
        unseen = !isOpen
        return true
    }

    /// Four seconds after finishing, the second line folds away; the unseen dot stays until the place is opened.
    mutating func settle(now: Date) {
        guard phase == .finished, let finishedAt, now.timeIntervalSince(finishedAt) >= Self.settleSeconds - 0.01 else { return }
        phase = .idle
        sentence = ""
        self.finishedAt = nil
    }

    /// The person opened the place: the result has been seen, and an error has been read.
    mutating func open() {
        unseen = false
        if phase == .failed { phase = .idle; sentence = "" }
    }

    /// Stop: the row returns to rest without a check.
    mutating func stop() {
        phase = .idle
        sentence = ""
        done = 0
        finishedAt = nil
    }
}

/// The rows' states for the window, with the 4 s settle timers. Fed by `RoomRootView` from the engines.
@Observable @MainActor
final class RoomSidebarActivity {
    private(set) var rows: [RoomDestination: RoomRowActivity] = [:]
    @ObservationIgnored private var settles: [RoomDestination: Task<Void, Never>] = [:]
    @ObservationIgnored private let settleDelay: Duration

    init(settleDelay: Duration = RoomTokens.Nav.settle) { self.settleDelay = settleDelay }

    func row(_ place: RoomDestination) -> RoomRowActivity { rows[place] ?? RoomRowActivity() }

    func update(_ signals: [RoomDestination: RoomRowSignal], open current: RoomDestination?, now: Date = Date()) {
        for (place, signal) in signals {
            var row = rows[place] ?? RoomRowActivity()
            let finished = row.apply(signal, isOpen: current == place, now: now)
            if row != rows[place] ?? RoomRowActivity() { rows[place] = row }
            if finished { scheduleSettle(place) }
        }
    }

    func open(_ place: RoomDestination) {
        guard var row = rows[place] else { return }
        row.open()
        if row != rows[place] { rows[place] = row }
    }

    func stop(_ place: RoomDestination) {
        settles.removeValue(forKey: place)?.cancel()
        guard var row = rows[place] else { return }
        row.stop()
        rows[place] = row
    }

    private func scheduleSettle(_ place: RoomDestination) {
        settles.removeValue(forKey: place)?.cancel()
        let delay = settleDelay
        settles[place] = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, var row = self.rows[place] else { return }
            // The timer is the clock here: settle as of the moment the dwell ends.
            row.settle(now: row.finishedAt.map { $0.addingTimeInterval(RoomRowActivity.settleSeconds) } ?? Date())
            self.rows[place] = row
            self.settles[place] = nil
        }
    }
}

/// The sentences each place says while it works and when it ends. Sizes go through `RoomFormat.gb`.
nonisolated enum RoomRowSignals {
    static func caches(isScanning: Bool, checked: Int, of total: Int, clearableBytes: Int64, unreadable: Int) -> RoomRowSignal {
        let counted = total > 0
        return RoomRowSignal(
            working: isScanning, done: min(checked, total), of: counted ? total : nil,
            sentence: counted ? "Checking \(min(checked + 1, total)) of \(total) places" : "Checking caches",
            doneSentence: clearableBytes > 0 ? "Found \(RoomFormat.gb(clearableBytes))" : "All clear",
            failure: unreadable > 0 ? (unreadable == 1 ? "Could not read 1 place" : "Could not read \(unreadable) places") : nil)
    }

    static func developer(isScanning: Bool, progress: String, totalBytes: Int64, projects: Int, error: String?) -> RoomRowSignal {
        let done: String
        if totalBytes > 0 {
            done = projects > 0 ? "\(RoomFormat.gb(totalBytes)) in \(projects == 1 ? "1 project" : "\(projects) projects")"
                                : RoomFormat.gb(totalBytes)
        } else {
            done = "Scan finished"
        }
        return RoomRowSignal(working: isScanning, sentence: progress.isEmpty ? "Scanning" : progress,
                             doneSentence: done, failure: error.map { _ in "Could not finish the scan" })
    }

    static func diskMap(isScanning: Bool, mapped: Int, of total: Int?) -> RoomRowSignal {
        let counted = (total ?? 0) > 0
        return RoomRowSignal(
            working: isScanning, done: mapped, of: counted ? total : nil,
            sentence: counted ? "Mapping \(min(mapped + 1, total!)) of \(total!) folders" : "Mapping",
            doneSentence: "Folder mapped")
    }

    /// Make room: "Moving 7 of 22 GB", then "Made 22 GB".
    static func makeRoom(isMoving: Bool, movedBytes: Int64, totalBytes: Int64, madeBytes: Int64?, failed: Int) -> RoomRowSignal {
        let totalGB = max(1, Int((Double(totalBytes) / 1e9).rounded()))
        let movedGB = min(totalGB, Int((Double(movedBytes) / 1e9).rounded()))
        return RoomRowSignal(
            working: isMoving, done: movedGB, of: totalGB,
            sentence: "Moving \(movedGB) of \(RoomFormat.gb(totalBytes))",
            doneSentence: "Made \(RoomFormat.gb(madeBytes ?? totalBytes))",
            failure: failed > 0 ? (failed == 1 ? "1 item could not move" : "\(failed) items could not move") : nil)
    }
}
