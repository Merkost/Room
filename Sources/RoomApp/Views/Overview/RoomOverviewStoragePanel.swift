import SwiftUI

nonisolated struct RoomOverviewCapacityBalance {
    let plan: RoomOverviewPlanInput
    let goal: Int64?

    init(plan: RoomOverviewPlanInput, goal: Int64?) {
        self.plan = plan
        self.goal = goal.flatMap { $0 > 0 && $0 <= plan.capacityBytes ? $0 : nil }
    }

    var usedBytes: Int64 { plan.capacityBytes - plan.freeBytes }
    var usedFraction: Double { Double(usedBytes) / Double(plan.capacityBytes) }
    var goalPosition: Double? { goal.map { 1 - Double($0) / Double(plan.capacityBytes) } }
    var goalDifference: Int64? { goal.map { plan.freeBytes - $0 } }
}

struct RoomOverviewStoragePanel: View {
    let volumeName: String?
    let balance: RoomOverviewCapacityBalance
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    private var hidden: Bool { hide.masksNow }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Label(hidden ? "Storage" : volumeName ?? "Storage", systemImage: "internaldrive")
                .font(RoomTokens.Typography.title)
                .foregroundStyle(RoomTokens.Ink.graphite)
                .lineLimit(1)
                .accessibilityHeading(.h1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: RoomTokens.Space.breath2) {
                    availability.frame(minWidth: 168, idealWidth: 200)
                    breakdown.frame(minWidth: 246)
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    availability
                    breakdown
                }
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.popover))
        .accessibilityIdentifier("RoomOverviewStorage")
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text("Available")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            RoomByteMetric(bytes: balance.plan.freeBytes, maximumSize: 58)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hidden ? "Available space hidden" : "\(RoomFormat.bytes(balance.plan.freeBytes)) available")
            if let difference = balance.goalDifference {
                HStack(spacing: RoomTokens.Space.tight) {
                    Image(systemName: difference < 0 ? "arrow.down.right" : "checkmark")
                        .accessibilityHidden(true)
                    RoomMaskable(goalStatus(difference))
                }
                .font(RoomTokens.Typography.bodyStrong)
                .foregroundStyle(difference < 0 ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                figure("Used", bytes: balance.usedBytes)
                Spacer(minLength: 0)
                figure("Capacity", bytes: balance.plan.capacityBytes)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                HStack(spacing: 0) {
                    Rectangle().fill(RoomTokens.Surface.used.opacity(0.48))
                        .frame(width: width * balance.usedFraction)
                    Rectangle().fill(accent.fill)
                }
                .clipShape(Capsule())
                .overlay(alignment: .leading) {
                    if let position = balance.goalPosition {
                        Capsule()
                            .fill(RoomTokens.Ink.graphite)
                            .frame(width: 2, height: 18)
                            .offset(x: max(0, min(width - 2, width * position - 1)))
                    }
                }
            }
            .frame(height: 12)
            .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: balance.usedFraction)
            .accessibilityHidden(true)

            HStack(spacing: RoomTokens.Space.inner) {
                key("Used", color: RoomTokens.Surface.used.opacity(0.48))
                key("Available", color: accent.fill)
                if let goal = balance.goal {
                    RoomMaskable("\(RoomFormat.overviewBytes(goal)) goal")
                        .font(RoomTokens.Typography.micro)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func goalStatus(_ difference: Int64) -> String {
        if difference < 0 { return "\(RoomFormat.overviewBytes(-difference)) below goal" }
        if difference > 0 { return "\(RoomFormat.overviewBytes(difference)) above goal" }
        return "At your storage goal"
    }

    private func figure(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text(title).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            RoomMaskable(RoomFormat.bytes(bytes))
                .font(RoomTokens.Typography.figure)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func key(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(title).font(RoomTokens.Typography.micro).foregroundStyle(RoomTokens.Ink.secondary)
        }
        .accessibilityHidden(true)
    }
}
