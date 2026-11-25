import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomShellRoutingTests {
    @Test func keyboardSelectionHasNoAnimation() {
        let navigation = RoomWindowNavigation()
        #expect(navigation.transaction(for: .keyboard).disablesAnimations)
        #expect(!navigation.transaction(for: .pointer).disablesAnimations)
    }

    @Test func restorableRawForActivityAndRooms() throws {
        let id = UUID()
        #expect(RoomDestination(rawValue: "activity") == nil)
        #expect(RoomRoute.room(id).restorableRaw == "disk")
        #expect(RoomRoute.savedView(id).restorableRaw == "disk")
        let encoded = try JSONEncoder().encode(RoomRoute.room(id))
        #expect(try JSONDecoder().decode(RoomRoute.self, from: encoded) == .room(id))
    }

    @Test func backAndForwardRoundTrip() throws {
        let suite = "RoomShellRouting-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let navigation = RoomWindowNavigation(defaults: defaults)
        navigation.select(.clean)
        navigation.select(.screen(.disk), origin: .keyboard)
        #expect(navigation.selectionOrigin == .keyboard)
        navigation.back()
        #expect(navigation.route == .screen(.clean) && navigation.canGoForward)
        #expect(navigation.selectionOrigin == .keyboard)
        navigation.forward()
        #expect(navigation.route == .screen(.disk) && !navigation.canGoForward)
        #expect(defaults.string(forKey: "RoomLastDestination") == "disk")
        navigation.select(.screen(.overview), origin: .pointer)
        #expect(navigation.selectionOrigin == .pointer)
    }

    @Test func backDisabledWhenModal() {
        let go = RoomMenuModel.make(.init(window: .modal, canGoBack: true, canGoForward: true))
        #expect(go.first { $0.id == .back }?.enabled == false)
        #expect(go.first { $0.id == .forward }?.enabled == false)
    }

    @Test func unpinnedRoomLeavesHistory() {
        let room = RoomRoute.room(UUID())
        var history = RoomNavigationHistory(current: .screen(.overview))
        history.visit(room)
        history.visit(.screen(.disk))
        history.goBack()
        history.remove(room, fallback: .screen(.disk))
        #expect(history.current == .screen(.disk))
        #expect(history.back == [.screen(.overview)])
        #expect(history.forward.isEmpty)
    }
}

struct RoomSidebarLayoutTests {
    @Test func autoIconsBelow900() {
        #expect(RoomSidebarLayout.mode(windowWidth: 899, userPrefersIcons: false) == .iconsOnly)
        #expect(RoomSidebarLayout.mode(windowWidth: 900, userPrefersIcons: false) == .labelled)
        #expect(RoomSidebarLayout.mode(windowWidth: 1000, userPrefersIcons: true) == .iconsOnly)
    }

    @Test func iconColumnDoesNotMove() {
        #expect(RoomSidebarLayout.iconLeading == 16)
        #expect(RoomSidebarLayout.width(.labelled) == 256)
        #expect(RoomSidebarLayout.width(.iconsOnly) == 62)
    }

    @Test func shortcutHintsOnlyLabelled() {
        #expect(RoomSidebarLayout.showsShortcutHints(.labelled))
        #expect(!RoomSidebarLayout.showsShortcutHints(.iconsOnly))
    }
}

struct RoomSidebarFootTests {
    @Test func belowGoalSpeaksShortfall() {
        let foot = RoomSidebarFoot.make(capacityBytes: 100, freeBytes: 20, goalBytes: 30,
                                        volumeName: "Data", hidden: false, format: { "\($0) GB" })
        #expect(foot.belowGoal)
        #expect(foot.freeText == "20 GB free")
        #expect(foot.accessibilityLabel == "Data, 20 GB free, 10 GB under your goal")
        #expect(foot.usedFraction == 0.8)
    }

    @Test func unreadableShowsNothing() {
        let foot = RoomSidebarFoot.make(capacityBytes: 100, freeBytes: nil, goalBytes: 30,
                                        volumeName: "Data", hidden: false, format: { "\($0) GB" })
        #expect(foot.freeText == nil && foot.volumeName == nil && foot.usedFraction == nil)
    }

    @Test func volumeNameNeverInvented() {
        let foot = RoomSidebarFoot.make(capacityBytes: 100, freeBytes: 30, goalBytes: 30,
                                        volumeName: nil, hidden: false, format: { "\($0) GB" })
        #expect(foot.volumeName == nil && !foot.belowGoal)
    }
}
