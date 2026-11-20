import Observation
import SwiftUI

@Observable @MainActor
final class RoomInlineConfirmCenter {
    static let shared = RoomInlineConfirmCenter()
    private var entries: [String: Entry] = [:]
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]

    private struct Entry {
        var state = RoomInlineConfirm()
        let doneLine: String
        let stage: () -> Void
        let commit: () -> Void
        let undo: () -> Void
    }

    func phase(_ id: String) -> RoomInlineConfirm.Phase { entries[id]?.state.phase ?? .idle }

    func stagedLines(prefix: String) -> [(id: String, text: String)] {
        entries.compactMap { id, entry in
            guard id.hasPrefix(prefix), case .staged = entry.state.phase else { return nil }
            return (id, entry.doneLine)
        }.sorted { $0.id < $1.id }
    }

    func press(_ id: String, doneLine: String, stage: @escaping () -> Void,
               commit: @escaping () -> Void, undo: @escaping () -> Void) {
        for other in Array(entries.keys) where other != id { disarm(other) }
        var entry = entries[id] ?? Entry(doneLine: doneLine, stage: stage, commit: commit, undo: undo)
        let effect = entry.state.press(at: Date())
        entries[id] = entry
        if effect == .stage { entry.stage() }
        switch entry.state.phase {
        case .idle: break
        case .armed(let until), .staged(let until):
            timers[id]?.cancel()
            timers[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow))) }
                catch { return }
                self?.finish(id)
            }
        }
    }

    func disarm(_ id: String) {
        guard case .armed = phase(id) else { return }
        remove(id)
    }

    func undo(_ id: String) {
        guard var entry = entries[id], entry.state.undoPressed(at: Date()) == .undo else { return }
        remove(id)
        entry.undo()
    }

    func finish(_ id: String) {
        guard var entry = entries[id] else { return }
        remove(id)
        if entry.state.flush() == .commit { entry.commit() }
    }

    func finishAll(prefix: String = "") {
        for id in Array(entries.keys) where id.hasPrefix(prefix) { finish(id) }
    }

    private func remove(_ id: String) {
        timers.removeValue(forKey: id)?.cancel()
        entries[id] = nil
    }
}

struct RoomInlineConfirmButton: View {
    let id: String
    let title: String
    let confirmTitle: String
    let doneLine: String
    var isAllowed = true
    let stage: () -> Void
    let commit: () -> Void
    let undo: () -> Void

    @FocusState private var focused: Bool
    private let center = RoomInlineConfirmCenter.shared

    var body: some View {
        let armed = if case .armed = center.phase(id) { true } else { false }
        Button {
            center.press(id, doneLine: doneLine, stage: stage, commit: commit, undo: undo)
            focused = true
        } label: {
            Text(armed ? confirmTitle : title)
                .foregroundStyle(armed ? RoomTokens.Status.elevated : RoomTokens.Ink.graphite)
                .frame(minHeight: RoomTokens.Sidebar.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(RoomPressStyle())
        .disabled(!isAllowed)
        .focused($focused)
        .onAppear { if armed { focused = true } }
        .onChange(of: focused) { _, value in if !value { center.disarm(id) } }
        .onExitCommand { center.disarm(id) }
        .accessibilityLabel(armed ? confirmTitle : title)
    }
}

struct RoomInlineUndoRows: View {
    let prefix: String
    var hidesPrivateName = false
    @Environment(\.roomHide) private var hide
    private let center = RoomInlineConfirmCenter.shared

    var body: some View {
        ForEach(center.stagedLines(prefix: prefix), id: \.id) { entry in
            HStack {
                Text(hide.masksNow && hidesPrivateName ? "Room unpinned." : entry.text)
                    .font(RoomTokens.Typography.caption)
                Button(String(localized: "confirm.undo", defaultValue: "Undo", bundle: RoomCopy.bundle)) {
                    center.undo(entry.id)
                }
            }
        }
    }
}
