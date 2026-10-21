import SwiftUI

/// The selected cache sources become three upright layers; motion stays inside
/// the illustration so the numbers and controls never move under the pointer.
struct RoomGlassVisual: View {
    let selectionCount: Int
    let isScanning: Bool
    let motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @Namespace private var glassNamespace

    private var animated: Bool { motionEnabled && !reduceMotion }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.14 : 0.09))
                .frame(width: 230, height: 135)
                .blur(radius: 54)
                .offset(x: 20, y: 14)

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
                        .stroke(.primary.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
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
                .glassEffect(.regular.tint(Color.cyan.opacity(0.045)).interactive(),
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

struct RoomMark: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + side * x, y: origin.y + side * y)
        }
        // Three receding room frames match RoomMark.svg. Native stroke consumers
        // retain their foreground and line weight; no filled glyph is required.
        var path = Path()
        for index in 0..<3 {
            let corner = CGFloat(0.112) + CGFloat(index) * 0.224
            path.move(to: point(corner, 0.888))
            path.addLine(to: point(corner, corner + 0.096))
            path.addQuadCurve(to: point(corner + 0.096, corner), control: point(corner, corner))
            path.addLine(to: point(0.888, corner))
        }
        return path
    }
}

struct RoomAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                RadialGradient(colors: [Color.cyan.opacity(colorScheme == .dark ? 0.07 : 0.06), .clear],
                               center: .topTrailing, startRadius: 10, endRadius: 620)
                RadialGradient(colors: [Color.pink.opacity(colorScheme == .dark ? 0.045 : 0.045), .clear],
                               center: .bottomLeading, startRadius: 10, endRadius: 530)
            }
        }
        .ignoresSafeArea()
    }
}

enum RoomFormat {
    static func bytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func memoryBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    static func splitBytes(_ bytes: Int64, memory: Bool = false) -> (value: String, unit: String) {
        let text = memory ? self.memoryBytes(bytes) : self.bytes(bytes)
        guard let separator = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }
}

enum RoomType {
    static func heading(_ size: CGFloat) -> Font { .custom("AvenirNext-DemiBold", size: size) }
    static func figure(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
}

/// Each alternative keeps its unit and baseline together. Narrow windows choose
/// the next complete size rather than clipping a unit or compressing its glyphs.
struct RoomByteMetric: View {
    let bytes: Int64
    var maximumSize: CGFloat = 76
    var memory = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metric(size: maximumSize).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.82).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.66).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(size: CGFloat) -> some View {
        let amount = RoomFormat.splitBytes(bytes, memory: memory)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(amount.value)
                .font(RoomType.figure(size))
                .tracking(-0.6)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(amount.unit)
                .font(RoomType.figure(max(19, size * 0.35)))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
