import SwiftUI
import SystemConfiguration

/// This Mac's name over a meter of the volume: used in ink, what Make room would give back in the accent, free as the
/// track. Hide masks the name and the sizes. The headline above already says what is free.
struct RoomVolumeMeter: View {
    let freeBytes: Int64?
    let capacityBytes: Int64?
    let couldGoBytes: Int64

    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    static let macName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: hide.masksNow ? "This Mac" : Self.macName)
                    .font(RoomTokens.Nav.plateName)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    .lineLimit(1)
                Spacer(minLength: RoomTokens.Space.group)
                if couldGoBytes > 0 {
                    RoomMaskable("\(RoomFormat.gb(couldGoBytes)) could go")
                        .font(RoomTokens.Nav.plateLine)
                        .foregroundStyle(accent.text)
                }
            }
            if let meter = RoomNameplateMeter.make(capacityBytes: capacityBytes, freeBytes: freeBytes, couldGoBytes: couldGoBytes) {
                RoomNameplateMeterView(meter: meter)
                    .animation(motion.animation(RoomTokens.Motion.room, fallback: nil), value: meter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard !hide.masksNow else { return "This Mac, sizes hidden" }
        var parts = [Self.macName]
        if couldGoBytes > 0 { parts.append("Make room could give back \(RoomFormat.gb(couldGoBytes))") }
        return parts.joined(separator: ", ")
    }
}

struct RoomNameplateMeterView: View {
    let meter: RoomNameplateMeter
    @Environment(\.roomAccent) private var accent

    var body: some View {
        GeometryReader { geometry in
            let gap = RoomTokens.Nav.meterGap
            let width = max(0, geometry.size.width - gap * 2)
            HStack(spacing: gap) {
                Capsule().fill(RoomTokens.Ink.secondary).frame(width: width * meter.used)
                if meter.couldGo > 0 {
                    Capsule().fill(accent.text).frame(width: max(RoomTokens.Nav.meterHeight, width * meter.couldGo))
                }
                Capsule().fill(RoomTokens.Surface.tile)
            }
        }
        .frame(height: RoomTokens.Nav.meterHeight)
        .accessibilityHidden(true)
    }
}
