import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class RoomActivityCenter {
    static let shared = RoomActivityCenter()

    private(set) var visible: RoomActivityPillState = .idle(freeBytes: nil)
    private(set) var expansion: [RoomActivityPillState] = []
    @ObservationIgnored private var board = RoomActivityBoard()
    @ObservationIgnored private var idle: RoomActivityPillState = .idle(freeBytes: nil)
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var labels: [RoomActivityBoard.Source: RoomRollingLabel] = [:]
    @ObservationIgnored private var pending: [RoomActivityBoard.Source: RoomActivityPillState] = [:]
    @ObservationIgnored private var labelTimers: [RoomActivityBoard.Source: Task<Void, Never>] = [:]

    func post(_ state: RoomActivityPillState, from source: RoomActivityBoard.Source) {
        cancelLabel(source)
        board.post(state, from: source, at: Date())
        update()
    }

    func clear(_ source: RoomActivityBoard.Source) {
        cancelLabel(source)
        board.clear(source)
        update()
    }

    func setIdle(freeBytes: Int64?) {
        idle = .idle(freeBytes: freeBytes)
        update()
    }

    func pause(_ paused: Bool) {
        if paused { board.pause(at: Date()) } else { board.resume(at: Date()) }
        update()
    }

    func reportScan(_ tool: RoomActivityPillState.Tool, path: String, files: Int, bytes: Int64) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        reportScanLabel(tool, label: RoomPillPath.abbreviate(path, home: home), files: files, bytes: bytes)
    }

    func reportScanLabel(_ tool: RoomActivityPillState.Tool, label: String, files: Int, bytes: Int64) {
        let source: RoomActivityBoard.Source = switch tool {
        case .diskMap: .diskMap
        case .caches: .caches
        case .developer: .developer
        }
        let state = RoomActivityPillState.scanning(tool: tool, location: label, files: files, bytes: bytes)
        let now = Date()
        if labels[source, default: RoomRollingLabel()].offer(label, at: now) != nil {
            pending[source] = nil
            board.post(state, from: source, at: now)
            update()
        } else if labels[source]?.pending != nil, let shown = labels[source]?.shownAt {
            pending[source] = state
            guard labelTimers[source] == nil else { return }
            let deadline = shown.addingTimeInterval(RoomRollingLabel.interval)
            labelTimers[source] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
                guard let self else { return }
                self.labelTimers[source] = nil
                guard let next = self.pending.removeValue(forKey: source),
                      self.labels[source]?.flush(at: max(Date(), deadline)) != nil else { return }
                self.board.post(next, from: source, at: Date())
                self.update()
            }
        } else {
            pending[source] = nil
        }
    }

    private func cancelLabel(_ source: RoomActivityBoard.Source) {
        labels[source] = nil
        pending[source] = nil
        labelTimers.removeValue(forKey: source)?.cancel()
    }

    private func update() {
        let now = Date()
        let nextVisible = board.visible(now: now, idle: idle)
        if visible != nextVisible { visible = nextVisible }
        let nextExpansion = board.expansion(now: now)
        if expansion != nextExpansion { expansion = nextExpansion }
        expiry?.cancel()
        guard let next = board.nextExpiry(now: now) else { expiry = nil; return }
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) } catch { return }
            self?.update()
        }
    }
}

extension EnvironmentValues {
    @Entry var roomActivityCenter: RoomActivityCenter?
}
