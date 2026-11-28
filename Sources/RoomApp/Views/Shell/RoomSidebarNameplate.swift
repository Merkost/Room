import SwiftUI
import SystemConfiguration

/// The sidebar foot: the Mac's name, "64 GB free of 494 GB", and a meter whose accent part is what Make room would give
/// back. Hide masks the name and the sizes.
struct RoomSidebarNameplate: View {
    let freeBytes: Int64?
    let capacityBytes: Int64?
    let couldGoBytes: Int64
    let belowGoal: Bool

    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    static let macName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
            Text(verbatim: hide.masksNow ? "This Mac" : Self.macName)
                .font(RoomTokens.Nav.plateName)
                .foregroundStyle(RoomTokens.Ink.graphite)
                .lineLimit(1)
            if let line = freeLine {
                RoomMaskable(line, spoken: spokenLine)
                    .font(RoomTokens.Nav.plateLine)
                    .foregroundStyle(belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
                    .lineLimit(1)
            }
            if let meter = RoomNameplateMeter.make(capacityBytes: capacityBytes, freeBytes: freeBytes, couldGoBytes: couldGoBytes) {
                RoomNameplateMeterView(meter: meter)
                    .padding(.top, RoomTokens.Space.tight / 2)
                    .animation(motion.animation(RoomTokens.Motion.room, fallback: nil), value: meter)
            }
        }
        .padding(.horizontal, RoomTokens.Space.inner - 3)
        .padding(.top, RoomTokens.Space.row)
        .padding(.bottom, RoomTokens.Space.tight / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(RoomTokens.Surface.line).frame(height: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var freeLine: String? {
        guard let freeBytes, let capacityBytes, capacityBytes > 0 else { return nil }
        return "\(RoomFormat.gb(freeBytes)) free of \(RoomFormat.gb(capacityBytes))"
    }

    private var spokenLine: String { freeLine ?? "Free space unavailable" }

    private var accessibilityLabel: String {
        let name = hide.masksNow ? "This Mac" : Self.macName
        guard !hide.masksNow else { return "\(name), sizes hidden" }
        var parts = [name, spokenLine]
        if couldGoBytes > 0 { parts.append("Make room could give back \(RoomFormat.gb(couldGoBytes))") }
        if belowGoal { parts.append("under your goal") }
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
