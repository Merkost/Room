import SwiftUI

/// One look for everything that expands: the whole row is the control, a chevron turns, and the content sits under the
/// title. Set once per scene root, so every `DisclosureGroup` gets it.
struct RoomDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View { RoomDisclosureRow(configuration: configuration) }
}

private struct RoomDisclosureRow: View {
    let configuration: DisclosureGroupStyle.Configuration
    @Environment(\.roomMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: RoomTokens.Space.inner) {
                    Image(systemName: "chevron.right")
                        .font(RoomTokens.Typography.roomGlyph)
                        .foregroundStyle(RoomTokens.Ink.tertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: RoomTokens.Control.chevronColumn)
                        .accessibilityHidden(true)
                    configuration.label
                        .foregroundStyle(RoomTokens.Ink.graphite)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: RoomTokens.Control.height)
                .padding(.horizontal, RoomTokens.Space.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.row))
            .padding(.horizontal, -RoomTokens.Space.row)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) { configuration.content }
                    .padding(.leading, RoomTokens.Control.chevronColumn + RoomTokens.Space.inner)
                    .padding(.top, RoomTokens.Space.tight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }
}

/// One look for everything that drops down: a quiet filled capsule with its chevron.
struct RoomDropdownStyle: ButtonStyle {
    /// False when the same spot sometimes holds a plain button instead of a menu.
    var chevron = true

    func makeBody(configuration: Configuration) -> some View { Capsuled(configuration: configuration, chevron: chevron) }

    private struct Capsuled: View {
        let configuration: ButtonStyle.Configuration
        let chevron: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            HStack(spacing: RoomTokens.Space.tight) {
                configuration.label.lineLimit(1)
                if chevron {
                    Image(systemName: "chevron.down")
                        .font(RoomTokens.Typography.roomGlyph)
                        .foregroundStyle(RoomTokens.Ink.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .font(RoomTokens.Typography.bodyStrong)
            .foregroundStyle(RoomTokens.Ink.graphite)
            .padding(.horizontal, RoomTokens.Space.inner)
            .frame(minHeight: RoomTokens.Control.height)
            .background(hovering || configuration.isPressed ? RoomTokens.Surface.pill : RoomTokens.Surface.tile, in: Capsule())
            .overlay(Capsule().strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// For a `Menu` (or the plain button that stands in for one, with `chevron: false`).
    func roomDropdown(chevron: Bool = true) -> some View {
        menuStyle(.button).buttonStyle(RoomDropdownStyle(chevron: chevron)).menuIndicator(.hidden).fixedSize()
    }
}
