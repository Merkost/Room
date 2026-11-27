import RoomCore
import SwiftUI

struct RoomHistoryButton: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    let show: () -> Void

    @Environment(\.roomMotion) private var motion
    /// The latest receipt that arrived; only a new one pulses the button (clearing the receipt does not).
    @State private var arrivedReceipt: UUID?

    private enum Pulse: CaseIterable { case rest, lift, settle }

    var body: some View {
        let badge = model.makeRoomStore?.summary.badge ?? 0
        Button(action: show) {
            Image(systemName: "clock")
                // One pulse when a receipt pill arrives (Reduce Motion: a brief brighten, no scale).
                .phaseAnimator(Pulse.allCases, trigger: arrivedReceipt) { icon, phase in
                    icon.scaleEffect(phase == .lift && motion.isFull ? 1.2 : 1)
                        .opacity(phase == .lift && !motion.isFull ? 0.6 : 1)
                } animation: { phase in
                    switch phase {
                    case .lift: RoomTokens.Motion.quick.delay(RoomReceiptTravel.pulseDelay)
                    case .settle: motion.isFull ? RoomTokens.Motion.success : RoomTokens.Motion.fade
                    case .rest: nil
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let label = RoomHistorySummary.badgeText(badge) {
                        Text(RoomCachesVisibility.figure(label, hidden: hidden)).font(RoomTokens.Typography.micro)
                            .padding(.horizontal, 3).background(.thinMaterial, in: Capsule()).offset(x: 7, y: -5)
                    }
                }
                .frame(width: RoomTokens.Dock.barIcon, height: RoomTokens.Dock.barIcon)
                .contentShape(Circle())
        }
        .help("History (⌘Y)")
        .accessibilityLabel("History")
        .accessibilityValue(hidden ? "Receipt count hidden" : "\(badge) receipts still in Trash")
        .onChange(of: model.movedReceiptID) { _, new in if let new { arrivedReceipt = new } }
    }
}
