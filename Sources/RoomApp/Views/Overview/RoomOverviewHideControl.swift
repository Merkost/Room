import Foundation
import SwiftUI

nonisolated enum RoomOverviewPrivacy {
    static let key = "RoomHideSizes"
    static var menuTitle: String {
        String(localized: "menu.hideOverviewSizes", defaultValue: "Hide Sizes on Overview")
    }
}

struct RoomOverviewHideControl: View {
    @Binding var hidden: Bool

    var body: some View {
        Toggle(isOn: $hidden) {
            let title = hidden ? String(localized: "hide.on", defaultValue: "Hidden")
                : String(localized: "hide.button", defaultValue: "Hide")
            Label(title, systemImage: hidden ? "eye.slash" : "eye")
        }
        .toggleStyle(.button)
        .help(String(localized: "hide.overview.help", defaultValue: "Hide sizes on Overview. (⇧⌘H)"))
        .accessibilityLabel(RoomOverviewPrivacy.menuTitle)
        .accessibilityAddTraits(hidden ? .isSelected : [])
        .accessibilityIdentifier("RoomOverviewHide")
    }
}
