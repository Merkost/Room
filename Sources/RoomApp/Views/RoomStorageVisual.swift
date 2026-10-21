import SwiftUI

/// A compact version of Room's upright layers, without miniature status text.
struct RoomStorageVisual: View {
    let selectionCount: Int
    let isScanning: Bool
    let motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var animation: Animation? {
        motionEnabled && !reduceMotion ? .spring(response: 0.4, dampingFraction: 1) : nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.primary.opacity(0.025))
                .frame(width: 88, height: 96)
                .offset(y: selectionCount > 0 ? 14 : 10)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .frame(width: 92, height: 100)
                .offset(y: selectionCount > 0 ? 7 : 5)

            RoomMark()
                .fill(Color.primary.opacity(0.8), style: FillStyle(eoFill: true))
                .frame(width: 42, height: 42)
                .frame(width: 96, height: 104)
                .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear,
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .glassEffect(reduceTransparency ? .identity : .regular.tint(Color.cyan.opacity(0.035)),
                             in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .opacity(isScanning ? 0.8 : 1)
        }
        .frame(width: 154, height: 142)
        .animation(animation, value: selectionCount)
        .animation(animation, value: isScanning)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
