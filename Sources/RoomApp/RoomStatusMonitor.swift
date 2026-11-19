import AppKit
import Observation
import SwiftUI

/// Owns the actual menu bar button and its anchored native popover. Both mouse
/// clicks and the Show Monitor command take this same presentation path.
@MainActor
final class RoomStatusMonitor: NSObject, NSPopoverDelegate {
    private let insights: RoomInsightsModel
    private let cacheModel: RoomViewModel
    private let rooms: RoomRoomsModel
    private var openRoom: () -> Void
    private var openSettings: () -> Void
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
    private var displayedTint: RoomMenuBarTint = .none
    private var pocketImageCache: [String: NSImage] = [:]

    /// One image per (fill, tint), built on first use. The tint is baked into the image because macOS ignores
    /// `contentTintColor` on a status item's template image; an untinted image stays a template.
    private func pocketImage(fill: Double, tint: RoomMenuBarTint) -> NSImage {
        let key = "\(fill)/\(tint)"
        if let cached = pocketImageCache[key] { return cached }
        let image = RoomPocketMark.image(fill: fill, pointSize: 16, tint: tintColor(tint))
        pocketImageCache[key] = image
        return image
    }
    private var preferencesObserver: NSObjectProtocol?

#if DEBUG
    let debugMenuBarState = RoomDebugMenuBarState.shared

    func setDebugMenuBarScenario(_ scenario: RoomDebugMenuBarScenario) {
        debugMenuBarState.scenario = scenario
        updateButton()
    }

    /// Debug builds only: open `popover` or `settings[:menubar|:folders|:about]` shortly after launch.
    private func applyDebugLaunchRequest() {
        guard let request = ProcessInfo.processInfo.environment["ROOM_DEBUG_OPEN"] else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            switch request {
            case "popover": self?.showMonitor()
            case "settings", "settings:menubar", "settings:folders", "settings:about":
                let rawTab = request.split(separator: ":").dropFirst().first.map(String.init) ?? "general"
                guard let tab = RoomSettingsTab(rawValue: rawTab), let self else { return }
                self.insights.requestedSettingsTab = tab
                self.insights.requestedSettings = true
            default: break
            }
        }
    }
#endif

    init(insights: RoomInsightsModel, cacheModel: RoomViewModel,
         rooms: RoomRoomsModel, openRoom: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.insights = insights
        self.cacheModel = cacheModel
        self.rooms = rooms
        self.openRoom = openRoom
        self.openSettings = openSettings
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView:
            RoomMenuBarView(insights: insights, cacheModel: cacheModel, rooms: rooms, openRoom: { [weak self] in
                self?.openMainWindow()
            }, showSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
                NSApp.activate()
            })
            .modifier(RoomMotionRoot())
            .modifier(RoomAccentRoot())
            .modifier(RoomHideRoot())
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        #if DEBUG
        applyDebugLaunchRequest()
        #endif
    }

    func updateOpenRoom(_ action: @escaping () -> Void) { openRoom = action }
    func updateOpenSettings(_ action: @escaping () -> Void) { openSettings = action }

    func setEnabled(_ enabled: Bool) {
        if !enabled { rooms.setPopoverActive(false) }
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        observationGeneration = UUID()
        if enabled {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "RoomMemoryMonitor"
            item.isVisible = true
            statusItem = item
            if let button = item.button {
                button.image = pocketImage(fill: 0, tint: .none)
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
        insights.scanMemory()
        insights.refreshDiskCapacity()
        rooms.setPopoverActive(true)
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

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        rooms.setPopoverActive(false)
    }

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
        let format = RoomMenuBarFormat.live
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

        if output.stackedLines != nil {
            // The shared image owns both figures. Two lines swap at once rather than ticking.
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            updateTitle(output.title, mode: input.value, previousMode: previousMode,
                        button: button, animated: motionAllowed)
            button.imagePosition = output.icon == .none ? .noImage : output.title.isEmpty ? .imageOnly : .imageLeading
        }
        if motionAllowed, previousOutput?.icon == .mark, output.icon == .mark,
           displayedPocketFill != output.pocketFill {
            if output.stackedLines != nil {
                // Show the new figures before the first fill frame, keeping the old tint until the end.
                button.contentTintColor = nil
                button.image = stackedImage(output, fill: displayedPocketFill, tint: displayedTint)
            } else if previousOutput?.stackedLines != nil {
                // Remove the composite as soon as the inline title returns.
                button.image = pocketImage(fill: displayedPocketFill, tint: displayedTint)
            }
            animatePocket(to: output, button: button)
        } else {
            applyImage(output, button: button)
        }
        button.toolTip = output.toolTip
        button.setAccessibilityLabel("Room")
        button.setAccessibilityValue(output.accessibilityValue)
        // Until a first measurement arrives the key is the "unavailable" placeholder; letting it use up the
        // first-value exemption would announce a pressure that was already there at launch (D-MB-8).
        let hasMeasurement = input.memoryUsedBytes != nil || input.diskFreeBytes != nil
        if hasMeasurement, announcer.shouldAnnounce(output.announcementKey) {
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
        button.contentTintColor = nil   // ignored on template images by macOS; colour lives in the image instead
        displayedTint = output.tint
        if output.stackedLines != nil {
            button.image = RoomMenuBarStackedItem.image(for: output)
            displayedPocketFill = output.pocketFill
            return
        }
        switch output.icon {
        case .mark:
            button.image = pocketImage(fill: output.pocketFill, tint: output.tint)
            displayedPocketFill = output.pocketFill
        case .symbol:
            var image = NSImage(systemSymbolName: output.symbolName, accessibilityDescription: "Room")
            if let color = tintColor(output.tint) {
                var resolved = color
                button.effectiveAppearance.performAsCurrentDrawingAppearance {
                    resolved = color.usingColorSpace(.sRGB) ?? color
                }
                image = image?.withSymbolConfiguration(.init(paletteColors: [resolved]))
            } else {
                image?.isTemplate = true
            }
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
        case .none:
            button.image = nil
        }
    }

    private func stackedImage(_ output: RoomMenuBarOutput, fill: Double, tint: RoomMenuBarTint) -> NSImage {
        var frame = output
        frame.tint = tint
        return RoomMenuBarStackedItem.image(for: frame, pocketFill: fill)
    }

    private func animatePocket(to output: RoomMenuBarOutput, button: NSStatusBarButton) {
        let frames = RoomMenuBarMotion.fillFrames(from: displayedPocketFill, to: output.pocketFill)
        fillTask = Task { @MainActor [weak self, weak button] in
            for fill in frames {
                do { try await Task.sleep(for: .seconds(RoomMenuBarMotion.fillDuration / Double(RoomMenuBarMotion.fillFrameCount))) }
                catch { return }
                guard !Task.isCancelled, let self, let button else { return }
                if fill != self.displayedPocketFill {
                    if output.stackedLines != nil {
                        button.image = self.stackedImage(output, fill: fill, tint: self.displayedTint)
                    } else {
                        button.image = self.pocketImage(fill: fill, tint: self.displayedTint)
                    }
                    self.displayedPocketFill = fill
                }
            }
            guard !Task.isCancelled, let self, let button else { return }
            self.applyImage(output, button: button)
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
