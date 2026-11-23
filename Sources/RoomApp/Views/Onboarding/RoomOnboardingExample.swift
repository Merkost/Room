import SwiftUI

/// Step 2's toy: three example rooms of dots and a small Trash. Click or flick a room and it hops into the Trash;
/// Put back springs it home. It only changes this drawing: its buttons send `.demoTrash` and `.demoPutBack`, which
/// never produce an effect, and nothing here calls a file, Trash, scan, picker or permission API
/// (`exampleNeverTouchesFiles`). The "Example" chip carries the honesty; its sentence is the tooltip and the label.
struct RoomOnboardingExample: View {
    let beat: RoomDemoBeat
    let trash: () -> Void
    let putBack: () -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Which room went in last; the reducer only knows that one did.
    @State private var chosen = 0
    @State private var hovered: Int?
    @State private var nudged = false
    @State private var landed = 0
    @State private var drag: (index: Int, offset: CGSize)?

    private typealias Onboarding = RoomTokens.Onboarding

    /// The example plan, in stage points (600 x 296): three rooms on the left, the Trash on the right.
    private static let rooms: [CGRect] = [
        CGRect(x: 32, y: 64, width: 184, height: 124),
        CGRect(x: 228, y: 64, width: 136, height: 124),
        CGRect(x: 32, y: 200, width: 332, height: 64),
    ]
    private static let trashCenter = CGPoint(x: 486, y: 136)
    private static let flick: CGFloat = 36

