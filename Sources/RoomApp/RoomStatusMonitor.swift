import AppKit
import Observation
import SwiftUI

/// Owns the actual menu bar button and its anchored native popover. Both mouse
/// clicks and the Show Monitor command take this same presentation path.
@MainActor
final class RoomStatusMonitor: NSObject, NSPopoverDelegate {
    private let insights: RoomInsightsModel
    private let memoryActions: MemoryActionsModel
    private let cacheModel: RoomViewModel
    private var openRoom: () -> Void
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var observationGeneration = UUID()
    private var isEnabled = false
    private var lastAccessibilityValue: String?
    private var preferencesObserver: NSObjectProtocol?

    init(insights: RoomInsightsModel, memoryActions: MemoryActionsModel,
         cacheModel: RoomViewModel, openRoom: @escaping () -> Void) {
        self.insights = insights
        self.memoryActions = memoryActions
        self.cacheModel = cacheModel
        self.openRoom = openRoom
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView:
            RoomMenuBarView(insights: insights, memoryActions: memoryActions, cacheModel: cacheModel) { [weak self] in
                self?.openMainWindow()
            }
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    func updateOpenRoom(_ action: @escaping () -> Void) { openRoom = action }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        observationGeneration = UUID()
        if enabled {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "RoomMemoryMonitor"
            item.isVisible = true
            statusItem = item
            if let button = item.button {
                let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Room")
                image?.isTemplate = true
                image?.size = NSSize(width: 16, height: 16)
                button.image = image
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true
                button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                button.target = self
                button.action = #selector(toggleMonitor(_:))
                button.identifier = NSUserInterfaceItemIdentifier("RoomMemoryMonitorStatusButton")
                button.setAccessibilityIdentifier("RoomMemoryMonitorStatusButton")
                button.setAccessibilityLabel("Room memory monitor")
            }
            preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateButton() }
            }
            insights.beginMonitoring()
            observeMemory(generation: observationGeneration)
        } else {
            if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
            preferencesObserver = nil
            popover.performClose(nil)
            insights.stopMonitoring()
            if let item = statusItem {
                item.button?.target = nil
                item.button?.action = nil
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            lastAccessibilityValue = nil
        }
    }

    /// An accessible menu command invokes the owned status button, rather than
    /// presenting a second window that merely resembles the monitor.
    func showMonitor() {
        guard isEnabled, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
        } else {
            button.performClick(nil)
        }
    }

    @objc private func toggleMonitor(_ sender: Any?) {
        guard isEnabled, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        let motionEnabled = UserDefaults.standard.object(forKey: "RoomMotionEnabled") as? Bool ?? true
        popover.animates = motionEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch UserDefaults.standard.string(forKey: "RoomAppearance") {
        case "dark": popover.appearance = NSAppearance(named: .darkAqua)
        case "light": popover.appearance = NSAppearance(named: .aqua)
        default: popover.appearance = nil
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.title = "Room Monitor"
            window.identifier = NSUserInterfaceItemIdentifier("RoomMemoryMonitorPopover")
            window.makeKey()
        }
        button.highlight(true)
    }

    private func openMainWindow() {
        popover.performClose(nil)
        openRoom()
    }

    func popoverDidClose(_ notification: Notification) { statusItem?.button?.highlight(false) }

    private func observeMemory(generation: UUID) {
        guard isEnabled, generation == observationGeneration else { return }
        withObservationTracking {
            _ = insights.memoryReport?.id
            _ = insights.diskCapacityBytes
            _ = insights.diskAvailableBytes
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeMemory(generation: generation)
            }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let metric = RoomMonitorMetric(rawValue: defaults.string(forKey: "RoomMenuBarMetric") ?? "memory") ?? .memory
        let showPressure = defaults.object(forKey: "RoomMonitorShowPressure") as? Bool ?? true
        let showSwap = defaults.object(forKey: "RoomMonitorShowSwap") as? Bool ?? true
        let presentation: RoomMonitorPresentation
        if metric == .storage {
            presentation = .storage(total: insights.diskCapacityBytes, available: insights.diskAvailableBytes)
        } else {
            let report = insights.memoryReport
            presentation = .memory(total: report?.totalBytes ?? 0, used: report?.usedBytes ?? 0,
                available: report?.availableBytes ?? 0, pressure: report?.pressure ?? .unknown,
                swap: report.flatMap(RoomMonitorPresentation.measuredSwap), showPressure: showPressure, showSwap: showSwap)
        }
        let image = NSImage(systemSymbolName: metric.symbol, accessibilityDescription: metric.title)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        button.image = image
        button.title = presentation.value
        switch presentation.tone {
        case .neutral: button.contentTintColor = nil
        case .normal: button.contentTintColor = .systemGreen
        case .elevated: button.contentTintColor = .systemOrange
        case .critical: button.contentTintColor = .systemRed
        }
        let value = presentation.detail
        button.toolTip = "Room · \(value)"
        button.setAccessibilityLabel("Room \(metric.title) monitor")
        button.setAccessibilityValue(value)
        if lastAccessibilityValue != value {
            lastAccessibilityValue = value
            NSAccessibility.post(element: button, notification: .valueChanged)
        }
    }
}
