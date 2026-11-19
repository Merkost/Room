import SwiftUI

/// Flat navigation lives on the native toolbar. Only the selected destination
/// receives glass; there is no second enclosing material behind the controls.
struct RoomNavigationBar: View {
    @Binding var selection: RoomDestination
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focusedDestination: RoomDestination?
    @State private var hoveredDestination: RoomDestination?

    static let items: [NavigationItem] = RoomMenuModel.Destination.allCases.compactMap { item in
        guard let destination = RoomDestination(rawValue: item.rawValue) else { return nil }
        return NavigationItem(destination: destination, title: item.item.title, symbol: item.symbol,
                              shortcut: item.shortcut?.key)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            navigationRow(presentation: .labeled)
            navigationRow(presentation: .labelsOnly)
            navigationRow(presentation: .iconsOnly)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room views")
    }

    private func navigationRow(presentation: NavigationPresentation) -> some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Self.items) { item in destinationButton(item, presentation: presentation) }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
    }

    private func destinationButton(_ item: NavigationItem, presentation: NavigationPresentation) -> some View {
        let selected = selection == item.destination
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.row, style: .continuous)
        return Button { select(item.destination, moveFocus: false) } label: {
            HStack(spacing: 6) {
                if presentation != .labelsOnly {
                    Image(systemName: item.symbol).font(RoomTokens.Typography.bodyStrong).frame(width: 16)
                }
                if presentation != .iconsOnly {
                    Text(item.title).font(RoomTokens.Typography.navigationLabel).lineLimit(1)
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(width: presentation.slotWidth, height: 32)
            .background {
                if selected && reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else if !selected && hoveredDestination == item.destination {
                    shape.fill(RoomTokens.Surface.hover)
                }
            }
            .glassEffect(selected && !reduceTransparency ? .regular.interactive() : .identity, in: shape)
            .glassEffectTransition(.identity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focusedDestination, equals: item.destination)
        .onHover { hovered in
            if hovered { hoveredDestination = item.destination }
            else if hoveredDestination == item.destination { hoveredDestination = nil }
        }
        .help(item.help)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("RoomNavigation-\(item.id)")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func select(_ destination: RoomDestination, moveFocus: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if moveFocus { focusedDestination = destination }
            if selection != destination { selection = destination }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = Self.items
        guard let current = items.firstIndex(where: { $0.destination == (focusedDestination ?? selection) }) else { return }
        let next: Int
        switch direction {
        case .left: next = max(0, current - 1)
        case .right: next = min(items.count - 1, current + 1)
        default: return
        }
        select(items[next].destination, moveFocus: true)
    }
}

private enum NavigationPresentation: Equatable {
    case labeled, labelsOnly, iconsOnly

    var slotWidth: CGFloat {
        switch self { case .labeled: 94; case .labelsOnly: 78; case .iconsOnly: 36 }
    }
}

nonisolated struct NavigationItem: Identifiable, Sendable {
    let destination: RoomDestination
    let title: String
    let symbol: String
    let shortcut: Character?
    var id: String { destination.rawValue }
    var help: String { shortcut.map { "\(title) (⌘\($0))" } ?? title }
}
