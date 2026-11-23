import SwiftUI

/// Step 2's example: review, Trash with a receipt, Put back (ONBOARDING-V3-SPEC §3.3, MV-6, MV-7).
/// Static drawings marked "Example" with no sizes. Its only button is Put back, which changes the drawing and calls
/// no file, Trash, scan, picker or permission API (`exampleNeverTouchesFiles`).
struct RoomOnboardingExample: View {
    let layout: RoomDemoLayout
    let putBack: () -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    private typealias Onboarding = RoomTokens.Onboarding
    private typealias T = RoomOnboardingText

    private var beat: RoomDemoBeat {
        switch layout {
        case .single(let beat): beat
        case .triptych(let highlight): highlight
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            chip
                .offset(x: Onboarding.chipOrigin.x, y: Onboarding.chipOrigin.y)
            switch layout {
            case .single(let beat):
                panel(beat)
                    .frame(width: Onboarding.exampleSize.width, height: Onboarding.exampleSize.height)
                    .offset(x: Onboarding.exampleOrigin.x, y: Onboarding.exampleOrigin.y)
                rail(current: beat)
                    .frame(width: Onboarding.railWidth, alignment: .topLeading)
                    .offset(x: Onboarding.railX, y: Onboarding.exampleOrigin.y)
            case .triptych(let highlight):
                triptych(highlight: highlight)
                    .padding(.horizontal, Onboarding.triptychInset)
                    .offset(y: Onboarding.triptychTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RoomOnboardingCopy.demoAccessibility(beat))
        .accessibilityIdentifier("RoomOnboardingExample")
    }

    private var chip: some View {
        Text(T.string("onboarding.v3.example.chip", "Example"))
            .font(RoomTokens.Typography.micro)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .padding(.horizontal, RoomTokens.Space.row)
            .frame(height: 18)
            .overlay { Capsule().strokeBorder(RoomTokens.Surface.line2) }
            .accessibilityHidden(true)
    }

    // MARK: Full motion: one card that changes beat

    private func panel(_ beat: RoomDemoBeat) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.group)
        return ZStack(alignment: .topLeading) {
            switch beat {
            case .review:
                reviewDrawing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(motion.isFull ? .opacity.combined(with: .offset(x: 12)) : .opacity)
            case .trashed:
                trashedDrawing
                    .transition(.opacity)
            case .restored:
                restoredDrawing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(motion.isFull ? .opacity.combined(with: .offset(y: 6)) : .opacity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, RoomTokens.Space.group)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoomTokens.Surface.group, in: shape)
        .overlay { shape.strokeBorder(RoomTokens.Surface.line) }
    }

    private var reviewDrawing: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.row) {
                checkbox
                Text(T.string("onboarding.v3.example.row.name", "DerivedData"))
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                Spacer(minLength: RoomTokens.Space.row)
                Text(T.string("onboarding.v3.example.row.kind", "Xcode cache"))
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            moveCapsule
        }
    }

    private var checkbox: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 16, height: 16)
            .background(accent.fill, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }

    private var moveCapsule: some View {
        Text(T.string("onboarding.v3.example.move", "Move to Trash"))
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Ink.graphite)
            .padding(.horizontal, RoomTokens.Space.row + 2)
            .frame(height: 24)
            .overlay { Capsule().strokeBorder(RoomTokens.Surface.line2) }
    }

    private var trashedDrawing: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RoomTokens.Space.row) {
                Image(systemName: "trash").foregroundStyle(RoomTokens.Ink.secondary).accessibilityHidden(true)
                Text(T.string("onboarding.v3.example.moved", "Moved to Trash"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoomTokens.Ink.graphite)
                Spacer(minLength: RoomTokens.Space.row)
                putBackButton
            }
            Rectangle().fill(RoomTokens.Surface.line).frame(height: 1)
                .padding(.vertical, RoomTokens.Space.row + 4)
            VStack(spacing: 6) {
                line(T.string("onboarding.v3.example.row.name", "DerivedData"), T.string("onboarding.v3.example.row.kind", "Xcode cache"))
                line(T.string("onboarding.v3.example.row.where", "Now in"), T.string("onboarding.v3.example.row.trash", "Trash"))
                line(T.string("onboarding.v3.example.row.receipt", "Receipt"), T.string("onboarding.v3.example.row.kept", "Kept in History"))
            }
            Text(T.string("onboarding.v3.example.foot", "Room never empties the Trash. That stays yours."))
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(.top, RoomTokens.Space.row + 4)
        }
    }

    private var restoredDrawing: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row + 4) {
            HStack(spacing: RoomTokens.Space.row) {
                Image(systemName: "folder").foregroundStyle(RoomTokens.Ink.secondary).accessibilityHidden(true)
                Text(T.string("onboarding.v3.example.back", "Back where it was"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoomTokens.Ink.graphite)
            }
            line(T.string("onboarding.v3.example.row.name", "DerivedData"), T.string("onboarding.v3.example.row.restored", "Restored"))
        }
    }

    private var putBackButton: some View {
        Button(action: putBack) {
            Label(T.string("onboarding.v3.example.putBack", "Put back"), systemImage: "arrow.uturn.backward")
                .font(RoomTokens.Typography.body)
                .frame(minWidth: 72, minHeight: RoomTokens.Sidebar.minimumTarget)
        }
        .roomLink(accent)
        .accessibilityIdentifier("RoomOnboardingPutBack")
    }

    private func line(_ name: String, _ value: String) -> some View {
        HStack(alignment: .center, spacing: RoomTokens.Space.tight) {
            Text(name).foregroundStyle(RoomTokens.Ink.graphite).fixedSize()
            RoomOnboardingLeader()
                .stroke(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                .frame(height: 1)
                .frame(minWidth: RoomTokens.Space.tight)
            Text(value).foregroundStyle(RoomTokens.Ink.secondary).fixedSize()
        }
        .font(RoomTokens.Typography.body)
        .lineLimit(1)
        .frame(minHeight: 18)
    }

    // MARK: Rail

    private func rail(current: RoomDemoBeat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(RoomDemoBeat.allCases, id: \.rawValue) { item in
                railItem(item, current: current)
            }
        }
        .accessibilityHidden(true)
    }

    private func railItem(_ item: RoomDemoBeat, current: RoomDemoBeat) -> some View {
        let isCurrent = item == current
        let isDone = item.rawValue < current.rawValue
        return HStack(alignment: .top, spacing: RoomTokens.Space.row + 4) {
            VStack(spacing: 4) {
                bead(done: isDone, current: isCurrent, size: Onboarding.bead)
                if item != .restored {
                    Rectangle().fill(RoomTokens.Surface.line2).frame(width: 1)
                }
            }
            .frame(width: Onboarding.bead)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.railTitle(item))
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent || isDone ? RoomTokens.Ink.graphite : RoomTokens.Ink.secondary)
                Text(Self.railDetail(item))
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .lineLimit(1)
        }
        .frame(height: Onboarding.railItem, alignment: .top)
    }

    private func bead(done: Bool, current: Bool, size: CGFloat) -> some View {
        ZStack {
            if done {
                Circle().fill(accent.fill)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white)
            } else if current {
                Circle().strokeBorder(accent.text, lineWidth: 1.5)
                Circle().fill(accent.text).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(RoomTokens.Surface.line2, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .animation(motion.animation(RoomTokens.Motion.quick), value: done)
        .animation(motion.animation(RoomTokens.Motion.quick), value: current)
    }

    private static func railTitle(_ beat: RoomDemoBeat) -> String {
        switch beat {
        case .review: T.string("onboarding.v3.rail.1", "You review first")
        case .trashed: T.string("onboarding.v3.rail.2", "Trash, with a receipt")
        case .restored: T.string("onboarding.v3.rail.3", "You can put it back")
        }
    }

    private static func railDetail(_ beat: RoomDemoBeat) -> String {
        switch beat {
        case .review: T.string("onboarding.v3.rail.1.detail", "Nothing is picked for you.")
        case .trashed: T.string("onboarding.v3.rail.2.detail", "Every move is written down.")
        case .restored: T.string("onboarding.v3.rail.3.detail", "Try it: press Put back.")
        }
    }

    // MARK: Reduce Motion / Gentle off: three still cards, no auto-play

    private func triptych(highlight: RoomDemoBeat) -> some View {
        HStack(alignment: .top, spacing: Onboarding.triptychGap) {
            ForEach(RoomDemoBeat.allCases, id: \.rawValue) { item in
                triptychCard(item, highlighted: item == highlight)
            }
        }
        .frame(height: Onboarding.exampleSize.height, alignment: .top)
    }

    private func triptychCard(_ item: RoomDemoBeat, highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.group)
        return VStack(alignment: .leading, spacing: RoomTokens.Space.row + 2) {
            HStack(spacing: RoomTokens.Space.row) {
                Text(verbatim: "\(item.rawValue)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(accent.text)
                    .frame(width: Onboarding.triptychBead, height: Onboarding.triptychBead)
                    .overlay { Circle().strokeBorder(accent.text, lineWidth: 1.5) }
                Text(Self.railTitle(item))
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    .lineLimit(1)
            }
            .accessibilityHidden(true)
            triptychDrawing(item)
                .padding(.horizontal, RoomTokens.Space.row + 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoomTokens.Surface.group, in: shape)
                .overlay {
                    shape.strokeBorder(highlighted ? accent.text : RoomTokens.Surface.line, lineWidth: 1)
                        .animation(motion.animation(RoomTokens.Motion.fade), value: highlighted)
                }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func triptychDrawing(_ item: RoomDemoBeat) -> some View {
        switch item {
        case .review:
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                HStack(spacing: RoomTokens.Space.row) {
                    checkbox
                    Text(T.string("onboarding.v3.example.row.name", "DerivedData"))
                        .font(RoomTokens.Typography.body)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                }
                moveCapsule
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .trashed:
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                HStack(spacing: RoomTokens.Space.tight) {
                    Image(systemName: "trash").foregroundStyle(RoomTokens.Ink.secondary).accessibilityHidden(true)
                    Text(T.string("onboarding.v3.example.moved", "Moved to Trash"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoomTokens.Ink.graphite)
                }
                line(T.string("onboarding.v3.example.row.receipt", "Receipt"), T.string("onboarding.v3.example.row.keptShort", "Kept"))
                putBackButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .restored:
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                HStack(spacing: RoomTokens.Space.tight) {
                    Image(systemName: "folder").foregroundStyle(RoomTokens.Ink.secondary).accessibilityHidden(true)
                    Text(T.string("onboarding.v3.example.back", "Back where it was"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoomTokens.Ink.graphite)
                }
                line(T.string("onboarding.v3.example.row.name", "DerivedData"), T.string("onboarding.v3.example.row.restored", "Restored"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A dotted leader between a receipt line's name and value.
nonisolated struct RoomOnboardingLeader: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
