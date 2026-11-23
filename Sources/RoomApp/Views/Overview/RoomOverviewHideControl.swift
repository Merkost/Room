import Foundation
import SwiftUI

nonisolated enum RoomOverviewPrivacy {
    static let key = "RoomHideSizes"
    static var menuTitle: String {
        String(localized: "menu.hideOverviewSizes", defaultValue: "Hide Sizes on Overview")
    }
}
