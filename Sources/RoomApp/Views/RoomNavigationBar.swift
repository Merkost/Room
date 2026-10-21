import SwiftUI

/// A stable row of destinations with one glass selection that moves between them.
/// Labels remain visible; only an explicit selection triggers the symbol feedback.
struct RoomNavigationBar: View {
    @Binding var selection: RoomDestination
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionGlass
    @FocusState private var focusedDestination: RoomDestination?
    @State private var hoveredDestination: RoomDestination?
    @State private var selectionPulses: [RoomDestination: Int] = [:]

    private var allowsMotion: Bool { motionEnabled && !reduceMotion }
    private var selectionAnimation: Animation? {
        allowsMotion ? .spring(response: 0.24, dampingFraction: 1) : nil
    }
    private var items: [NavigationItem] {
        [
            NavigationItem(destination: .clean, title: "Clean", symbol: "sparkles", shortcut: "1"),
            NavigationItem(destination: .memory, title: "Memory", symbol: "memorychip", shortcut: "2"),
            NavigationItem(destination: .disk, title: "Disk Map", symbol: "square.grid.2x2", shortcut: "3"),
            NavigationItem(destination: .developer, title: "Developer", symbol: "shippingbox", shortcut: "5"),
            NavigationItem(destination: .activity, title: "Activity", symbol: "clock.arrow.circlepath", shortcut: "4")
        ]
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                navigationRow(compact: false)
                navigationRow(compact: true)
            }
        }
        .background {
            Capsule()
                .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.035))
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(selectionAnimation, value: selection)
        .transaction { transaction in
            if !allowsMotion { transaction.disablesAnimations = true }
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room views")
    }

    private func navigationRow(compact: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { item in destinationButton(item, compact: compact) }
        }.padding(4)
    }

    private func destinationButton(_ item: NavigationItem, compact: Bool) -> some View {
        Button {
            select(item.destination)
        } label: {
            HStack(spacing: 6) {
                destinationSymbol(item)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 17)
                if !compact || selection == item.destination {
                    Text(item.title)
                        .font(.system(size: 12, weight: selection == item.destination ? .semibold : .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selection == item.destination ? .primary : .secondary)
            .padding(.horizontal, compact && selection != item.destination ? 12 : 13)
            .frame(height: 34)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                neutralBackground(for: item.destination)
            }
            // Apply material to the content-bearing view so SwiftUI keeps the
            // icon and title above the refractive plane, rather than sampling them.
            .glassEffect(selection == item.destination && !reduceTransparency
                ? .regular.tint(Color.cyan.opacity(0.08)).interactive() : .identity, in: Capsule())
            .glassEffectID(selection == item.destination ? "RoomSelectedDestination" : nil, in: selectionGlass)
            .glassEffectTransition(allowsMotion ? .matchedGeometry : .identity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused($focusedDestination, equals: item.destination)
        .keyboardShortcut(KeyEquivalent(item.shortcut), modifiers: .command)
        .onHover { hovered in
            if hovered { hoveredDestination = item.destination }
            else if hoveredDestination == item.destination { hoveredDestination = nil }
        }
        .help("\(item.title) (⌘\(String(item.shortcut)))")
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("RoomNavigation-\(item.id)")
        .accessibilityValue(selection == item.destination ? "Selected" : "")
        .accessibilityAddTraits(selection == item.destination ? [.isSelected] : [])
    }

    @ViewBuilder
    private func destinationSymbol(_ item: NavigationItem) -> some View {
        if allowsMotion {
            Image(systemName: item.symbol)
                .symbolEffect(.bounce.byLayer, options: .speed(2.5), value: selectionPulses[item.destination, default: 0])
        } else {
            Image(systemName: item.symbol)
        }
    }

    @ViewBuilder
    private func neutralBackground(for destination: RoomDestination) -> some View {
        if selection == destination && reduceTransparency {
            Capsule().fill(Color(nsColor: .controlBackgroundColor))
        } else if selection != destination && hoveredDestination == destination {
            Capsule().fill(Color.primary.opacity(0.045))
        }
    }

    private func select(_ destination: RoomDestination) {
        guard destination != selection else { return }
        if allowsMotion { selectionPulses[destination, default: 0] += 1 }
        withAnimation(selectionAnimation) { selection = destination }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let current = items.firstIndex(where: { $0.destination == (focusedDestination ?? selection) }) else { return }
        let next: Int
        switch direction {
        case .left: next = max(0, current - 1)
        case .right: next = min(items.count - 1, current + 1)
        default: return
        }
        let destination = items[next].destination
        focusedDestination = destination
        select(destination)
    }
}

private struct NavigationItem: Identifiable {
    let destination: RoomDestination
    let title: String
    let symbol: String
    let shortcut: Character
    var id: String {
        switch destination {
        case .clean: "clean"
        case .memory: "memory"
        case .disk: "disk"
        case .developer: "developer"
        case .activity: "activity"
        }
    }
}
