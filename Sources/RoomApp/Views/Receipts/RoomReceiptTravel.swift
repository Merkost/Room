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

struct RoomReceiptTravelPill: View {
    let text: String
    /// Pill centre in the `RoomScreenScaffold.space` coordinate space.
    let origin: CGPoint
    let finished: () -> Void
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomScreenSize) private var screen
    @State private var shown = false
    @State private var arrived = false

    var body: some View {
        let travel = RoomReceiptTravel.offset(from: origin, screenWidth: screen.width, fullMotion: motion.isFull)
        Label(text, systemImage: "trash")
            .font(RoomTokens.Typography.section)
            .padding(.horizontal, RoomTokens.Space.inner)
            .frame(height: RoomTokens.Map.readoutHeight)
            .background(RoomTokens.Surface.group, in: Capsule())
            .overlay { Capsule().strokeBorder(RoomTokens.Surface.line2) }
            .scaleEffect(arrived && motion.isFull ? 0.4 : 1)
            .offset(arrived ? travel : .zero)
            .opacity(shown && !arrived ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                withAnimation(motion.animation(RoomTokens.Motion.standard)) { shown = true }
                try? await Task.sleep(for: .seconds(RoomReceiptTravel.hold))
                withAnimation(motion.animation(RoomTokens.Motion.page)) { arrived = true }
                try? await Task.sleep(for: .seconds(RoomReceiptTravel.trip))
                finished()
            }
    }
}
