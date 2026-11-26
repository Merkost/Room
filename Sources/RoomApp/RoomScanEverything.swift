import Foundation
import Observation

/// Overview's "Scan everything": starts every read-only scan at once and answers what each one is doing. The engines
/// keep their own state; this only remembers what was asked, so progress is never invented.
@MainActor @Observable
final class RoomScanEverything {
    nonisolated enum Part: String, CaseIterable, Sendable {
        case caches, disk, developer, memory
    }

    /// What one engine says about the scan started at `since`.
    nonisolated struct Reading: Equatable, Sendable {
        var running = false
        /// Waiting on the person (a folder panel or the Home confirmation).
        var pending = false
        var finished = false
        /// Why a read that ran came to nothing.
        var problem: String?
        /// Finished parts over all parts, only when the engine counts them.
        var fraction: Double?
        var detail = ""
        var figure: String?
    }

    struct Source {
        var unavailable: () -> String?
        var start: () -> Void
        var stop: () -> Void
        var read: (_ since: Date) -> Reading
    }

    @ObservationIgnored var sources: [Part: Source] = [:]
    /// True from the press until the finished rooms have had their moment.
    private(set) var isPresented = false
    private(set) var startedAt = Date.distantPast
    private var skipped: [Part: String] = [:]
    /// A room that finished keeps what it came to, whatever its engine does next.
    private var settled: [Part: RoomScanTile] = [:]
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    private var stopRequested = false

    var isRunning: Bool { isPresented && tiles.contains { $0.isActive } }

    func start() {
        guard !isRunning else { return }
        dismissal?.cancel()
        dismissal = nil
        startedAt = Date()
        settled = [:]
        skipped = [:]
        stopRequested = false
        for part in Part.allCases {
            guard let source = sources[part] else { continue }
            if let reason = source.unavailable() { skipped[part] = reason } else { source.start() }
        }
        isPresented = !sources.isEmpty
        watch()
    }

    /// Keeps each finished room, and once they all have, puts the board away after its moment. This lives here, not in
    /// a view, so leaving Overview cannot hold an old board open.
    func settle() {
        guard isPresented else { return }
        for part in Part.allCases where settled[part] == nil {
            if let tile = tile(part), !tile.isActive { settled[part] = tile }
        }
        guard dismissal == nil, !isRunning else { return }
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(RoomTokens.Scan.settle)) } catch { return }
            self?.dismiss()
        }
    }

    private func watch() {
        guard isPresented else { return }
        withObservationTracking { settle() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.watch() }
        }
    }

    func stop() {
        stopRequested = true
        for (part, source) in sources
        where skipped[part] == nil && settled[part] == nil && source.read(startedAt).running { source.stop() }
    }

    func dismiss() { isPresented = false }

    var tiles: [RoomScanTile] { Part.allCases.compactMap { settled[$0] ?? tile($0) } }

    private func tile(_ part: Part) -> RoomScanTile? {
        guard let source = sources[part] else { return nil }
        var tile = RoomScanTile(id: part.rawValue, title: Self.title(part), glyph: Self.glyph(part), state: .waiting)
        if let reason = skipped[part] {
            tile.state = .skipped
            tile.detail = reason
            return tile
        }
        let reading = source.read(startedAt)
        if reading.pending {
            tile.detail = "Waiting for you"
        } else if reading.running {
            tile.state = .reading(fraction: reading.fraction)
            tile.detail = reading.detail
        } else if let problem = reading.problem {
            tile.state = .skipped
            tile.detail = problem
        } else if reading.finished {
            tile.state = .done
            tile.value = reading.figure
        } else {
            tile.state = stopRequested ? .stopped : .skipped
            tile.detail = stopRequested ? "Stopped" : "Not read"
        }
        return tile
    }

    static func title(_ part: Part) -> String {
        switch part {
        case .caches: "Caches"
        case .disk: "Home folder"
        case .developer: "Developer"
        case .memory: "Memory"
        }
    }

    static func glyph(_ part: Part) -> RoomGlyph {
        switch part {
        case .caches: .caches
        case .disk: .diskMap
        case .developer: .developer
        case .memory: .memory
        }
    }
}

/// One room of a scan: what it is, whether it is being read, and what it came to.
nonisolated struct RoomScanTile: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable {
        case waiting, reading(fraction: Double?), done, stopped, skipped
    }

    let id: String
    let title: String
    let glyph: RoomGlyph
    var state: State
    var value: String? = nil
    var detail = ""

    var isReading: Bool { if case .reading = state { true } else { false } }
    var isActive: Bool { isReading || state == .waiting }
    /// How full the room is drawn. A part that does not count its work stays empty until it is done.
    var fill: Double {
        switch state {
        case .done: 1
        case .reading(let fraction): min(1, max(0, fraction ?? 0))
        default: 0
        }
    }

    /// "2 of 4 read": finished rooms over the rooms that were asked.
    static func progress(_ tiles: [RoomScanTile]) -> String {
        let asked = tiles.filter { $0.state != .skipped }
        return "\(asked.filter { $0.state == .done }.count) of \(asked.count) read"
    }
}
