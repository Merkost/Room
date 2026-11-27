import SwiftUI

/// The Make room moment (REVIEW §4.4): when a cleanup lands, the cleared rows leave, a receipt pill appears where
/// they were and travels to the History button in the toolbar, which pulses once. Reduce Motion: the pill
/// cross-fades in place and the button only brightens.
nonisolated enum RoomReceiptTravel {
    /// Pill in, a beat to read it, then the trip (page spring).
    static let hold: TimeInterval = RoomDS.Motion.Duration.standard.seconds
    static let trip: TimeInterval = RoomDS.Motion.Duration.page.seconds
    /// The History button pulses when the pill arrives.
    static var pulseDelay: TimeInterval { hold + trip }

    /// Where the pill goes, from its centre in the screen's coordinates: the toolbar's trailing History button.
    static func offset(from origin: CGPoint, screenWidth: CGFloat, fullMotion: Bool) -> CGSize {
        guard fullMotion else { return .zero }
        let target = CGPoint(x: screenWidth - RoomDS.Space.breath1, y: -RoomDS.Space.breath1)
        return CGSize(width: target.x - origin.x, height: target.y - origin.y)
    }
}

private struct RoomScreenSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    /// The detail column's visible size, for motion that aims at the toolbar.
    var roomScreenSize: CGSize {
        get { self[RoomScreenSizeKey.self] }
        set { self[RoomScreenSizeKey.self] = newValue }
    }
}

/// A cleanup has landed: a handful of dots leave the cleared rows for History, where the receipt now is. Nothing
/// heads for free space, because the files still sit in Trash. Reduce Motion draws nothing (History brightens).
struct RoomReceiptDots: View {
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var gone = false

    private static let count = 14

    var body: some View {
        GeometryReader { geometry in
            if motion.isFull {
                ForEach(0..<Self.count, id: \.self) { index in
                    let start = CGPoint(x: geometry.size.width * (0.18 + 0.03 * Double((index * 5) % Self.count)),
                                        y: geometry.size.height * (0.42 + 0.025 * Double((index * 3) % 7)))
                    Circle().fill(accent.text)
                        .frame(width: RoomTokens.Nav.dot + 2, height: RoomTokens.Nav.dot + 2)
                        .position(gone ? CGPoint(x: geometry.size.width - RoomTokens.Space.breath2 - RoomTokens.Dock.barIcon,
                                                 y: RoomTokens.Screen2.paneTop + RoomTokens.Screen2.barHeight / 2) : start)
                        .opacity(gone ? 0 : 1)
                        .scaleEffect(gone ? 0.4 : 1)
                        .animation(RoomTokens.Motion.eo(0.7).delay(Double(index) * 0.025), value: gone)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { gone = true }
    }
}
