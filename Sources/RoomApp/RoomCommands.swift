import AppKit
import Observation
import SwiftUI

struct RoomScreenActions {
    let destination: RoomMenuModel.Destination
    var title: String { destination.item.title }
    var canRescan = false
    var isScanning = false
    var rescan: () -> Void = {}
    var stop: () -> Void = {}
    var canEnclose = false
    var enclose: () -> Void = {}
    var overviewSizesHidden: Bool = false
    var toggleOverviewSizes: () -> Void = {}
}

extension FocusedValues {
    @Entry var roomScreen: RoomScreenActions?
}

@Observable @MainActor
final class RoomCommandWindowContext {
    private(set) var window: RoomMenuModel.Window = .none

    func update() { window = Self.current }

    static var current: RoomMenuModel.Window {
        guard let app = NSApp else { return .none }
        if app.modalWindow != nil || app.windows.contains(where: { window in
            window.attachedSheet != nil || window.sheetParent != nil || (window is NSOpenPanel && window.isVisible)
        }) {
            return .modal
        }
        guard let key = app.keyWindow else { return .none }
        return key.identifier == RoomApplicationDelegate.primaryWindowID ? .main : .settings
    }
}

struct RoomCommands: Commands {
    @FocusedValue(\.roomScreen) private var screen
    let windowContext: RoomCommandWindowContext
    let menuBarEnabled: Bool
    let isWorking: () -> Bool
    let rooms: RoomRoomsModel
    let showMonitor: () -> Void
    let openTrash: () -> Void
    let showWelcome: () -> Void
    let navigate: (RoomDestination) -> Void

    private let links = RoomAppLinks()

    private var items: [RoomMenuModel.Item] {
        #if ROOM_APP_STORE
        let edition = RoomMenuModel.Edition.store
        #else
        let edition = RoomMenuModel.Edition.direct
        #endif
        return RoomMenuModel.make(.init(destination: screen?.destination, canRescan: screen?.canRescan ?? false,
            isScanning: screen?.isScanning ?? false, canEnclose: screen?.canEnclose ?? false,
            overviewSizesHidden: screen?.overviewSizesHidden ?? false, menuBarEnabled: menuBarEnabled, edition: edition, window: windowContext.window, isWorking: isWorking(),
            canPin: rooms.canChooseFolder, supportAvailable: links.support != nil, privacyAvailable: links.privacy != nil))
    }

    var body: some Commands {
        let presentation = items

        CommandGroup(after: .appInfo) {
            rows(.room, in: presentation)
        }

        CommandGroup(replacing: .newItem) {
            rows(.file, in: presentation)
        }

        CommandGroup(after: .toolbar) {
            rows(.view, in: presentation)
        }

        CommandGroup(replacing: .sidebar) {}

        CommandMenu(RoomMenuModel.Section.go.title) {
            rows(.go, in: presentation)
        }

        CommandGroup(before: .help) {
            rows(.help, in: presentation)
        }
    }

    private func rows(_ section: RoomMenuModel.Section, in items: [RoomMenuModel.Item]) -> some View {
        ForEach(items.filter { $0.section == section && $0.visible && !$0.native }, id: \.id) { item in
            Group {
                if let checked = item.checked {
                    Toggle(item.title, isOn: Binding(get: { checked }, set: { _ in perform(item) }))
                } else {
                    Button {
                        perform(item)
                    } label: {
                        if let destination = RoomMenuModel.Destination.allCases.first(where: { $0.item == item.id }) {
                            Label(item.title, systemImage: destination.symbol)
                        } else {
                            Text(item.title)
                        }
                    }
                }
            }
            .keyboardShortcut(item.shortcut.map { $0.keyboardShortcut })
            .disabled(!item.enabled)
        }
    }

    private func perform(_ item: RoomMenuModel.Item) {
        guard item.enabled else { return }
        let window = RoomCommandWindowContext.current
        switch item.id {
        case .support:
            if let url = links.support { NSWorkspace.shared.open(url) }
        case .privacy:
            if let url = links.privacy { NSWorkspace.shared.open(url) }
        default:
            guard window != .modal else { return }
            performRoomAction(item.id, window: window)
        }
    }

    private func performRoomAction(_ id: RoomMenuModel.ID, window: RoomMenuModel.Window) {
        if let destination = RoomMenuModel.Destination.allCases.first(where: { $0.item == id }),
           let roomDestination = RoomDestination(rawValue: destination.rawValue) {
            withoutNavigationAnimation { navigate(roomDestination) }
            return
        }
        switch id {
        case .monitor: if menuBarEnabled { showMonitor() }
        case .pin: if !isWorking() { rooms.chooseFolder() }
        case .trash: openTrash()
        case .welcome: if !isWorking() { showWelcome() }
        case .hideOverviewSizes:
            if window == .main, screen?.destination == .overview { screen?.toggleOverviewSizes() }
        case .enclosing:
            if window == .main, !isWorking(), let screen, screen.canEnclose, !screen.isScanning {
                withoutNavigationAnimation(screen.enclose)
            }
        case .stop:
            if window == .main, !isWorking(), let screen, screen.destination.canStop, screen.isScanning { screen.stop() }
        default:
            if window == .main, !isWorking(), let screen, id == screen.destination.rescan, screen.canRescan, !screen.isScanning {
                screen.rescan()
            }
        }
    }

    private func withoutNavigationAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

private extension RoomMenuModel.Shortcut {
    var keyboardShortcut: KeyboardShortcut {
        var flags: EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        return KeyboardShortcut(key == "↑" ? .upArrow : KeyEquivalent(key), modifiers: flags)
    }
}
