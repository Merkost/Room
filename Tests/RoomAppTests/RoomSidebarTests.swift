import Foundation
import SwiftUI
import Testing
@testable import RoomApp

@MainActor
struct RoomSidebarTests {
    @Test func symbolsMatchDSMap() {
        // BRAND-DS §7.2 / spec 02 §9: Caches is archivebox, Developer is hammer; Overview keeps the custom mark.
        let symbols = Dictionary(uniqueKeysWithValues: RoomSidebar.items.map { ($0.destination, $0.symbol) })
        #expect(symbols[.disk] == "square.grid.2x2")
        #expect(symbols[.clean] == "archivebox")
        #expect(symbols[.developer] == "hammer")
        #expect(symbols[.memory] == "memorychip")
        #expect(!symbols.values.contains("sparkles") && !symbols.values.contains("shippingbox"))
    }

    @Test func sidebarFootHiddenOnOverview() {
        #expect(!RoomSidebarFoot.isShown(route: .screen(.overview), labelled: true),
                "the Overview answer already shows the free space")
        for destination in [RoomDestination.disk, .clean, .developer, .memory] {
            #expect(RoomSidebarFoot.isShown(route: .screen(destination), labelled: true))
        }
        #expect(RoomSidebarFoot.isShown(route: .room(UUID()), labelled: true))
        #expect(!RoomSidebarFoot.isShown(route: .screen(.memory), labelled: false), "icons-only sidebar has no foot")
    }

    @Test func keyboardSelectionHasNoTransaction() {
        let full = RoomMotionPolicy(gentleMotion: true, reduceMotion: false)
        let reduced = RoomMotionPolicy(gentleMotion: true, reduceMotion: true)
        #expect(RoomSidebar.selectionAnimation(origin: .keyboard, motion: full) == nil)
        #expect(RoomSidebar.selectionAnimation(origin: .programmatic, motion: full) == nil)
        #expect(RoomSidebar.selectionAnimation(origin: .pointer, motion: full) == RoomTokens.Motion.standard)
        #expect(RoomSidebar.selectionAnimation(origin: .pointer, motion: reduced) == nil, "Reduce Motion drops the travel")

        let defaults = UserDefaults(suiteName: "RoomSidebarTests-\(UUID().uuidString)")!
        let navigation = RoomWindowNavigation(defaults: defaults)
        let transaction = navigation.transaction(for: .keyboard)
        #expect(transaction.disablesAnimations && transaction.animation == nil)
        navigation.select(.screen(.memory), origin: .keyboard)
        #expect(navigation.selectionOrigin == .keyboard)
    }

    @Test func shortcutHintsOnlyOnHoverOrCommand() {
        #expect(!RoomSidebar.showsShortcut(hovered: false, commandHeld: false))
        #expect(RoomSidebar.showsShortcut(hovered: true, commandHeld: false))
        #expect(RoomSidebar.showsShortcut(hovered: false, commandHeld: true))
    }
}
