import AppKit
import RoomCore
import SwiftUI

@main
struct RoomApp: App {
    @NSApplicationDelegateAdaptor(RoomApplicationDelegate.self) private var delegate
    @State private var model: RoomViewModel
    @State private var insights = RoomInsightsModel(volumeHistory: .shared, pressureWriter: .shared)
    @State private var navigation = RoomWindowNavigation()
    @State private var memoryActions = MemoryActionsModel()
    @State private var rooms: RoomRoomsModel
    #if !ROOM_APP_STORE
    @State private var agentWork: AgentWorkModel
    #endif
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init() {
        let cacheModel = RoomViewModel(cachesCheckStore: RoomCachesCheckStore(writer: .shared))
        _model = State(initialValue: cacheModel)
        #if ROOM_APP_STORE
        _rooms = State(initialValue: RoomRoomsModel(isWorking: { cacheModel.isWorking }))
        #else
        let agentModel = AgentWorkModel()
        _agentWork = State(initialValue: agentModel)
        _rooms = State(initialValue: RoomRoomsModel(isWorking: { cacheModel.isWorking || agentModel.isWorking }))
        #endif
    }

    private var isWorking: Bool {
        #if ROOM_APP_STORE
        model.isWorking
        #else
        model.isWorking || agentWork.isWorking
        #endif
    }

    private func openMainWindow() {
        openWindow(id: "room")
        NSApp.activate()
    }

    @ViewBuilder private var rootView: some View {
        #if ROOM_APP_STORE
        RoomRootView(model: model, insights: insights, memoryActions: memoryActions, rooms: rooms, navigation: navigation)
        #else
        RoomRootView(model: model, insights: insights, memoryActions: memoryActions, rooms: rooms,
                     navigation: navigation, agentWork: agentWork)
        #endif
    }

    var body: some Scene {
        Window("Room", id: "room") {
            rootView
                .modifier(RoomMotionRoot())
                .modifier(RoomAccentRoot())
                .background(RoomWindowConfigurator())
                .onAppear {
                    delegate.model = model
                    delegate.insights = insights
                    insights.recordCapacityOnLaunch()
                    #if !ROOM_APP_STORE
                    delegate.agentWork = agentWork
                    #endif
                    delegate.configureMonitor(insights: insights, cacheModel: model, rooms: rooms, enabled: menuBarEnabled, openRoom: {
                        openWindow(id: "room")
                        NSApp.activate()
                    }, openSettings: { openSettings() })
                }
                .onChange(of: model.lastScanned) { _, date in
                    if date != nil { insights.recordCapacityAfterScan() }
                }
                .onChange(of: menuBarEnabled, initial: true) { _, enabled in
                    delegate.statusMonitor?.setEnabled(enabled)
                }
        }
        .defaultSize(width: 1000, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            RoomCommands(windowContext: delegate.commandWindow, menuBarEnabled: menuBarEnabled, isWorking: { isWorking },
                         rooms: rooms, navigation: navigation, showMonitor: { delegate.statusMonitor?.showMonitor() },
                         openTrash: model.openTrash, showWelcome: {
                insights.requestedWelcome = true
                openMainWindow()
            }, navigate: { destination in
                navigation.select(.screen(destination), origin: .keyboard)
                openMainWindow()
            })
            #if DEBUG
            RoomDebugMenuCommands(windowContext: delegate.commandWindow, enabled: menuBarEnabled,
                                  monitor: { delegate.statusMonitor })
            #endif
        }
        Settings {
            RoomSettingsView(model: model, insights: insights, rooms: rooms, isWorking: { isWorking })
                .modifier(RoomMotionRoot())
                .modifier(RoomAccentRoot())
        }
        .windowResizability(.contentSize)

    }
}

final class RoomApplicationDelegate: NSObject, NSApplicationDelegate {
    static let primaryWindowID = NSUserInterfaceItemIdentifier("RoomPrimaryWindow")

    weak var model: RoomViewModel?
    weak var insights: RoomInsightsModel?
    private var waitingForStateWrites = false
    #if !ROOM_APP_STORE
    weak var agentWork: AgentWorkModel?
    #endif
    private var isAgentOperationWorking: Bool {
        #if ROOM_APP_STORE
        false
        #else
        agentWork?.isWorking == true
        #endif
    }
    private(set) var statusMonitor: RoomStatusMonitor?
    let commandWindow = RoomCommandWindowContext()

    func configureMonitor(insights: RoomInsightsModel, cacheModel: RoomViewModel,
                          rooms: RoomRoomsModel, enabled: Bool, openRoom: @escaping () -> Void,
                          openSettings: @escaping () -> Void) {
        self.insights = insights
        if let statusMonitor {
            statusMonitor.updateOpenRoom(openRoom)
            statusMonitor.updateOpenSettings(openSettings)
            statusMonitor.setEnabled(enabled)
        } else {
            let monitor = RoomStatusMonitor(insights: insights, cacheModel: cacheModel, rooms: rooms,
                openRoom: openRoom, openSettings: openSettings)
            statusMonitor = monitor
            monitor.setEnabled(enabled)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "Room", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                     NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(commandWindowChanged), name: name, object: nil)
        }
        commandWindow.update()
        #if DEBUG
        RoomDebugMainMenuProbe.start()
        #endif
    }

    @objc private func commandWindowChanged() {
        Task { @MainActor in commandWindow.update() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing a window must not interrupt a move or its recovery receipt.
        let monitorEnabled = UserDefaults.standard.object(forKey: "RoomMenuBarEnabled") as? Bool ?? true
        return !monitorEnabled && model?.isWorking != true && !isAgentOperationWorking
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if !ROOM_APP_STORE
        agentWork?.shutdown()
        #endif
        StorageAIEngine.shutdownOwnedWorkers()
        statusMonitor?.setEnabled(false)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        insights?.recordCapacityOnActivation()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.isWorking == true || isAgentOperationWorking {
            let alert = NSAlert()
            alert.messageText = "Room is finishing a file operation."
            alert.informativeText = "Keep Room open while its recovery record is saved. Files already moved remain in Trash."
            alert.addButton(withTitle: "Keep Room Open")
            alert.runModal()
            return .terminateCancel
        }
        if waitingForStateWrites { return .terminateLater }
        RoomInlineConfirmCenter.shared.finishAll()
        insights?.volumeHistory.prepareForTermination()
        insights?.savePressureHistory()
        let writer = RoomStateWriter.shared
        guard writer.hasPendingWrites else { return .terminateNow }
        waitingForStateWrites = true
        Task { @MainActor in
            await writer.flush(deadline: .milliseconds(500))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.identifier == Self.primaryWindowID }?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

private struct RoomWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> RoomWindowBridge { RoomWindowBridge() }
    func updateNSView(_ nsView: RoomWindowBridge, context: Context) { }
}

private final class RoomWindowBridge: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.identifier = RoomApplicationDelegate.primaryWindowID
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RoomPrimaryWindow")
    }
}
