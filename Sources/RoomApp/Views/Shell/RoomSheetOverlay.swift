import SwiftUI

/// A review drawn in the window (mockup `.sheet` over `.scrim`): a near-opaque card 104 pt from the top, centred, over
/// a quiet scrim that covers the sidebar too. It materialises from 14 pt higher, 96 % and a 3 pt blur on the 280 ms
/// UI spring with a 160 ms fade; opened from the keyboard it is simply there. The scrim takes every click, so nothing
/// behind it can be used while the review is open; it does not close the review (only Cancel and Escape do).
struct RoomSheetOverlay<Card: View>: ViewModifier {
    let isPresented: Bool
    var animated = true
    @ViewBuilder var card: () -> Card
    @Environment(\.roomMotion) private var motion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .top) {
                if isPresented {
                    RoomTokens.Surface.scrim
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    card()
                        .background(RoomTokens.Surface.sheetGlass,
                                    in: RoundedRectangle(cornerRadius: RoomTokens.Screen2.sheetRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: RoomTokens.Screen2.sheetRadius, style: .continuous)
                            .strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
                        .shadow(color: RoomTokens.Surface.panelShadow, radius: 30, y: 30)
                        .padding(.top, RoomTokens.Screen2.sheetTop)
                        .transition(motion.isFull ? .modifier(active: RoomSheetMaterialise(shown: false),
                                                              identity: RoomSheetMaterialise(shown: true)) : .opacity)
                        .accessibilityAddTraits(.isModal)
                        .zIndex(1)
                }
            }
            .ignoresSafeArea()
            .animation(animated ? motion.animation(RoomTokens.Motion.glass, fallback: RoomTokens.Motion.fade) : nil,
                       value: isPresented)
        }
    }
}

private struct RoomSheetMaterialise: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .offset(y: shown ? 0 : -14)
            .scaleEffect(shown ? 1 : 0.96, anchor: .top)
            .blur(radius: shown ? 0 : 3)
            .opacity(shown ? 1 : 0)
    }
}

extension View {
    func roomSheetOverlay<Card: View>(isPresented: Bool, animated: Bool = true,
                                      @ViewBuilder card: @escaping () -> Card) -> some View {
        modifier(RoomSheetOverlay(isPresented: isPresented, animated: animated, card: card))
    }
}
