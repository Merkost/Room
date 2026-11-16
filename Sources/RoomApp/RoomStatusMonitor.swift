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
    private var announcer = RoomMenuBarAnnouncer()
    private var lastOutput: RoomMenuBarOutput?
    private var lastValueMode: RoomMenuBarValueMode?
    private var lastMotionAllowed: Bool?
    private var titleTask: Task<Void, Never>?
    private var fillTask: Task<Void, Never>?
    private var displayedPocketFill: Double = 0
    private lazy var pocketImages = Dictionary(uniqueKeysWithValues:
        RoomMenuBarMotion.cachedFills.map { ($0, RoomPocketMark.image(fill: $0, pointSize: 16)) })
    private var preferencesObserver: NSObjectProtocol?

#if DEBUG
    let debugMenuBarState = RoomDebugMenuBarState()

    func setDebugMenuBarScenario(_ scenario: RoomDebugMenuBarScenario) {
        debugMenuBarState.scenario = scenario
        updateButton()
    }
#endif

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
                button.image = pocketImages[0]
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true
                button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
                button.target = self
                button.action = #selector(toggleMonitor(_:))
                button.identifier = NSUserInterfaceItemIdentifier("RoomMemoryMonitorStatusButton")
                button.setAccessibilityIdentifier("RoomMemoryMonitorStatusButton")
                button.setAccessibilityLabel("Room")
            }
            preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateButton() }
            }
            insights.beginMonitoring()
            observeMemory(generation: observationGeneration)
        } else {
            titleTask?.cancel()
            titleTask = nil
            fillTask?.cancel()
            fillTask = nil
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
            announcer = RoomMenuBarAnnouncer()
            lastOutput = nil
            lastValueMode = nil
            lastMotionAllowed = nil
            displayedPocketFill = 0
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
        popover.animates = allowsMotion
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
        let liveInput = RoomMenuBarSettings.makeInput(defaults: .standard, memoryReport: insights.memoryReport,
            diskCapacityBytes: insights.diskCapacityBytes, diskAvailableBytes: insights.diskAvailableBytes)
#if DEBUG
        let input = debugMenuBarState.scenario.apply(to: liveInput)
#else
        let input = liveInput
#endif
        // The pure presentation invokes these formatters synchronously here on MainActor.
        let format = RoomMenuBarFormat(
            memory: { bytes in MainActor.assumeIsolated { RoomFormat.memoryBytes(bytes) } },
            disk: { bytes in MainActor.assumeIsolated { RoomFormat.bytes(bytes) } })
        let output = RoomMenuBarPresentation.make(input, format: format)
        let motionAllowed = allowsMotion
        guard output != lastOutput || input.value != lastValueMode || motionAllowed != lastMotionAllowed else { return }

        titleTask?.cancel()
        titleTask = nil
        fillTask?.cancel()
        fillTask = nil
        let previousOutput = lastOutput
        let previousMode = lastValueMode
        lastOutput = output
        lastValueMode = input.value
        lastMotionAllowed = motionAllowed

        updateTitle(output.title, mode: input.value, previousMode: previousMode,
                    button: button, animated: motionAllowed)
        button.imagePosition = output.icon == .none ? .noImage : output.title.isEmpty ? .imageOnly : .imageLeading
        if motionAllowed, previousOutput?.icon == .mark, output.icon == .mark,
           displayedPocketFill != output.pocketFill {
            animatePocket(to: output, button: button)
        } else {
            applyImage(output, button: button)
            button.contentTintColor = tintColor(output.tint)
        }
        button.toolTip = output.toolTip
        button.setAccessibilityLabel("Room")
        button.setAccessibilityValue(output.accessibilityValue)
        if announcer.shouldAnnounce(output.announcementKey) {
            NSAccessibility.post(element: button, notification: .valueChanged)
        }
    }

    private var allowsMotion: Bool {
        let enabled = UserDefaults.standard.object(forKey: "RoomMotionEnabled") as? Bool ?? true
        return enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateTitle(_ title: String, mode: RoomMenuBarValueMode,
                             previousMode: RoomMenuBarValueMode?, button: NSStatusBarButton, animated: Bool) {
        let titles = animated ? RoomMenuBarTitleTick.titles(from: button.title, to: title,
            previousMode: previousMode, mode: mode) : []
        guard !titles.isEmpty else { button.title = title; return }
        titleTask = Task { @MainActor [weak button] in
            for title in titles {
                do { try await Task.sleep(for: .seconds(RoomMenuBarMotion.tickDuration / Double(RoomMenuBarMotion.tickSteps))) }
                catch { return }
                guard !Task.isCancelled, let button else { return }
                button.title = title
            }
        }
    }

    private func applyImage(_ output: RoomMenuBarOutput, button: NSStatusBarButton) {
        switch output.icon {
        case .mark:
            button.image = pocketImages[output.pocketFill]
            displayedPocketFill = output.pocketFill
        case .symbol:
            let image = NSImage(systemSymbolName: output.symbolName, accessibilityDescription: "Room")
            image?.isTemplate = true
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
        case .none:
            button.image = nil
        }
    }

    private func animatePocket(to output: RoomMenuBarOutput, button: NSStatusBarButton) {
        let frames = RoomMenuBarMotion.fillFrames(from: displayedPocketFill, to: output.pocketFill)
        fillTask = Task { @MainActor [weak self, weak button] in
            for fill in frames {
                do { try await Task.sleep(for: .seconds(RoomMenuBarMotion.fillDuration / Double(RoomMenuBarMotion.fillFrameCount))) }
                catch { return }
                guard !Task.isCancelled, let self, let button else { return }
                if fill != self.displayedPocketFill {
                    button.image = self.pocketImages[fill]
                    self.displayedPocketFill = fill
                }
            }
            guard !Task.isCancelled, let self, let button else { return }
            self.applyImage(output, button: button)
            button.contentTintColor = self.tintColor(output.tint)
        }
    }

    private func tintColor(_ tint: RoomMenuBarTint) -> NSColor? {
        switch tint {
        case .none: nil
        case .normal: RoomTokens.Status.normalAppKit
        case .elevated: RoomTokens.Status.elevatedAppKit
        case .critical: RoomTokens.Status.criticalAppKit
        }
    }
}
