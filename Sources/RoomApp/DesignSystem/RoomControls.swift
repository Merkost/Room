import AppKit
import SwiftUI

enum RoomActionRole {
    case primary, secondary, quiet
}

enum RoomSelectionState {
    case off, on, mixed

    var controlState: NSControl.StateValue {
        switch self { case .off: .off; case .on: .on; case .mixed: .mixed }
    }
}

/// The native checkbox exposes a real mixed state rather than presenting a
/// partially selected family as an ordinary checked Boolean toggle.
struct RoomSelectionCheckbox: NSViewRepresentable {
    let state: RoomSelectionState
    let label: String
    var isEnabled = true
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator,
                              action: #selector(Coordinator.pressed(_:)))
        button.allowsMixedState = true
        button.controlSize = .regular
        button.focusRingType = .default
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        update(button, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    private func update(_ button: NSButton, coordinator: Coordinator) {
        coordinator.action = action
        button.state = state.controlState
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
        // NSButton publishes its platform checkbox value from state, including
        // the mixed value; avoid replacing that native accessibility mapping.
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func pressed(_ sender: NSButton) { action() }
    }
}

extension View {
    /// Presentation only. Native Button roles, focus, shortcuts, loading and
    /// disabled state remain owned by the action at its call site.
    @ViewBuilder
    func roomAction(_ role: RoomActionRole) -> some View {
        switch role {
        case .primary: buttonStyle(.glassProminent)
        case .secondary: buttonStyle(.glass)
        case .quiet: buttonStyle(.plain)
        }
    }
}
