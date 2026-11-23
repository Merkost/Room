import RoomCore
import SwiftUI

struct RoomHistoryButton: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    let show: () -> Void
    let restore: (RoomActivity) -> Void

    @Environment(\.roomMotion) private var motion
    @State private var hovering = false
    @State private var cardsHovered = false
    @State private var showingCards = false
    @State private var expanded = false
    /// The latest receipt that arrived; only a new one pulses the button (clearing the receipt does not).
    @State private var arrivedReceipt: UUID?

    private enum Pulse: CaseIterable { case rest, lift, settle }

    var body: some View {
        let badge = model.makeRoomStore?.summary.badge ?? 0
        Button {
            guard !model.activity.isEmpty else { show(); return }
            showingCards = true
            withAnimation(motion.animation(RoomTokens.Motion.page)) { expanded = true }
        } label: {
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
        }
        .help("History (⌘Y)")
        .accessibilityLabel("History")
        .accessibilityValue(hidden ? "Receipt count hidden" : "\(badge) receipts still in Trash")
        .onHover { hovering = $0 }
        .onChange(of: model.movedReceiptID) { _, new in if let new { arrivedReceipt = new } }
        .task(id: hovering) {
            if hovering, !model.activity.isEmpty {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                showingCards = true
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                withAnimation(motion.animation(RoomTokens.Motion.page)) { expanded = true }
            } else {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                if !cardsHovered { showingCards = false; expanded = false }
            }
        }
        .popover(isPresented: $showingCards, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Button("Show History") { showingCards = false; show() }
                let recent = Array(model.activity.prefix(3))
                if expanded || !motion.isFull {
                    ForEach(recent) { card($0) }
                } else {
                    ZStack(alignment: .top) {
                        ForEach(Array(recent.enumerated()).reversed(), id: \.element.id) { index, receipt in
                            card(receipt).scaleEffect(1 - 0.05 * Double(index))
                                .offset(y: -14 * CGFloat(index)).opacity(index == 0 ? 1 : 0.7)
                                .accessibilityHidden(index != 0)
                        }
                    }
                    .padding(.top, Double(max(0, recent.count - 1) * 14))
                }
            }
            .padding(RoomTokens.Space.group).frame(width: 280)
            .onHover { inside in
                cardsHovered = inside
                if !inside && !hovering { showingCards = false; expanded = false }
            }
            .onDisappear { expanded = false }
        }
    }

    private func card(_ receipt: RoomActivity) -> some View {
        let entry = model.makeRoomStore?.entry(for: receipt.id)
        let size = RoomCachesVisibility.bytes(receipt.bytes, hidden: hidden)
        let headline = entry.map { RoomMakeRoomCopy.headline($0, format: { RoomCachesVisibility.bytes($0, hidden: hidden) }) }
            ?? "Moved \(size) to Trash"
        return VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text(headline).font(RoomTokens.Typography.section).lineLimit(1)
            HStack {
                Text(receipt.date.formatted(.dateTime.day().month(.abbreviated)))
                Spacer()
                if RoomMakeRoomCopy.footerWord(entry, receiptCanRestore: receipt.canRestore) == nil {
                    Button("Restore") { showingCards = false; restore(receipt) }
                        .buttonStyle(.glass).tint(nil).disabled(model.isScanning || model.isWorking)
                }
            }
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .padding(RoomTokens.Space.row)
        .frame(width: 240, height: 66, alignment: .leading)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
    }
}