    private var holding: Bool { beat == .trashed }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.plan)
                .strokeBorder(contrast == .increased ? RoomTokens.Ink.secondary : RoomTokens.Surface.line2,
                              lineWidth: contrast == .increased ? 1.5 : Onboarding.wallStroke)
            chip
                .offset(x: RoomTokens.Space.group, y: RoomTokens.Space.group)
            ForEach(Self.rooms.indices, id: \.self) { index in
                ghost(index)
            }
            trashCan
            ForEach(Self.rooms.indices, id: \.self) { index in
                room(index)
            }
        }
        .frame(width: RoomOnboardingStage.width, height: RoomOnboardingStage.introWallHeight, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RoomOnboardingCopy.demoAccessibility(beat))
        .accessibilityHint(RoomOnboardingCopy.exampleLead)
        .accessibilityIdentifier("RoomOnboardingExample")
        .task {
            // One invitation, once: the first room hops in place. Never a loop.
            guard motion.isFull, beat == .review else { return }
            try? await Task.sleep(for: Onboarding.nudgeDelay)
            guard !Task.isCancelled, beat == .review else { return }
            withAnimation(RoomTokens.Motion.bounce) { nudged = true }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(RoomTokens.Motion.pop) { nudged = false }
        }
        .onChange(of: beat) { _, beat in
            guard beat == .trashed, motion.isFull else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                landed += 1
            }
        }
    }

    private var chip: some View {
        Label(RoomOnboardingCopy.exampleChip, systemImage: "hand.point.up.left")
            .font(RoomTokens.Typography.micro)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .padding(.horizontal, RoomTokens.Space.row)
            .frame(height: 20)
            .overlay { Capsule().strokeBorder(RoomTokens.Surface.line2) }
            .help(RoomOnboardingCopy.exampleOnly)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RoomOnboardingCopy.exampleOnly)
    }

    // MARK: Rooms

    private func isInTrash(_ index: Int) -> Bool { holding && chosen == index }

    /// Where a room was: a dashed outline while it sits in the Trash.
    private func ghost(_ index: Int) -> some View {
        let rect = Self.rooms[index]
        return RoundedRectangle(cornerRadius: RoomTokens.Radius.card)
            .strokeBorder(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: 1, dash: RoomTokens.OverviewPlan.dashedWall.dash))
            .frame(width: rect.width, height: rect.height)
            .opacity(isInTrash(index) ? 1 : 0)
            .animation(motion.animation(RoomTokens.Motion.standard), value: isInTrash(index))
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityHidden(true)
    }

    private func room(_ index: Int) -> some View {
        let rect = Self.rooms[index]
        let inTrash = isInTrash(index)
        let lifted = hovered == index && !holding
        let dragOffset = drag?.index == index ? drag?.offset ?? .zero : .zero
        let toTrash = CGSize(width: Self.trashCenter.x - rect.midX, height: Self.trashCenter.y - rect.midY)
        let travel = inTrash && motion.isFull ? toTrash : dragOffset
        let nudge = index == 0 && nudged ? -Onboarding.nudge : 0
        return Button {
            send(index)
        } label: {
            roomDrawing(rect.size, lifted: lifted)
        }
        .buttonStyle(.plain)
        .disabled(holding)
        .frame(width: rect.width, height: rect.height)
        .scaleEffect(inTrash ? (motion.isFull ? Onboarding.trashLanded : 1) : (lifted ? Onboarding.roomLift : 1))
        .opacity(inTrash ? 0 : 1)
        .offset(x: travel.width, y: travel.height + nudge)
        .animation(motion.animation(inTrash ? RoomTokens.Motion.hop : RoomTokens.Motion.pop), value: inTrash)
        .animation(motion.animation(RoomTokens.Motion.swell), value: lifted)
        .offset(x: rect.minX, y: rect.minY)
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .simultaneousGesture(flickGesture(index))
        .accessibilityLabel(RoomOnboardingCopy.exampleRoom)
        .accessibilityHint(RoomOnboardingCopy.exampleRoomHint)
        .accessibilityHidden(inTrash)
        .accessibilityIdentifier("RoomOnboardingExampleRoom\(index + 1)")
    }

    private func send(_ index: Int) {
        guard !holding else { return }
        chosen = index
        hovered = nil
        trash()
    }

    /// A flick towards the Trash sends the room; anything else springs back.
    private func flickGesture(_ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !holding, motion.isFull else { return }
                drag = (index, value.translation)
            }
            .onEnded { value in
                let thrown = value.predictedEndTranslation.width > Self.flick * 2 || value.translation.width > Self.flick
                withAnimation(motion.animation(RoomTokens.Motion.pop)) { drag = nil }
                if thrown { send(index) }
            }
    }

    private func roomDrawing(_ size: CGSize, lifted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.card)
        let pitch = Onboarding.examplePitch
        return ZStack {
            shape.fill(RoomTokens.Surface.group)
            Canvas { context, size in
                let columns = Int((size.width - pitch) / pitch), rows = Int((size.height - pitch) / pitch)
                let x0 = (size.width - CGFloat(columns - 1) * pitch) / 2, y0 = (size.height - CGFloat(rows - 1) * pitch) / 2
                var dots = Path()
                for row in 0..<max(rows, 1) {
                    for column in 0..<max(columns, 1) {
                        let r = Onboarding.exampleDot
                        dots.addEllipse(in: CGRect(x: x0 + CGFloat(column) * pitch - r, y: y0 + CGFloat(row) * pitch - r,
                                                   width: 2 * r, height: 2 * r))
                    }
                }
                context.fill(dots, with: .color(RoomTokens.Ink.secondary.opacity(lifted ? 0.85 : 0.45)))
            }
            .clipShape(shape)
            shape.strokeBorder(lifted ? accent.text : RoomTokens.Surface.line, lineWidth: lifted ? 1.5 : 1)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
    }

    // MARK: Trash and Put back

    private var trashCan: some View {
        VStack(spacing: RoomTokens.Space.group) {
            ZStack {
                Circle().fill(holding ? accent.wash : RoomTokens.Surface.group)
                Circle().strokeBorder(holding ? accent.text : RoomTokens.Surface.line2, lineWidth: holding ? 1.5 : 1)
                Image(systemName: holding ? "trash.fill" : "trash")
                    .font(Onboarding.trashGlyph)
                    .foregroundStyle(holding ? accent.text : RoomTokens.Ink.secondary)
                    .contentTransition(motion.isFull ? .symbolEffect(.replace) : .identity)
                    .symbolEffect(.bounce, options: .nonRepeating, value: landed)
            }
            .frame(width: Onboarding.trashSize, height: Onboarding.trashSize)
            .animation(motion.animation(RoomTokens.Motion.standard), value: holding)
            .accessibilityHidden(true)
            Button(action: putBack) {
                Label(RoomOnboardingCopy.putBack, systemImage: "arrow.uturn.backward")
                    .font(RoomTokens.Typography.bodyStrong)
                    .padding(.horizontal, RoomTokens.Space.group)
                    .frame(minHeight: 30)
                    .overlay { Capsule().strokeBorder(accent.text.opacity(0.6)) }
                    .contentShape(Capsule())
            }
            .roomLink(accent)
            .opacity(holding ? 1 : 0)
            .scaleEffect(holding || !motion.isFull ? 1 : 0.8)
            .animation(motion.animation(RoomTokens.Motion.pop.delay(holding ? 0.18 : 0)), value: holding)
            .disabled(!holding)
            .accessibilityHidden(!holding)
            .accessibilityIdentifier("RoomOnboardingPutBack")
        }
        .frame(width: 200)
        .position(x: Self.trashCenter.x, y: Self.trashCenter.y + 23)
    }
}
