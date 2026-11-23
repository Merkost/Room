import SwiftUI

struct RoomCachesRow: View {
    let source: RoomSource
    let displayedBytes: Int64
    let selected: Bool
    let partiallySelected: Bool
    let canSelect: Bool
    let focus: FocusState<String?>.Binding
    let format: (Int64) -> String
    let select: () -> Void
    let inspect: () -> Void
    let reveal: () -> Void
    var neverSuggest: (() -> Void)?

    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @Environment(\.roomAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: RoomTokens.Space.row) {
            Button(action: canSelect ? select : inspect) {
                HStack(spacing: RoomTokens.Space.row) {
                    if canSelect {
                        if partiallySelected {
                            Image(systemName: "minus.square.fill")
                                .foregroundStyle(accent.text)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                        } else {
                            RoomSelectionCheckmark(selected: selected, color: accent.text)
                                .frame(width: 14)
                        }
                    } else {
                        Image(systemName: "lock.fill")
                            .font(RoomTokens.Typography.micro)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: source.symbol)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(accent.text)
                        .frame(width: RoomTokens.Space.breath1, height: RoomTokens.Space.breath1)
                        .background(accent.wash, in: .rect(cornerRadius: RoomTokens.Radius.field))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(RoomTokens.Typography.section)
                        if let reason = source.blockedReason {
                            Text(reason)
                                .font(RoomTokens.Typography.caption)
                                .foregroundStyle(RoomTokens.Ink.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: RoomTokens.Space.row)
                    Text("\(source.isPartial ? "≥ " : "")\(format(displayedBytes))")
                        .font(RoomTokens.Typography.section.monospacedDigit())
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RoomHoverButtonStyle())
            .focused(focus, equals: source.id)
            .onKeyPress(.space) {
                if canSelect { select(); return .handled }
                return .ignored
            }
            .accessibilityLabel(hidden ? "\(source.name), size hidden" :
                "\(source.name), \(format(displayedBytes)), \(source.cleanupConsequences.first ?? source.blockedReason ?? source.subtitle)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(canSelect ? (partiallySelected ? "Some items selected" : selected ? "Selected" : "Not selected") : "Kept")
            Button(action: inspect) {
                Image(systemName: "info.circle")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoomHoverButtonStyle())
            .accessibilityLabel("Inspect \(source.name)")
            .keyboardShortcut(focus.wrappedValue == source.id ? KeyboardShortcut("i", modifiers: .command) : nil)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(contrast == .increased ? RoomTokens.Surface.line2 : RoomTokens.Surface.line).frame(height: 1)
        }
        .contextMenu {
            Button("Show in Finder", action: reveal)
            if let neverSuggest { Button("Never Suggest This", action: neverSuggest) }
            Button("Inspect", action: inspect)
        }
    }
}
