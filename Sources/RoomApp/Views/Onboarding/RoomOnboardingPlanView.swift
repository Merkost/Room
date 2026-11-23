import SwiftUI

/// The person's own Mac as a dot plan, inside the onboarding stage wall (ONBOARDING-V3-SPEC §3.2, §3.4, MV-1, MV-2, MV-8).
/// Geometry is the shared `RoomDotPlan` (the same rings Overview draws); only `RoomVolumeCapacity` is drawn: free
/// rings and one dashed Not mapped area. No kind room, kind colour or count appears here (D-ONV-7).
/// A separate view from `RoomDotPlanView` because the onboarding plan needs a per-row settle and the step 3 hint,
/// and Overview's plan carries hover, wake and selection that the sheet must not have.
struct RoomOnboardingPlanView: View {
    let plan: RoomOverviewPlanInput
    let wallHeight: CGFloat
    let hidden: Bool
    /// Step 3: the Not mapped area is where rooms will appear; the hint shows while Map my home folder is in focus.
    var showsHint = false
    var hintActive = false
    /// MV-1: false until the one settle of this presentation runs.
    let settled: Bool

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast

    private typealias Tokens = RoomTokens.OverviewPlan
    private typealias Onboarding = RoomTokens.Onboarding

    private struct RingRow: Identifiable {
        let id: Int
        let centers: [CGPoint]
    }

    var body: some View {
        let size = RoomOnboardingStage.layoutSize(wallHeight: wallHeight)
        let layout = plan.layout(size: size)
        let notMapped = layout.rooms.first { $0.id == .notMapped }?.rect.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap)
        let rows = Self.rows(layout)
        let hint = showsHint && hintActive
        ZStack(alignment: .topLeading) {
            if let notMapped, !notMapped.isEmpty {
                notMappedArea(notMapped, pitch: layout.pitch, hint: hint)
                    .opacity(settled ? 1 : 0)
                    .animation(settleAnimation(delay: motion.isFull ? RoomTokens.Motion.settleStagger : 0), value: settled)
            }
            ForEach(rows) { row in
                RoomOnboardingRingRow(centers: row.centers, radius: layout.radius,
                                      scale: settled || !motion.isFull ? 1 : Onboarding.settleScale)
                    .stroke(freeInk, lineWidth: RoomTokens.Dots.freeRingStroke)
                    .opacity(settled ? 1 : 0)
                    .animation(settleAnimation(delay: motion.isFull ? RoomTokens.Motion.stagger
                        * Double(min(row.id, RoomTokens.Motion.maxStaggered - 1)) : 0), value: settled)
            }
            if let notMapped, notMapped.width >= 200, notMapped.height >= 56 {
                label(hint: hint)
                    .frame(width: notMapped.width - 2 * Tokens.labelInset)
                    .position(x: notMapped.midX, y: notMapped.midY)
                    .opacity(settled ? 1 : 0)
                    .animation(settleAnimation(delay: motion.isFull ? RoomTokens.Motion.settleStagger : 0), value: settled)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .padding(RoomOnboardingStage.pad)
        .animation(motion.animation(RoomTokens.Motion.standard), value: hint)
        .allowsHitTesting(false)
    }

    /// Rings grouped by row (top to bottom) for the row-by-row settle.
    private static func rows(_ layout: RoomDotPlan) -> [RingRow] {
        let free = layout.dots.filter { $0.room == .free }
        let grouped = Dictionary(grouping: free) { Int(($0.center.y * 2).rounded()) }
        return grouped.keys.sorted().enumerated().map { index, key in
            RingRow(id: index, centers: grouped[key, default: []].map(\.center))
        }
    }

    private func settleAnimation(delay: TimeInterval) -> Animation {
        motion.isFull ? RoomTokens.Motion.settle.delay(delay) : RoomTokens.Motion.fade
    }

    private var freeInk: Color {
        RoomTokens.Ink.secondary.opacity(contrast == .increased ? 1 : RoomTokens.Dots.freeRingOpacity)
    }

    private var neutralOutline: Color {
        RoomTokens.Ink.secondary.opacity(contrast == .increased ? 1 : Onboarding.notMappedOpacity)
    }

    private func notMappedArea(_ rect: CGRect, pitch: CGFloat, hint: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.planRoom)
        let step = max(Tokens.gridPoint, pitch * Tokens.gridPitchFactor)
        return ZStack {
            shape.fill(accent.wash).opacity(hint ? 1 : 0)
            if contrast == .increased { shape.fill(accent.wash).opacity(hint ? 1 : 0) }
            Canvas { context, size in
                var grid = Path()
                for y in stride(from: step / 2, to: size.height, by: step) {
                    for x in stride(from: step / 2, to: size.width, by: step) {
                        grid.addEllipse(in: CGRect(x: x, y: y, width: Tokens.gridPoint, height: Tokens.gridPoint))
                    }
                }
                context.fill(grid, with: .color(RoomTokens.Surface.line2))
            }
            .clipShape(shape)
            shape.stroke(hint ? accent.text : neutralOutline,
                         style: StrokeStyle(lineWidth: hint && contrast == .increased ? 1.5 : Tokens.dashedWall.lineWidth,
                                            dash: Tokens.dashedWall.dash))
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder private func label(hint: Bool) -> some View {
        if showsHint {
            Text(RoomOnboardingCopy.hint)
                .font(RoomTokens.Typography.bodyStrong)
                .foregroundStyle(hint ? accent.text : RoomTokens.Ink.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.labelInset)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: Onboarding.labelBackingRadius).fill(RoomTokens.Surface.canvas)
                        RoundedRectangle(cornerRadius: Onboarding.labelBackingRadius).fill(accent.wash).opacity(hint ? 1 : 0)
                    }
                }
        } else {
            VStack(spacing: RoomTokens.Space.tight / 2) {
                backed(Text(RoomOnboardingCopy.notMappedLabel(.yourMac))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoomTokens.Ink.graphite))
                backed(Text(RoomOnboardingCopy.notMappedDetail(plan, hidden: hidden, format: RoomFormat.gb))
                    .font(RoomTokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(RoomTokens.Ink.secondary))
            }
            .multilineTextAlignment(.center)
        }
    }

    private func backed(_ text: some View) -> some View {
        text.padding(.horizontal, Tokens.labelInset)
            .background(RoomTokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Onboarding.labelBackingRadius))
    }
}

/// One row of free rings; `scale` animates each ring about its own centre (MV-1).
nonisolated struct RoomOnboardingRingRow: Shape {
    var centers: [CGPoint]
    var radius: CGFloat
    var scale: CGFloat

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            let r = radius * scale
            for center in centers {
                path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            }
        }
    }
}

/// Unreadable capacity or a disk over 26 TB: no plan, no ring, no number (§3.2).
struct RoomOnboardingPlanUnavailable: View {
    let tooLarge: Bool

    var body: some View {
        VStack(spacing: 0) {
            RoomMark()
                .fill(RoomTokens.Ink.secondary.opacity(RoomTokens.Onboarding.markOpacity), style: FillStyle(eoFill: true))
                .frame(width: RoomTokens.Onboarding.markSize, height: RoomTokens.Onboarding.markSize)
                .padding(.bottom, RoomTokens.Space.group)
            Text(RoomOnboardingCopy.emptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RoomTokens.Ink.graphite)
                .padding(.bottom, RoomTokens.Space.tight)
            Text(tooLarge ? RoomOnboardingCopy.tooLarge : RoomOnboardingCopy.emptyDetail)
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
