import SwiftUI

/// Step 3's three big icon tiles. Map my home folder is the one filled tile and the default action (Return);
/// Check caches and Watch memory are quiet. Hover lifts a tile, a press squashes it and it springs back.
struct RoomOnboardingTiles: View {
    let needsPicker: Bool
    let edition: RoomOnboardingEdition
    let enabled: Bool
    let focus: FocusState<RoomOnboardingChoice?>.Binding
    @Binding var hovered: RoomOnboardingChoice?
    let choose: (RoomOnboardingChoice) -> Void

    @Environment(\.roomAccent) private var accent

    private typealias Onboarding = RoomTokens.Onboarding

    var body: some View {
        HStack(spacing: Onboarding.tileGap) {
            ForEach(RoomOnboardingChoice.allCases, id: \.self) { choice in
                tile(choice)
            }
        }
        .frame(height: Onboarding.tileHeight)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Onboarding.disabledOpacity)
    }

    @ViewBuilder private func tile(_ choice: RoomOnboardingChoice) -> some View {
        let button = Button { choose(choice) } label: {
            VStack(spacing: RoomTokens.Space.inner) {
                Image(systemName: Self.glyph(choice))
                    .font(Onboarding.tileGlyph)
                    .frame(height: 36)
                Text(title(choice))
                    .font(RoomTokens.Typography.bodyStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, RoomTokens.Space.inner)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(RoomOnboardingTileStyle(filled: RoomOnboardingFlow.isProminent(choice), accent: accent,
                                             hovered: hovered == choice, focused: focus.wrappedValue == choice))
        .focused(focus, equals: choice)
        .onHover { inside in
            if inside { hovered = choice } else if hovered == choice { hovered = nil }
        }
        .accessibilityLabel(title(choice))
        .accessibilityHint(hint(choice))
        .accessibilityIdentifier(Self.identifier(choice))
        if RoomOnboardingFlow.isProminent(choice) {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    private func title(_ choice: RoomOnboardingChoice) -> String {
        switch choice {
        case .mapHome: RoomOnboardingCopy.mapTitle(needsPicker: needsPicker)
        case .checkCaches: RoomOnboardingCopy.cachesTitle(edition: edition)
        case .menuBar: RoomOnboardingCopy.menuBarTitle
        }
    }

    private func hint(_ choice: RoomOnboardingChoice) -> String {
        switch choice {
        case .mapHome: RoomOnboardingCopy.mapContext(edition: edition, needsPicker: needsPicker)
        case .checkCaches: RoomOnboardingCopy.cachesHint(edition: edition)
        case .menuBar: RoomOnboardingCopy.menuBarHint
        }
    }

    private static func glyph(_ choice: RoomOnboardingChoice) -> String {
        switch choice {
        case .mapHome: "house"
        case .checkCaches: "archivebox"
        case .menuBar: "memorychip"
        }
    }

    private static func identifier(_ choice: RoomOnboardingChoice) -> String {
        switch choice {
        case .mapHome: "RoomOnboardingMapHome"
        case .checkCaches: "RoomOnboardingCheckCaches"
        case .menuBar: "RoomOnboardingMenuBar"
        }
    }
}

/// A tile: filled in the accent (the screen's one filled control) or quiet on the group surface.
/// Hover lifts with a light spring, a press squashes; Reduce Motion keeps only the colour change.
private struct RoomOnboardingTileStyle: ButtonStyle {
    let filled: Bool
    let accent: RoomTokens.Accent
    let hovered: Bool
    let focused: Bool

    @Environment(\.roomMotion) private var motion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.group)
        let pressed = configuration.isPressed
        let scale: CGFloat = pressed ? RoomTokens.Onboarding.tilePress : (hovered ? RoomTokens.Onboarding.tileHover : 1)
        return configuration.label
            .foregroundStyle(filled ? Color.white : RoomTokens.Ink.graphite)
            .background {
                ZStack {
                    shape.fill(filled ? accent.fill : RoomTokens.Surface.group)
                    if !filled, hovered { shape.fill(accent.wash) }
                }
            }
            .overlay {
                shape.strokeBorder(filled ? Color.clear : (hovered ? accent.text : outline),
                                   lineWidth: hovered || contrast == .increased ? 1.5 : 1)
            }
            .overlay {
                if focused {
                    shape.inset(by: -4).strokeBorder(accent.text.opacity(0.7), lineWidth: 2)
                }
            }
            .contentShape(shape)
            .scaleEffect(motion.isFull ? scale : 1)
            .opacity(pressed && !motion.isFull ? 0.7 : 1)
            .animation(motion.isFull ? (pressed ? RoomTokens.Motion.quick : RoomTokens.Motion.bounce) : nil, value: pressed)
            .animation(motion.animation(RoomTokens.Motion.swell), value: hovered)
    }

    private var outline: Color {
        contrast == .increased ? RoomTokens.Ink.secondary : RoomTokens.Surface.line
    }
}
