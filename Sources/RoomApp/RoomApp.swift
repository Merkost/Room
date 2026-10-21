import AppKit
import RoomCore
import SwiftUI

@main
struct RoomApp: App {
    @NSApplicationDelegateAdaptor(RoomApplicationDelegate.self) private var delegate
    @State private var model = RoomViewModel()
    @State private var insights = RoomInsightsModel()
    @State private var memoryActions = MemoryActionsModel()
    #if !ROOM_APP_STORE
    @State private var agentWork = AgentWorkModel()
    #endif
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @Environment(\.openWindow) private var openWindow

    @ViewBuilder private var rootView: some View {
        #if ROOM_APP_STORE
        RoomRootView(model: model, insights: insights, memoryActions: memoryActions)
        #else
        RoomRootView(model: model, insights: insights, memoryActions: memoryActions, agentWork: agentWork)
        #endif
    }

    var body: some Scene {
        Window("Room", id: "room") {
            rootView
                .background(RoomWindowConfigurator())
                .onAppear {
                    delegate.model = model
                    #if !ROOM_APP_STORE
                    delegate.agentWork = agentWork
                    #endif
                    delegate.configureMonitor(insights: insights, memoryActions: memoryActions,
                                              cacheModel: model, enabled: menuBarEnabled) {
                        openWindow(id: "room")
                        NSApp.activate()
                    }
                }
                .onChange(of: menuBarEnabled, initial: true) { _, enabled in
                    delegate.statusMonitor?.setEnabled(enabled)
                }
        }
        .defaultSize(width: 1000, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Show Monitor") { delegate.statusMonitor?.showMonitor() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(!menuBarEnabled)
                Button(model.isScanning ? "Stop Cache Scan" : "Scan Caches") {
                    insights.requestedDestination = .clean
                    if model.isScanning { model.cancelScan() } else { model.scan() }
                }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isWorking)
                Button("Open Trash") { model.openTrash() }
            }
        }

    }
}

final class RoomApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: RoomViewModel?
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

    func configureMonitor(insights: RoomInsightsModel, memoryActions: MemoryActionsModel,
                          cacheModel: RoomViewModel, enabled: Bool, openRoom: @escaping () -> Void) {
        if let statusMonitor {
            statusMonitor.updateOpenRoom(openRoom)
            statusMonitor.setEnabled(enabled)
        } else {
            let monitor = RoomStatusMonitor(insights: insights, memoryActions: memoryActions,
                                            cacheModel: cacheModel, openRoom: openRoom)
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.isWorking == true || isAgentOperationWorking else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Room is finishing a file operation."
        alert.informativeText = "Keep Room open while its recovery record is saved. Files already moved remain in Trash."
        alert.addButton(withTitle: "Keep Room Open")
        alert.runModal()
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.identifier?.rawValue == "RoomPrimaryWindow" }?.makeKeyAndOrderFront(nil)
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
        window.identifier = NSUserInterfaceItemIdentifier("RoomPrimaryWindow")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RoomPrimaryWindow")
    }
}
