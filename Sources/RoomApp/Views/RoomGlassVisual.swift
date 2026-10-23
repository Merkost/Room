import SwiftUI

/// The selected cache sources become three upright layers; motion stays inside
/// the illustration so the numbers and controls never move under the pointer.
struct RoomGlassVisual: View {
    let selectionCount: Int
    let isScanning: Bool
    let motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    @Namespace private var glassNamespace

    private var animated: Bool { motionEnabled && !reduceMotion }

    var body: some View {
        ZStack {
            GlassEffectContainer(spacing: 22) {
                ZStack {
                    plate(index: 2)
                    plate(index: 1)
                    plate(index: 0)
                }
            }
            .scaleEffect(hovering ? 1.025 : 1)
            .offset(y: hovering ? -3 : 0)
            .animation(animated ? .spring(response: 0.65, dampingFraction: 0.8) : nil, value: hovering)
            .animation(animated ? .spring(response: 0.7, dampingFraction: 0.75) : nil, value: selectionCount)
        }
        .frame(width: 320, height: 260)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityHidden(true)
        .allowsHitTesting(true)
    }

    private func plate(index: Int) -> some View {
        let depth = CGFloat(index)
        return ZStack {
            if index == 0 {
                ZStack {
                    RoomMark()
                        .fill(.primary.opacity(0.85), style: FillStyle(eoFill: true))
                        .frame(width: 73, height: 73)
                        .offset(y: -5)

                    HStack(spacing: 6) {
                        if isScanning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Circle().fill(Color.primary.opacity(0.65)).frame(width: 4, height: 4)
                        }
                        Text(isScanning ? "Measuring" : "\(selectionCount) selected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: 63)
                }
                .frame(width: 190, height: 202)
                .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 49, style: .continuous))
                .glassEffect(reduceTransparency ? .identity : .regular.tint(Color.cyan.opacity(0.045)).interactive(),
                             in: RoundedRectangle(cornerRadius: 49, style: .continuous))
                .glassEffectID(index, in: glassNamespace)
            } else {
                RoundedRectangle(cornerRadius: 49, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 49, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 1)
                    }
            }
        }
        .frame(width: 190, height: 202)
        .offset(y: depth * (hovering ? 13 : 9))
        .opacity(index == 0 ? 1 : 0.8 - Double(index) * 0.16)
        .scaleEffect(selectionCount == 0 ? 0.92 : 1)
    }
}
