import RoomCore
import SwiftUI

/// What a move did, for six seconds after it lands: "Made 22 GB · Restore" (nav-v3 Make room, step 3).
nonisolated struct RoomMadeToastState: Equatable, Sendable {
    let receiptID: UUID
    let bytes: Int64
    var restored = false

    var text: String { restored ? "Put back" : "Made \(RoomFormat.gb(bytes))" }
}

/// Make room progress, kept pure: how far the move is, from the engine's per-item statuses.
nonisolated enum RoomMakeRoomProgress {
    /// (done, total) items: trashed and failed both count as finished.
    static func counts(_ statuses: [UUID: ActivityStatus]) -> (done: Int, total: Int) {
        (statuses.values.filter { $0 == .trashed || $0 == .failed }.count, statuses.count)
    }

    /// Bytes moved so far, as the share of finished items times the bytes the review chose.
    static func movedBytes(_ statuses: [UUID: ActivityStatus], totalBytes: Int64) -> Int64 {
        let c = counts(statuses)
        guard c.total > 0 else { return 0 }
        return Int64(Double(totalBytes) * Double(c.done) / Double(c.total))
    }

    static func failed(_ statuses: [UUID: ActivityStatus]) -> Int { statuses.values.filter { $0 == .failed }.count }
}

struct RoomMadeToast: View {
    let state: RoomMadeToastState
    let canRestore: Bool
    let restore: () -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        HStack(spacing: RoomTokens.Space.row + 2) {
            RoomMaskable(state.text)
                .font(RoomTokens.Typography.bodyStrong)
                .foregroundStyle(RoomTokens.Ink.graphite)
            if canRestore && !state.restored {
                Button("Restore", action: restore)
                    .buttonStyle(RoomPressStyle())
                    .font(RoomTokens.Typography.bodyStrong)
                    .foregroundStyle(accent.text)
                    .padding(.horizontal, RoomTokens.Space.row)
                    .frame(height: 26)
                    .background(RoomTokens.Surface.tile, in: Capsule())
                    .accessibilityHint("Puts everything from this move back where it was")
            }
        }
        .padding(.leading, RoomTokens.Space.group)
        .padding(.trailing, RoomTokens.Space.tight + 2)
        .frame(height: RoomTokens.Screen2.toastHeight)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hide.masksNow ? "Moved to Trash" : state.text)
    }
}
