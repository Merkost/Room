import Foundation

/// Room's commands and the native rows they share shortcuts with.
nonisolated enum RoomMenuModel {
    enum Section: String, CaseIterable, Sendable {
        case room = "Room", file = "File", edit = "Edit", view = "View", go = "Go"
        case window = "Window", help = "Help", debug = "Debug"

        var title: String {
            switch self {
            case .go: String(localized: "menu.go", defaultValue: "Go")
            case .debug: String(localized: "menu.debug", defaultValue: "Debug")
            default: rawValue
            }
        }
    }

    enum ID: String, CaseIterable, Sendable {
        case about
        case settings
        case monitor
        case services
        case hideApp
        case hideOthers
        case showAll
        case quit
        case quitKeepingWindows
        case pin
        case trash
        case close
        case closeAll
        case undo
        case redo
        case cut
        case copy
        case paste
        case delete
        case selectAll
        case autoFill
        case dictation
        case emoji
        case refreshOverview
        case hideOverviewSizes
        case rescanDisk
        case rescanCaches
        case rescanDeveloper
        case refreshMemory
        case stop
        case fullScreen
        case sidebarLabels
        case back
        case forward
        case overview
        case disk
        case caches
        case developer
        case memory
        case activity
        case enclosing
        case minimize
        case minimizeAll
        case zoom
        case zoomAll
        case fill
        case center
        case moveResize
        case fullScreenTile
        case front
        case arrangeInFront
        case removeWindowSet
        case welcome
        case support
        case privacy
        case helpSearch
        case systemHelp
        case feedback
        case debugState
        case debugLive
        case debugNormal
        case debugElevated
        case debugCritical
        case debugBelowGoal
        case debugBoth
        case debugStacked
        case debugIcon

        var title: String {
            switch self {
            case .about: "About Room"
            case .settings: "Settings…"
            case .monitor: String(localized: "menu.monitor", defaultValue: "Show Monitor")
            case .services: "Services"
            case .hideApp: "Hide Room"
            case .hideOthers: "Hide Others"
            case .showAll: "Show All"
            case .quit: "Quit Room"
            case .quitKeepingWindows: "Quit and Keep Windows"
            case .pin: String(localized: "menu.pin", defaultValue: "Pin Folder as a Room…")
            case .trash: String(localized: "menu.trash", defaultValue: "Open Trash")
            case .close: "Close"
            case .closeAll: "Close All"
            case .undo: "Undo"
            case .redo: "Redo"
            case .cut: "Cut"
            case .copy: "Copy"
            case .paste: "Paste"
            case .delete: "Delete"
            case .selectAll: "Select All"
            case .autoFill: "AutoFill"
            case .dictation: "Start Dictation"
            case .emoji: "Emoji & Symbols"
            case .refreshOverview: String(localized: "menu.refreshOverview", defaultValue: "Refresh Free Space")
            case .hideOverviewSizes: RoomOverviewPrivacy.menuTitle
            case .rescanDisk: String(localized: "menu.rescanDisk", defaultValue: "Rescan Disk Map")
            case .rescanCaches: String(localized: "menu.rescanCaches", defaultValue: "Check Caches Again")
            case .rescanDeveloper: String(localized: "menu.rescanDeveloper", defaultValue: "Rescan Developer")
            case .refreshMemory: String(localized: "menu.refreshMemory", defaultValue: "Refresh Memory")
            case .stop: String(localized: "menu.stop", defaultValue: "Stop Scan")
            case .fullScreen: "Enter Full Screen"
            case .sidebarLabels: String(localized: "menu.sidebarLabels.hide", defaultValue: "Hide Sidebar Labels", bundle: RoomCopy.bundle)
            case .back: String(localized: "menu.back", defaultValue: "Back", bundle: RoomCopy.bundle)
            case .forward: String(localized: "menu.forward", defaultValue: "Forward", bundle: RoomCopy.bundle)
            case .overview: String(localized: "menu.overview", defaultValue: "Overview")
            case .disk: String(localized: "menu.disk", defaultValue: "Disk Map")
            case .caches: String(localized: "menu.caches", defaultValue: "Caches")
            case .developer: String(localized: "menu.developer", defaultValue: "Developer")
            case .memory: String(localized: "menu.memory", defaultValue: "Memory")
            case .activity: String(localized: "menu.activity", defaultValue: "Activity")
            case .enclosing: String(localized: "menu.enclosing", defaultValue: "Enclosing Folder")
            case .minimize: "Minimize"
            case .minimizeAll: "Minimize All"
            case .zoom: "Zoom"
            case .zoomAll: "Zoom All"
            case .fill: "Fill"
            case .center: "Center"
            case .moveResize: "Move & Resize"
            case .fullScreenTile: "Full Screen Tile"
            case .front: "Bring All to Front"
            case .arrangeInFront: "Arrange in Front"
            case .removeWindowSet: "Remove Window from Set"
            case .welcome: String(localized: "menu.welcome", defaultValue: "Show Welcome")
            case .support: String(localized: "menu.support", defaultValue: "Room Support")
            case .privacy: String(localized: "menu.privacy", defaultValue: "Privacy")
            case .helpSearch: "Search"
            case .systemHelp: "Room Help"
            case .feedback: "Send Room Feedback to Apple"
            case .debugState: String(localized: "menu.debugState", defaultValue: "Menu bar state")
            case .debugLive: String(localized: "menu.debugLive", defaultValue: "Live")
            case .debugNormal: String(localized: "menu.debugNormal", defaultValue: "Normal")
            case .debugElevated: String(localized: "menu.debugElevated", defaultValue: "Elevated")
            case .debugCritical: String(localized: "menu.debugCritical", defaultValue: "Critical")
            case .debugBelowGoal: String(localized: "menu.debugBelowGoal", defaultValue: "Disk below goal")
            case .debugBoth: String(localized: "menu.debugBoth", defaultValue: "Both (elevated and below goal)")
            case .debugStacked: String(localized: "menu.debugStacked", defaultValue: "Both stacked (elevated and below goal)")
            case .debugIcon: String(localized: "menu.debugIcon", defaultValue: "Icon only (elevated)")
            }
        }
    }

    enum Destination: String, CaseIterable, Sendable {
        case overview, disk, clean, developer, memory, activity

        var item: ID {
            switch self {
            case .overview: .overview
            case .disk: .disk
            case .clean: .caches
            case .developer: .developer
            case .memory: .memory
            case .activity: .activity
            }
        }

        var shortcut: Shortcut? {
            switch self {
            case .overview: .init("1")
            case .disk: .init("2")
            case .clean: .init("3")
            case .developer: .init("4")
            case .memory: .init("5")
            case .activity: nil
            }
        }

        var symbol: String {
            switch self {
            case .overview: "house"
            case .disk: "square.grid.2x2"
            case .clean: "sparkles"
            case .developer: "shippingbox"
            case .memory: "memorychip"
            case .activity: "clock.arrow.circlepath"
            }
        }

        var rescan: ID? {
            switch self {
            case .overview: .refreshOverview
            case .disk: .rescanDisk
            case .clean: .rescanCaches
            case .developer: .rescanDeveloper
            case .memory: .refreshMemory
            case .activity: nil
            }
        }

        var canStop: Bool {
            switch self {
            case .disk, .clean, .developer: true
            case .overview, .memory, .activity: false
            }
        }
    }

    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let command = Self(rawValue: 1 << 0)
        static let shift = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let control = Self(rawValue: 1 << 3)
    }

    struct Shortcut: Hashable, Sendable {
        let key: Character
        let modifiers: Modifiers

        init(_ key: Character, _ modifiers: Modifiers = .command) {
            self.key = key
            self.modifiers = modifiers
        }
    }

    enum Edition: Sendable { case direct, store }
    enum Window: Sendable { case main, settings, modal, none }

    struct Input: Sendable {
        var destination: Destination? = nil
        var canRescan = false
        var isScanning = false
        var canEnclose = false
        var overviewSizesHidden = false
        var menuBarEnabled = true
        var edition: Edition = .direct
        var window: Window = .none
        var isWorking = false
        var canPin = true
        var supportAvailable = true
        var privacyAvailable = true
        var debug = false
        var sidebarIconsOnly = false
        var canGoBack = false
        var canGoForward = false
    }

    struct Item: Equatable, Sendable {
        let id: ID
        let section: Section
        let shortcut: Shortcut?
        let enabled: Bool
        let visible: Bool
        let native: Bool
        var checked: Bool? = nil
        var titleOverride: String? = nil
        var title: String { titleOverride ?? id.title }
    }

    static func make(_ input: Input) -> [Item] {
        var items: [Item] = []
        func add(_ section: Section, _ id: ID, _ shortcut: Shortcut? = nil,
                 enabled: Bool = true, visible: Bool = true, native: Bool = false,
                 checked: Bool? = nil, title: String? = nil) {
            items.append(Item(id: id, section: section, shortcut: shortcut, enabled: enabled,
                              visible: visible, native: native, checked: checked, titleOverride: title))
        }

        let modal = input.window == .modal
        let main = input.window == .main
        let hasKeyWindow = input.window != .none
        let canStart = !modal && !input.isWorking

        add(.room, .about, native: true)
        add(.room, .monitor, .init("m", [.shift, .command]), enabled: input.menuBarEnabled && !modal)
        add(.room, .settings, .init(","), native: true)
        add(.room, .services, native: true)
        add(.room, .hideApp, .init("h"), native: true)
        add(.room, .hideOthers, .init("h", [.option, .command]), native: true)
        add(.room, .showAll, native: true)
        add(.room, .quit, .init("q"), native: true)
        add(.room, .quitKeepingWindows, .init("q", [.option, .command]), native: true)

        add(.file, .pin, .init("p", [.shift, .command]), enabled: canStart && input.canPin)
        add(.file, .trash, enabled: !modal)
        add(.file, .close, .init("w"), enabled: hasKeyWindow, native: true)
        add(.file, .closeAll, .init("w", [.option, .command]), enabled: hasKeyWindow, native: true)

        add(.edit, .undo, .init("z"), native: true)
        add(.edit, .redo, .init("z", [.shift, .command]), native: true)
        add(.edit, .cut, .init("x"), native: true)
        add(.edit, .copy, .init("c"), native: true)
        add(.edit, .paste, .init("v"), native: true)
        add(.edit, .delete, native: true)
        add(.edit, .selectAll, .init("a"), native: true)
        add(.edit, .autoFill, native: true)
        add(.edit, .dictation, native: true)
        add(.edit, .emoji, native: true)

        if main, let destination = input.destination, let rescan = destination.rescan {
            add(.view, rescan, .init("r"), enabled: canStart && input.canRescan && !input.isScanning)
            if destination.canStop {
                add(.view, .stop, .init("."), enabled: input.isScanning && !input.isWorking)
            }
        }
        if main, input.destination == .overview {
            add(.view, .hideOverviewSizes, .init("h", [.command, .shift]), checked: input.overviewSizesHidden)
        }
        add(.view, .sidebarLabels, .init("s", [.control, .command]), enabled: main,
            title: input.sidebarIconsOnly ? String(localized: "menu.sidebarLabels.show", defaultValue: "Show Sidebar Labels", bundle: RoomCopy.bundle) : nil)
        add(.view, .fullScreen, .init("f", [.control, .command]), enabled: hasKeyWindow, native: true)

        add(.go, .back, .init("["), enabled: main && input.canGoBack)
        add(.go, .forward, .init("]"), enabled: main && input.canGoForward)
        for destination in Destination.allCases {
            add(.go, destination.item, destination.shortcut, enabled: !modal)
        }
        add(.go, .enclosing, .init("↑"), enabled: main && input.destination == .disk && canStart && input.canEnclose && !input.isScanning)

        add(.window, .minimize, .init("m"), enabled: hasKeyWindow, native: true)
        add(.window, .minimizeAll, .init("m", [.option, .command]), enabled: hasKeyWindow, native: true)
        add(.window, .zoom, enabled: hasKeyWindow, native: true)
        add(.window, .zoomAll, enabled: hasKeyWindow, native: true)
        add(.window, .fill, enabled: hasKeyWindow, native: true)
        add(.window, .center, enabled: hasKeyWindow, native: true)
        add(.window, .moveResize, enabled: hasKeyWindow, native: true)
        add(.window, .fullScreenTile, enabled: hasKeyWindow, native: true)
        add(.window, .front, native: true)
        add(.window, .arrangeInFront, native: true)
        add(.window, .removeWindowSet, enabled: hasKeyWindow, native: true)

        add(.help, .helpSearch, native: true)
        add(.help, .welcome, enabled: canStart)
        add(.help, .support, visible: input.supportAvailable)
        add(.help, .privacy, visible: input.privacyAvailable)
        add(.help, .systemHelp, .init("?"), native: true)
        add(.help, .feedback, native: true)

        if input.debug {
            for id in debugItems {
                add(.debug, id, enabled: input.menuBarEnabled && !modal)
            }
        }
        return items
    }

    static let debugItems: [ID] = [
        .debugState, .debugLive, .debugNormal, .debugElevated, .debugCritical,
        .debugBelowGoal, .debugBoth, .debugStacked, .debugIcon
    ]
}
