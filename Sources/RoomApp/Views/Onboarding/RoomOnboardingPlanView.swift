import SwiftUI

/// The person's own Mac as rings (steps 1 and 3). Geometry is the shared `RoomDotPlan` (the same centres Overview
/// draws); only `RoomVolumeCapacity` is drawn: free rings and one dashed Not mapped area. No kind, colour or count.
/// The rings pop in once in a diagonal wave and swell under the pointer, then relax. Nothing moves at rest.
struct RoomOnboardingPlanView: View {
    let plan: RoomOverviewPlanInput
    /// The wall's outer size; the plan sits inside it with `RoomOnboardingStage.pad`.
    let size: CGSize
    let hidden: Bool
    /// Step 3: the Not mapped area is where rooms will appear; it lights while Map my home folder is in play.
    var highlight = false

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false
    @State private var pointer: CGPoint?

    private typealias Tokens = RoomTokens.OverviewPlan
    private typealias Onboarding = RoomTokens.Onboarding
    private var pad: CGFloat { RoomOnboardingStage.pad }

    var body: some View {
        let inner = CGSize(width: size.width - 2 * pad, height: size.height - 2 * pad)
        let layout = plan.layout(size: inner)
        let free = layout.dots.filter { $0.room == .free }.map(\.center)
        let spacing = Self.spacing(free, fallback: layout.pitch)
        let radius = min(spacing * Onboarding.ringRadiusFactor, Onboarding.ringRadiusMax)
        let notMapped = layout.rooms.first { $0.id == .notMapped }?.rect.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap)
        let wave = Self.wave(free)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.plan)
                .strokeBorder(wallInk, lineWidth: contrast == .increased ? 1.5 : Onboarding.wallStroke)
            ZStack(alignment: .topLeading) {
                if let notMapped, !notMapped.isEmpty {
                    notMappedArea(notMapped, pitch: spacing, anchor: free.first ?? notMapped.origin)
                        .opacity(appeared ? 1 : 0)
                        .animation(motion.isFull ? RoomTokens.Motion.standard.delay(RoomTokens.Motion.popSpread / 2)
                                                 : RoomTokens.Motion.fade, value: appeared)
                }
                ForEach(free.indices, id: \.self) { index in
                    ring(at: free[index], radius: radius, delay: wave(free[index]))
                }
            }
            .frame(width: inner.width, height: inner.height, alignment: .topLeading)
            .padding(pad)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard motion.isFull else { return }
            switch phase {
            case .active(let location): pointer = CGPoint(x: location.x - pad, y: location.y - pad)
            case .ended: pointer = nil
            }
        }
        .onAppear { Task { @MainActor in appeared = true } }
    }

    private func ring(at center: CGPoint, radius: CGFloat, delay: TimeInterval) -> some View {
        let swell = swell(at: center)
        return Circle()
            .strokeBorder(swell > 1.05 ? RoomTokens.Ink.graphite : freeInk, lineWidth: Onboarding.ringStroke)
            .frame(width: 2 * radius, height: 2 * radius)
            .scaleEffect(swell)
            .animation(motion.isFull ? RoomTokens.Motion.swell : nil, value: swell)
            .scaleEffect(appeared || !motion.isFull ? 1 : Onboarding.ringPopFrom)
            .opacity(appeared ? 1 : 0)
            .animation(motion.isFull ? RoomTokens.Motion.pop.delay(delay) : RoomTokens.Motion.fade, value: appeared)
            .position(center)
    }

    /// 1 at rest; up to 1 + gain for the ring under the pointer, easing out over `swellReach`.
    private func swell(at center: CGPoint) -> CGFloat {
        guard let pointer, motion.isFull else { return 1 }
        let distance = hypot(center.x - pointer.x, center.y - pointer.y)
        let reach = max(0, 1 - distance / Onboarding.swellReach)
        return 1 + Onboarding.swellGain * reach * reach
    }

    /// The lattice step the rings actually sit on (the plan may tighten its nominal pitch to fit a short wall).
    private static func spacing(_ centers: [CGPoint], fallback: CGFloat) -> CGFloat {
        guard let first = centers.first else { return fallback }
        let nearest = centers.dropFirst().map { hypot($0.x - first.x, $0.y - first.y) }.filter { $0 > 0.5 }.min()
        return min(nearest ?? fallback, fallback)
    }

    /// The pop-in order: a diagonal wave from the top-left ring, spread over `popSpread`.
    private static func wave(_ centers: [CGPoint]) -> (CGPoint) -> TimeInterval {
        let sums = centers.map { $0.x + $0.y }
        let low = sums.min() ?? 0, high = sums.max() ?? 0
        let span = max(high - low, 1)
        return { center in RoomTokens.Motion.popSpread * Double((center.x + center.y - low) / span) }
    }

    private var freeInk: Color {
        RoomTokens.Ink.secondary.opacity(contrast == .increased ? 1 : RoomTokens.Dots.freeRingOpacity)
    }

    private var wallInk: Color {
        contrast == .increased ? RoomTokens.Ink.secondary : RoomTokens.Surface.line2
    }

    private var neutralOutline: Color {
        RoomTokens.Ink.secondary.opacity(contrast == .increased ? 1 : Onboarding.notMappedOpacity)
    }

    /// Used space: one quiet point per lattice position on the rings' own pitch, so the disk reads as one field.
    private func notMappedArea(_ rect: CGRect, pitch: CGFloat, anchor: CGPoint) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.card)
        let step = max(pitch, 4)
        let first = CGPoint(x: anchor.x + ((rect.minX + step / 3 - anchor.x) / step).rounded(.up) * step - rect.minX,
                            y: anchor.y + ((rect.minY + step / 3 - anchor.y) / step).rounded(.up) * step - rect.minY)
        let point = Onboarding.usedPoint
        let ink = RoomTokens.Ink.secondary.opacity(contrast == .increased ? 0.8 : Onboarding.usedPointOpacity)
        return ZStack {
            shape.fill(accent.wash).opacity(highlight ? 1 : 0)
            Canvas { context, size in
                var grid = Path()
                for y in stride(from: first.y, through: size.height - step / 3, by: step) {
                    for x in stride(from: first.x, through: size.width - step / 3, by: step) {
                        grid.addEllipse(in: CGRect(x: x - point, y: y - point, width: 2 * point, height: 2 * point))
                    }
                }
                context.fill(grid, with: .color(ink))
            }
            .clipShape(shape)
            shape.stroke(highlight ? accent.text : neutralOutline,
                         style: StrokeStyle(lineWidth: highlight ? 1.5 : Tokens.dashedWall.lineWidth,
                                            dash: Tokens.dashedWall.dash))
        }
        .frame(width: rect.width, height: rect.height)
        .scaleEffect(highlight && motion.isFull ? 1.006 : 1)
        .animation(motion.animation(RoomTokens.Motion.bounce), value: highlight)
        .help(highlight ? RoomOnboardingCopy.hint : RoomOnboardingCopy.notMappedDetail(plan, hidden: hidden, format: RoomFormat.gb))
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// Unreadable capacity or a disk over 26 TB: no plan, no ring, no number; the mark in a dashed wall.
struct RoomOnboardingPlanUnavailable: View {
    let size: CGSize

    @Environment(\.roomMotion) private var motion
    @State private var appeared = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.plan)
                .strokeBorder(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: 1, dash: RoomTokens.OverviewPlan.dashedWall.dash))
            RoomMark()
                .fill(RoomTokens.Ink.secondary.opacity(RoomTokens.Onboarding.markOpacity), style: FillStyle(eoFill: true))
                .frame(width: RoomTokens.Onboarding.markSize, height: RoomTokens.Onboarding.markSize)
                .scaleEffect(appeared || !motion.isFull ? 1 : RoomTokens.Onboarding.ringPopFrom)
                .opacity(appeared ? 1 : 0)
                .animation(motion.isFull ? RoomTokens.Motion.pop : RoomTokens.Motion.fade, value: appeared)
        }
        .frame(width: size.width, height: size.height)
        .onAppear { Task { @MainActor in appeared = true } }
        .allowsHitTesting(false)
    }
}
