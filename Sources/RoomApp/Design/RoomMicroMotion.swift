import SwiftUI

extension RoomMotionPolicy {
    /// Keep small replacements at the same anchor, with a shorter dismissal.
    var labelReplacement: AnyTransition {
        guard isFull else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 3).combined(with: .opacity).animation(RoomTokens.Motion.standard),
            removal: .offset(y: -3).combined(with: .opacity).animation(RoomTokens.Motion.quick)
        )
    }

    var rowDisclosure: AnyTransition {
        guard isFull else { return .opacity.animation(RoomTokens.Motion.fade) }
        return .asymmetric(
            insertion: .offset(y: -RoomTokens.Space.row).combined(with: .opacity).animation(RoomTokens.Motion.standard),
            removal: .opacity.animation(RoomTokens.Motion.quick)
        )
    }
}

extension View {
    func roomReveal(_ visible: Bool, from offset: CGFloat = 0, animation: Animation?) -> some View {
        self.offset(y: visible ? 0 : offset)
            .opacity(visible ? 1 : 0)
            .animation(animation, value: visible)
    }

    func roomPanelArrival(enabled: Bool = true, from offset: CGFloat = 0) -> some View {
        modifier(RoomPanelArrival(enabled: enabled, offset: offset))
    }

    func roomPanelChange(_ identity: some Hashable) -> some View {
        modifier(RoomPanelChange(identity: identity))
    }

    func roomNumericTransition<Value: Equatable>(_ value: Value, enabled: Bool = true) -> some View {
        modifier(RoomNumericTransition(value: value, enabled: enabled))
    }
}

/// Only the incoming panel fades. Its layout and the controls around it update immediately.
private struct RoomPanelArrival: ViewModifier {
    let enabled: Bool
    let offset: CGFloat
    @Environment(\.roomMotion) private var motion
    @State private var arrived = false

    func body(content: Content) -> some View {
        let animates = enabled && motion.isFull
        content
            .roomReveal(!animates || arrived, from: offset, animation: animates ? RoomTokens.Motion.standard : nil)
            .task { arrived = true }
    }
}

/// The old panel leaves before the new one arrives, so two captions are never readable at once (REVIEW §3 overlap).
nonisolated enum RoomPanelChangeTiming {
    static let removal: TimeInterval = RoomDS.Motion.Duration.quick.seconds
    static let insertionDelay: TimeInterval = removal
    static let insertion: TimeInterval = RoomDS.Motion.Duration.standard.seconds
}

/// Swap the content while leaving the surrounding controls and layout in place. One ZStack, one alignment: the old
/// content fades out (120 ms), then the new fades in (Reduce Motion keeps the fades and drops the 6 pt travel).
private struct RoomPanelChange<Identity: Hashable>: ViewModifier {
    let identity: Identity
    @Environment(\.roomMotion) private var motion

    func body(content: Content) -> some View {
        let arrival: AnyTransition = motion.isFull
            ? .opacity.combined(with: .offset(y: RoomTokens.Space.tight)) : .opacity
        ZStack(alignment: .topLeading) {
            content.id(identity)
                .transition(.asymmetric(
                    insertion: arrival.animation(RoomTokens.Motion.standard.delay(RoomPanelChangeTiming.insertionDelay)),
                    removal: .opacity.animation(RoomTokens.Motion.quick)))
        }
        .animation(motion.animation(RoomTokens.Motion.standard), value: identity)
    }
}

private struct RoomNumericTransition<Value: Equatable>: ViewModifier {
    let value: Value
    let enabled: Bool
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide

    func body(content: Content) -> some View {
        let animates = enabled && motion.isFull && !hide.masksNow
        content
            .contentTransition(animates ? .numericText() : .identity)
            // A RoomMaskable inside sets its own (opacity) content transition, which would win over this one; it reads
            // this flag instead, so masked figures roll too when their value really changes.
            .environment(\.roomNumericRoll, animates)
            .animation(animates ? RoomTokens.Motion.countAnimation : nil, value: value)
            .transaction(value: hide) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

private struct RoomNumericRollKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside `roomNumericTransition` while full motion is on and Hide is off: figures roll digit by digit.
    var roomNumericRoll: Bool {
        get { self[RoomNumericRollKey.self] }
        set { self[RoomNumericRollKey.self] = newValue }
    }
}

/// The hover wash is independent of layout, hit testing, and the selected state.
struct RoomHoverButtonStyle: ButtonStyle {
    var cornerRadius = RoomTokens.Radius.row
    var showsFeedback = true
    var isActive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.roomMotion) private var motion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = enabled && showsFeedback && (hovering || configuration.isPressed || isActive)
        return configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(RoomTokens.Surface.hover)
                    .opacity(highlighted ? 1 : 0)
                    .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: highlighted)
            }
            .onHover { hovering = $0 }
    }
}

struct RoomChangingSymbol: View {
    let name: String
    let color: Color
    @Environment(\.roomMotion) private var motion

    var body: some View {
        Image(systemName: name)
            .foregroundStyle(color)
            .contentTransition(motion.isFull ? .symbolEffect(.replace) : .identity)
            .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: name)
            .accessibilityHidden(true)
    }
}

nonisolated struct RoomCheckmarkPath: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.5))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

struct RoomSelectionCheckmark: View {
    let selected: Bool
    let color: Color
    @Environment(\.roomMotion) private var motion

    var body: some View {
        let border = RoundedRectangle(cornerRadius: 2)
        ZStack {
            border.strokeBorder(RoomTokens.Ink.secondary, lineWidth: 1)
            border.fill(color)
                .opacity(selected ? 1 : 0)
            RoomCheckmarkPath()
                .trim(from: 0, to: selected ? 1 : 0)
                .stroke(RoomTokens.Surface.canvas, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 7, height: 5)
        }
        .frame(width: 12, height: 12)
        .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: selected)
        .accessibilityHidden(true)
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
