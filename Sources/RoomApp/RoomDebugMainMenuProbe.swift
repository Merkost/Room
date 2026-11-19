#if DEBUG
import AppKit

/// A child process runs the real SwiftUI app so the test sees AppKit's assembled menu.
@MainActor
enum RoomDebugMainMenuProbe {
    nonisolated struct Row: Codable, Sendable {
        let title: String
        let key: String
        let modifiers: UInt
        let enabled: Bool
        let alternate: Bool
    }

    nonisolated struct Menu: Codable, Sendable {
        let title: String
        let rows: [Row]
    }

    static func start() {
        guard let path = ProcessInfo.processInfo.environment["ROOM_MAIN_MENU_TEST_OUTPUT"] else { return }
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(5)
            var menus: [Menu] = []
            repeat {
                try? await Task.sleep(for: .milliseconds(50))
                menus = readMainMenu()
            } while !menus.contains(where: { $0.title == "View" && $0.rows.contains { $0.title == "Refresh Free Space" } })
                && ContinuousClock.now < deadline

            if let data = try? JSONEncoder().encode(menus) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }

    private static func readMainMenu() -> [Menu] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        mainMenu.update()
        return mainMenu.items.compactMap { item in
            guard let submenu = item.submenu, !item.isHidden else { return nil }
            submenu.update()
            let rows = submenu.items.filter { !$0.isSeparatorItem && !$0.isHidden }.map {
                Row(title: $0.title, key: $0.keyEquivalent, modifiers: $0.keyEquivalentModifierMask.rawValue,
                    enabled: $0.isEnabled, alternate: $0.isAlternate)
            }
            return Menu(title: item.title.isEmpty ? submenu.title : item.title, rows: rows)
        }
    }
}
#endif
