import SwiftUI

/// The content arrival when a screen opens from the pointer (mockup `enter()`): the headline, the line under it and
/// the evidence rise 8 pt out of a 3 pt blur over 300 ms on `--eo`, 30 ms apart, at most 18 pieces. The keyboard and
/// programmatic navigation never animate; Reduce Motion keeps a plain fade.
nonisolated struct RoomEnterContext: Equatable, Sendable {
    var id = UUID()
    var animated = false
    var at = Date()
    /// Pieces that appear later than this (a scan finishing) just appear.
    static let window: TimeInterval = 0.8
}

private struct RoomEnterKey: EnvironmentKey {
    static let defaultValue = RoomEnterContext()
}

extension EnvironmentValues {
    var roomEnter: RoomEnterContext {
        get { self[RoomEnterKey.self] }
        set { self[RoomEnterKey.self] = newValue }
    }
}

private struct RoomEnterModifier: ViewModifier {
    let index: Int
    @Environment(\.roomEnter) private var context
    @Environment(\.roomMotion) private var motion
    @State private var shown = false
    @State private var animates = false

    func body(content: Content) -> some View {
        let hidden = animates && !shown
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && motion.isFull ? RoomTokens.Screen2.enterRise : 0)
            .blur(radius: hidden && motion.isFull ? RoomTokens.Screen2.enterBlur : 0)
            .onAppear {
                guard context.animated, index < RoomTokens.Screen2.enterCap,
                      Date().timeIntervalSince(context.at) < RoomEnterContext.window else { shown = true; return }
                animates = true
                let animation = (motion.isFull ? RoomTokens.Motion.enter : RoomTokens.Motion.fade)
                    .delay(Double(index) * RoomTokens.Screen2.enterStep)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Joins the screen's arrival at this place in the order (0 is the headline).
    func roomEnter(_ index: Int) -> some View { modifier(RoomEnterModifier(index: index)) }
}
