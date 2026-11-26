import RoomCore
import SwiftUI

/// What a move did, for six seconds after it lands: "Made 22 GB · Restore" (nav-v3 Make room, step 3).
nonisolated struct RoomMadeToastState: Equatable, Sendable {
    let receiptID: UUID
    let bytes: Int64
    var restored = false
    /// What Restore actually did, once it finished ("Put back", "1 of 2 put back. …"); nil while it runs.
    var outcome: String?

    var text: String {
        if let outcome { return outcome }
        return restored ? "Putting back…" : "Made \(RoomFormat.gb(bytes))"
    }

    /// The cache engine's restore result in words: everything back, or how much came back.
    static func cacheOutcome(itemCount: Int, restoredCount: Int, stillRestorable: Bool) -> String {
        if itemCount > 0, restoredCount >= itemCount { return "Put back" }
        if restoredCount == 0 { return "Nothing came back. The items changed or are no longer in Trash." }
        return "\(restoredCount) of \(itemCount) put back." + (stillRestorable ? " The rest stays in Trash." : "")
    }
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

/// The toast arrives and leaves the same way (mockup `.toast`): 24 pt up from below, from 96 %, on the UI spring with a
/// 180 ms fade. Reduce Motion keeps the fade.
struct RoomToastLift: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content.offset(y: shown ? 0 : 24).scaleEffect(shown ? 1 : 0.96).opacity(shown ? 1 : 0)
    }
}

extension AnyTransition {
    @MainActor static func roomToast(_ motion: RoomMotionPolicy) -> AnyTransition {
        motion.isFull ? .modifier(active: RoomToastLift(shown: false), identity: RoomToastLift(shown: true)) : .opacity
    }
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
        .background(RoomTokens.Surface.toastGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
        .shadow(color: RoomTokens.Surface.panelShadow, radius: 15, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hide.masksNow ? "Moved to Trash" : state.text)
    }
}
