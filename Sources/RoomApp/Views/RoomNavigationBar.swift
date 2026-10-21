import SwiftUI

/// Flat navigation lives on the native toolbar. Only the selected destination
/// receives glass; there is no second enclosing material behind the controls.
struct RoomNavigationBar: View {
    @Binding var selection: RoomDestination
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionGlass
    @FocusState private var focusedDestination: RoomDestination?
    @State private var hoveredDestination: RoomDestination?

    private var selectionAnimation: Animation? {
        motionEnabled && !reduceMotion ? .smooth(duration: 0.22) : nil
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
        ViewThatFits(in: .horizontal) {
            navigationRow(presentation: .labeled)
            navigationRow(presentation: .labelsOnly)
            navigationRow(presentation: .iconsOnly)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(selectionAnimation, value: selection)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room views")
    }

    private func navigationRow(presentation: NavigationPresentation) -> some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(items) { item in destinationButton(item, presentation: presentation) }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
    }

    private func destinationButton(_ item: NavigationItem, presentation: NavigationPresentation) -> some View {
        let selected = selection == item.destination
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button { select(item.destination) } label: {
            HStack(spacing: 6) {
                if presentation != .labelsOnly {
                    Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 16)
                }
                if presentation != .iconsOnly {
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(width: presentation.slotWidth, height: 32)
            .background {
                if selected && reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else if !selected && hoveredDestination == item.destination {
                    shape.fill(Color.primary.opacity(0.045))
                }
            }
            .glassEffect(selected && !reduceTransparency ? .regular.interactive() : .identity, in: shape)
            .glassEffectID(selected ? "RoomSelectedDestination" : nil, in: selectionGlass)
            .glassEffectTransition(motionEnabled && !reduceMotion ? .matchedGeometry : .identity)
            .contentShape(shape)
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
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func select(_ destination: RoomDestination) {
        guard destination != selection else { return }
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

private enum NavigationPresentation: Equatable {
    case labeled, labelsOnly, iconsOnly

    var slotWidth: CGFloat {
        switch self { case .labeled: 94; case .labelsOnly: 78; case .iconsOnly: 36 }
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
