import SwiftUI

extension RoomMotionPolicy {
    /// Keep small replacements at the same anchor, with a shorter dismissal.
    var labelReplacement: AnyTransition {
        guard isFull else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 3).combined(with: .opacity).animation(RoomTokens.Motion.rollIn),
            removal: .offset(y: -3).combined(with: .opacity).animation(RoomTokens.Motion.rollOut)
        )
    }

    var rowDisclosure: AnyTransition {
        guard isFull else { return .opacity.animation(RoomTokens.Motion.fade) }
        return .asymmetric(
            insertion: .offset(y: -RoomTokens.Space.row).combined(with: .opacity).animation(RoomTokens.Motion.standard),
            removal: .opacity.animation(RoomTokens.Motion.exit)
        )
    }
}

extension View {
    func roomReveal(_ visible: Bool, from offset: CGFloat = 0, animation: Animation?) -> some View {
        self.offset(y: visible ? 0 : offset)
            .opacity(visible ? 1 : 0)
            .animation(animation, value: visible)
    }
}

/// Keep the slot alive while its label changes. The caller supplies the semantic identity and can
/// disable replacement motion when the new value masks private information.
struct RoomChangingLabel<ID: Hashable, Label: View>: View {
    let value: ID
    var animates = true
    var alignment: Alignment = .leading
    @ViewBuilder var label: () -> Label
    @Environment(\.roomMotion) private var motion

    var body: some View {
        let enabled = animates && motion.isFull
        ZStack(alignment: alignment) {
            label()
                .id(value)
                .transition(enabled ? motion.labelReplacement : .identity)
                .accessibilityHidden(true)
        }
        .clipped()
        .animation(enabled ? RoomTokens.Motion.standard : nil, value: value)
        .transaction(value: enabled) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

/// An immediate update must also defeat any implicit animation on its descendants.
func roomWithoutMotion(_ update: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, update)
}
