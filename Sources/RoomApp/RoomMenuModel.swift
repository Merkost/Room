import Foundation

/// Room's commands and the native rows they share shortcuts with.
nonisolated enum RoomMenuModel {
    enum Section: String, CaseIterable, Sendable {
        case room = "Room", file = "File", edit = "Edit", view = "View", go = "Go"
        case window = "Window", help = "Help", debug = "Debug"

        var title: String {
            switch self {
            case .go: String(localized: "menu.go", defaultValue: "Go", bundle: RoomCopy.bundle)
            case .debug: String(localized: "menu.debug", defaultValue: "Debug", bundle: RoomCopy.bundle)
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
        case customiseOverview
        case refreshOverview
        case showDiskInspector
        case compareDiskMap
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
        case showHistory
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
        #if DEBUG
        case debugSimulateTrash
        case debugResetTrash
        #endif

        var title: String {
            switch self {
            case .about: "About Room"
            case .settings: "Settings…"
            case .monitor: String(localized: "menu.monitor", defaultValue: "Show Monitor", bundle: RoomCopy.bundle)
            case .services: "Services"
            case .hideApp: "Hide Room"
            case .hideOthers: "Hide Others"
            case .showAll: "Show All"
            case .quit: "Quit Room"
            case .quitKeepingWindows: "Quit and Keep Windows"
            case .pin: String(localized: "menu.pin", defaultValue: "Pin Folder as a Room…", bundle: RoomCopy.bundle)
            case .trash: String(localized: "menu.trash", defaultValue: "Open Trash", bundle: RoomCopy.bundle)
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
            case .customiseOverview: String(localized: "menu.customiseOverview", defaultValue: "Customise Overview…", bundle: RoomCopy.bundle)
            case .refreshOverview: String(localized: "menu.refreshOverview", defaultValue: "Refresh Free Space", bundle: RoomCopy.bundle)
            case .showDiskInspector: String(localized: "menu.disk.inspector", defaultValue: "Show Inspector", bundle: RoomCopy.bundle)
            case .compareDiskMap: String(localized: "menu.disk.compare", defaultValue: "Compare", bundle: RoomCopy.bundle)
            case .hideOverviewSizes: String(localized: "menu.hide", defaultValue: "Hide Sizes and Names", bundle: RoomCopy.bundle)
            case .rescanDisk: String(localized: "menu.rescanDisk", defaultValue: "Rescan Disk Map", bundle: RoomCopy.bundle)
            case .rescanCaches: String(localized: "menu.rescanCaches", defaultValue: "Check Caches Again", bundle: RoomCopy.bundle)
            case .rescanDeveloper: String(localized: "menu.rescanDeveloper", defaultValue: "Rescan Developer", bundle: RoomCopy.bundle)
            case .refreshMemory: String(localized: "menu.refreshMemory", defaultValue: "Refresh Memory", bundle: RoomCopy.bundle)
            case .stop: String(localized: "menu.stop", defaultValue: "Stop Scan", bundle: RoomCopy.bundle)
            case .fullScreen: "Enter Full Screen"
            case .sidebarLabels: String(localized: "menu.sidebarLabels.hide", defaultValue: "Hide Sidebar Labels", bundle: RoomCopy.bundle)
            case .back: String(localized: "menu.back", defaultValue: "Back", bundle: RoomCopy.bundle)
            case .forward: String(localized: "menu.forward", defaultValue: "Forward", bundle: RoomCopy.bundle)
            case .overview: String(localized: "menu.overview", defaultValue: "Overview", bundle: RoomCopy.bundle)
            case .disk: String(localized: "menu.disk", defaultValue: "Disk Map", bundle: RoomCopy.bundle)
            case .caches: String(localized: "menu.caches", defaultValue: "Caches", bundle: RoomCopy.bundle)
            case .developer: String(localized: "menu.developer", defaultValue: "Developer", bundle: RoomCopy.bundle)
            case .memory: String(localized: "menu.memory", defaultValue: "Memory", bundle: RoomCopy.bundle)
            case .showHistory: String(localized: "menu.showHistory", defaultValue: "Show History", bundle: RoomCopy.bundle)
            case .enclosing: String(localized: "menu.enclosing", defaultValue: "Enclosing Folder", bundle: RoomCopy.bundle)
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
            case .welcome: String(localized: "menu.welcome", defaultValue: "Show Welcome", bundle: RoomCopy.bundle)
            case .support: String(localized: "menu.support", defaultValue: "Room Support", bundle: RoomCopy.bundle)
            case .privacy: String(localized: "menu.privacy", defaultValue: "Privacy", bundle: RoomCopy.bundle)
            case .helpSearch: "Search"
            case .systemHelp: "Room Help"
            case .feedback: "Send Room Feedback to Apple"
            case .debugState: String(localized: "menu.debugState", defaultValue: "Menu bar state", bundle: RoomCopy.bundle)
            case .debugLive: String(localized: "menu.debugLive", defaultValue: "Live", bundle: RoomCopy.bundle)
            case .debugNormal: String(localized: "menu.debugNormal", defaultValue: "Normal", bundle: RoomCopy.bundle)
            case .debugElevated: String(localized: "menu.debugElevated", defaultValue: "Elevated", bundle: RoomCopy.bundle)
            case .debugCritical: String(localized: "menu.debugCritical", defaultValue: "Critical", bundle: RoomCopy.bundle)
            case .debugBelowGoal: String(localized: "menu.debugBelowGoal", defaultValue: "Disk below goal", bundle: RoomCopy.bundle)
            case .debugBoth: String(localized: "menu.debugBoth", defaultValue: "Both (elevated and below goal)", bundle: RoomCopy.bundle)
            case .debugStacked: String(localized: "menu.debugStacked", defaultValue: "Both stacked (elevated and below goal)", bundle: RoomCopy.bundle)
            case .debugIcon: String(localized: "menu.debugIcon", defaultValue: "Icon only (elevated)", bundle: RoomCopy.bundle)
            #if DEBUG
            case .debugSimulateTrash: String(localized: "debug.simulateTrash", defaultValue: "Simulate Trash Emptied", bundle: RoomCopy.bundle)
            case .debugResetTrash: String(localized: "debug.resetTrash", defaultValue: "Reset Simulated Trash", bundle: RoomCopy.bundle)
            #endif
            }
        }
    }

    enum Destination: String, CaseIterable, Sendable {
        case overview, disk, clean, developer, memory

        var item: ID {
            switch self {
            case .overview: .overview
            case .disk: .disk
            case .clean: .caches
            case .developer: .developer
            case .memory: .memory
            }
        }

        var shortcut: Shortcut? {
            switch self {
            case .overview: .init("1")
            case .disk: .init("2")
            case .clean: .init("3")
            case .developer: .init("4")
            case .memory: .init("5")
            }
        }

        var symbol: String {
            switch self {
            case .overview: "house"
            case .disk: "square.grid.2x2"
            case .clean: "sparkles"
            case .developer: "shippingbox"
            case .memory: "memorychip"
            }
        }

        var rescan: ID? {
            switch self {
            case .overview: .refreshOverview
            case .disk: .rescanDisk
            case .clean: .rescanCaches
            case .developer: .rescanDeveloper
            case .memory: .refreshMemory
            }
        }

        var canStop: Bool {
            switch self {
            case .disk, .clean, .developer: true
            case .overview, .memory: false
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
        var canInspectDisk = false
        var comparisonTitle: String?
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
        if main {
            add(.view, .hideOverviewSizes, .init("h", [.command, .shift]), checked: input.overviewSizesHidden)
            if input.destination == .disk, input.canInspectDisk {
                add(.view, .showDiskInspector, .init("i", [.option, .command]), enabled: canStart)
                if let title = input.comparisonTitle {
                    add(.view, .compareDiskMap, enabled: canStart, title: title)
                }
            }
        }
        add(.view, .sidebarLabels, .init("s", [.control, .command]), enabled: main,
            title: input.sidebarIconsOnly ? String(localized: "menu.sidebarLabels.show", defaultValue: "Show Sidebar Labels", bundle: RoomCopy.bundle) : nil)
        if main && input.destination == .overview {
            add(.view, .customiseOverview, .init("c", [.option, .command]))
        }
        add(.view, .fullScreen, .init("f", [.control, .command]), enabled: hasKeyWindow, native: true)

        add(.go, .back, .init("["), enabled: main && input.canGoBack)
        add(.go, .forward, .init("]"), enabled: main && input.canGoForward)
        for destination in Destination.allCases {
            add(.go, destination.item, destination.shortcut, enabled: !modal)
        }
        add(.go, .showHistory, .init("y"), enabled: main)
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
            #if DEBUG
            add(.debug, .debugSimulateTrash, enabled: main && !input.isWorking)
            add(.debug, .debugResetTrash, enabled: main && !input.isWorking)
            #endif
        }
        return items
    }

    static let debugItems: [ID] = [
        .debugState, .debugLive, .debugNormal, .debugElevated, .debugCritical,
        .debugBelowGoal, .debugBoth, .debugStacked, .debugIcon
    ]
}
