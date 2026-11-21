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
            let activationTimeout = ProcessInfo.processInfo.environment["ROOM_MAIN_MENU_ACTIVATION_TIMEOUT"]
                .flatMap(Int.init) ?? 60
            let deadline = ContinuousClock.now + .seconds(activationTimeout)
            var menus: [Menu] = []
            repeat {
                try? await Task.sleep(for: .milliseconds(50))
                if NSApp.keyWindow?.identifier != RoomApplicationDelegate.primaryWindowID,
                   let window = NSApp.windows.first(where: { $0.identifier == RoomApplicationDelegate.primaryWindowID }) {
                    NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    NSApp.activate()
                    window.makeMain()
                    window.makeKeyAndOrderFront(nil)
                }
                menus = readMainMenu()
            } while !menus.contains(where: { menu in
                guard menu.title == "View" else { return false }
                let titles = menu.rows.map(\.title)
                return titles.contains("Refresh Free Space") && titles.contains("Customise Overview…")
                    && titles.contains(where: { $0.contains("Full Screen") })
            })
                && ContinuousClock.now < deadline

            let state = NSApp.windows.map { window in
                [window.identifier?.rawValue ?? "unidentified", "key=\(window.isKeyWindow)",
                 "visible=\(window.isVisible)", "sheet=\(window.attachedSheet != nil)"].joined(separator: " ")
            }.joined(separator: "\n")
            let diagnostic = "active=\(NSApp.isActive) context=\(RoomCommandWindowContext.current)\n" + state
            try? diagnostic.write(to: URL(fileURLWithPath: path).appendingPathExtension("state"), atomically: true, encoding: .utf8)
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
