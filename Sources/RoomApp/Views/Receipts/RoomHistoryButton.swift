import RoomCore
import SwiftUI

struct RoomHistoryButton: View {
    let model: RoomViewModel
    let show: () -> Void
    let restore: (RoomActivity) -> Void

    @Environment(\.roomMotion) private var motion
    @State private var hovering = false
    @State private var cardsHovered = false
    @State private var showingCards = false
    @State private var expanded = false

    var body: some View {
        let badge = model.makeRoomStore?.summary.badge ?? 0
        Button {
            guard !model.activity.isEmpty else { show(); return }
            showingCards = true
            withAnimation(motion.animation(RoomTokens.Motion.page)) { expanded = true }
        } label: {
            Image(systemName: "clock")
                .overlay(alignment: .topTrailing) {
                    if let label = RoomHistorySummary.badgeText(badge) {
                        Text(label).font(RoomTokens.Typography.micro)
                            .padding(.horizontal, 3).background(.thinMaterial, in: Capsule()).offset(x: 7, y: -5)
                    }
                }
        }
        .help("History (⌘Y)")
        .accessibilityLabel("History")
        .accessibilityValue("\(badge) receipts still in Trash")
        .onHover { hovering = $0 }
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
                ForEach(Array(model.activity.prefix(expanded ? 3 : 1))) { receipt in
                    RoomReceiptView(receipt: receipt, entry: model.makeRoomStore?.entry(for: receipt.id),
                        restore: model.isScanning || model.isWorking ? nil : {
                            showingCards = false
                            restore(receipt)
                        })
                }
            }
            .padding(RoomTokens.Space.group).frame(width: 320)
            .onHover { inside in
                cardsHovered = inside
                if !inside && !hovering { showingCards = false; expanded = false }
            }
            .onDisappear { expanded = false }
        }
    }
}
