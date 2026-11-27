import RoomCore
import SwiftUI

/// The top bar's right end: Go to, History and Settings.
struct RoomTopBarActions: View {
    let model: RoomViewModel
    let destination: RoomDestination
    let openGoTo: () -> Void
    let show: (RoomDestination) -> Void
    let restore: (RoomActivity) -> Void

    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(spacing: RoomTokens.Space.tight) {
            Button(action: openGoTo) {
                icon(on: false) { RoomGlyphView(glyph: .search, size: 14, weight: 1.6) }
            }
            .help("Go to (⌘K)")
            .accessibilityLabel("Go to")
            .accessibilityHint("Command K")
            .accessibilityIdentifier("RoomGoTo")
            RoomHistoryButton(model: model, show: { show(.history) }, restore: restore)
                .frame(width: RoomTokens.Dock.barIcon, height: RoomTokens.Dock.barIcon)
                .background { if destination == .history { Circle().fill(accent.wash) } }
                .foregroundStyle(destination == .history ? accent.text : RoomTokens.Ink.secondary)
                .accessibilityAddTraits(destination == .history ? [.isSelected] : [])
                .accessibilityIdentifier("RoomNavigation-history")
            Button { show(.settings) } label: {
                icon(on: destination == .settings) { RoomGlyphView(glyph: .settings) }
            }
            .help("Settings (⌘7)")
            .accessibilityLabel(RoomPlacePlan.title(.settings))
            .accessibilityAddTraits(destination == .settings ? [.isSelected] : [])
            .accessibilityIdentifier("RoomNavigation-settings")
        }
        .buttonStyle(RoomPressStyle())
    }

    private func icon<Glyph: View>(on: Bool, @ViewBuilder glyph: () -> Glyph) -> some View {
        glyph()
            .foregroundStyle(on ? accent.text : RoomTokens.Ink.secondary)
            .frame(width: RoomTokens.Dock.barIcon, height: RoomTokens.Dock.barIcon)
            .background { if on { Circle().fill(accent.wash) } }
            .contentShape(Circle())
    }
}
