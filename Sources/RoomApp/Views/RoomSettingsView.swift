import AppKit
import SwiftUI

nonisolated enum RoomSettingsTab: String, CaseIterable, Sendable {
    case general, menubar, folders, about
}

@MainActor
struct RoomSettingsView: View {
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    @Bindable var rooms: RoomRoomsModel
    var isWorking: () -> Bool
    @SceneStorage("RoomSettingsTab") private var selectedTab = RoomSettingsTab.general.rawValue
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @Environment(\.roomMotion) private var motion

    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            VStack {
                if selectedTab == RoomSettingsTab.general.rawValue { RoomGeneralSettingsView(model: model, insights: insights, rooms: rooms, isWorking: isWorking).transition(.opacity) }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(RoomSettingsTab.general.rawValue)

            VStack {
                if selectedTab == RoomSettingsTab.menubar.rawValue {
                    RoomMenuBarSettingsControls(insights: insights, rooms: rooms, enabled: $menuBarEnabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                }
            }
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            .tag(RoomSettingsTab.menubar.rawValue)

            VStack {
                if selectedTab == RoomSettingsTab.folders.rawValue {
                    RoomFolderAccessSettingsView(insights: insights, rooms: rooms, isWorking: isWorking).transition(.opacity)
                }
            }
            .tabItem { Label("Folder Access", systemImage: "folder.badge.gearshape") }
            .tag(RoomSettingsTab.folders.rawValue)

            VStack {
                if selectedTab == RoomSettingsTab.about.rawValue {
                    RoomAboutSettingsView(model: model, insights: insights).transition(.opacity)
                }
            }
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(RoomSettingsTab.about.rawValue)
        }
        .frame(width: RoomTokens.Settings.width)
        .fixedSize(horizontal: false, vertical: true)
        // A tab's content fades in as the window settles to its height (240 ms, no travel); Reduce Motion: 150 ms fade.
        .animation(motion.animation(RoomTokens.Motion.settle), value: selectedTab)
        .preferredColorScheme(colorScheme)
        .onAppear {
            if RoomSettingsTab(rawValue: selectedTab) == nil { selectedTab = RoomSettingsTab.general.rawValue }
        }
        .onChange(of: insights.requestedSettingsTab, initial: true) { _, requested in
            guard let requested else { return }
            selectedTab = requested.rawValue
            insights.requestedSettingsTab = nil
        }
    }
}

@MainActor
private struct RoomGeneralSettingsView: View {
    @AppStorage(RoomOverviewPreferences.greetingKey) private var greetByName = true
    @AppStorage(RoomDevUnreferenced.preferenceKey) private var unpinnedFlagDays = RoomDevUnreferenced.defaultThreshold
    let model: RoomViewModel
    let insights: RoomInsightsModel
    let rooms: RoomRoomsModel
    let isWorking: () -> Bool
    #if !ROOM_APP_STORE
    private let weeklyCheck = RoomWeeklyCheckScheduler.shared
    #endif
    @State private var isForgettingHistory = false
    @State private var hasDamagedHistory = false
    private let confirmation = RoomInlineConfirmCenter.shared
    private let forgetID = "settings:forget-history"
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @AppStorage("RoomOpenOn") private var openOn = RoomOpenOn.last.rawValue
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @State private var loginItem = RoomLoginItemModel()
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.roomMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var goalBytes: Int64 { RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal)) }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
            RoomSettingsFormRow("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }

            RoomSettingsFormRow("Open on") {
                Picker("Open on", selection: $openOn) {
                    Text("Overview").tag(RoomOpenOn.overview.rawValue)
                    Text("Last place I was").tag(RoomOpenOn.last.rawValue)
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }

            RoomSettingsFormRow("Overview", hint: "Uses your macOS full name. It stays on this Mac.") {
                RoomSettingsSwitch(title: "Greet me by name", isOn: $greetByName)
            }

            RoomSettingsFormRow("Free-space goal", hint: "Below it, the Overview and the menu-bar icon turn amber.") {
                Stepper(onIncrement: incrementGoal, onDecrement: decrementGoal) {
                    Text("Keep \(Text("\(goalBytes / 1_000_000_000)").bold()) GB free")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(goalBytes)))
                        .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: goalBytes)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("RoomSettingsFreeSpaceGoal")
            }

            RoomSettingsFormRow("Motion", hint: "Follows Reduce Motion in System Settings.") {
                // Spec 13 §3.1: disabled and off while Reduce Motion is on, with the sentence below.
                RoomSettingsSwitch(title: "Gentle motion", isOn: reduceMotion ? .constant(false) : $motionEnabled)
                    .disabled(reduceMotion)
                    .accessibilityHint("Follows Reduce Motion in System Settings.")
            }

            RoomSettingsFormRow("Developer") {
                Picker("Flag unpinned versions after", selection: $unpinnedFlagDays) {
                    ForEach(RoomDevUnreferenced.thresholdChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }.fixedSize()
            }

            RoomSettingsFormRow("Login") {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    RoomSettingsSwitch(title: "Open Room at login", isOn: Binding(
                        get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                    if let approval = loginItem.approvalHint {
                        hint(approval).transition(.opacity)
                        Button("Open Login Items…") { RoomLoginItemModel.openLoginItems() }.transition(.opacity)
                    }
                    if let error = loginItem.errorMessage { hint(error).transition(.opacity) }
                }
                .animation(motion.animation(RoomTokens.Motion.standard), value: loginItem.approvalHint)
                .animation(motion.animation(RoomTokens.Motion.standard), value: loginItem.errorMessage)
            }

            #if !ROOM_APP_STORE
            weeklyCheckRow
            #endif
            RoomSettingsFormRow("History", hint: String(localized: "settings.general.forget.help",
                    defaultValue: "Receipts stay so Restore keeps working.", bundle: RoomCopy.bundle)) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    if confirmation.stagedLines(prefix: forgetID).isEmpty {
                        RoomInlineConfirmButton(id: forgetID,
                            title: String(localized: "settings.general.forget", defaultValue: "Forget history…", bundle: RoomCopy.bundle),
                            confirmTitle: String(localized: "confirm.forgetHistory", defaultValue: "Forget saved history?", bundle: RoomCopy.bundle),
                            doneLine: String(localized: "confirm.forgetHistory.done", defaultValue: "Saved history forgotten.", bundle: RoomCopy.bundle),
                            isAllowed: !isWorking() && !isForgettingHistory,
                            stage: { suspendHistory(true) }, commit: commitForgetHistory, undo: { suspendHistory(false) })
                    }
                    RoomInlineUndoRows(prefix: forgetID)
                }
            }
            Text("settings.general.privacy", bundle: RoomCopy.bundle)
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true).gridCellColumns(2)
            if hasDamagedHistory {
                RoomSettingsFormRow("Saved history", hint: String(localized: "state.damaged",
                        defaultValue: "Some saved history couldn't be read and was set aside.", bundle: RoomCopy.bundle)) {
                    Button {
                        let directory = RoomStateStore.defaultDirectory.appendingPathComponent("Damaged", isDirectory: true)
                        NSWorkspace.shared.activateFileViewerSelecting([directory])
                    } label: {
                        Text("state.damaged.reveal", bundle: RoomCopy.bundle)
                    }
                }
            }
        }
        .padding(.top, 18).padding(.bottom, 18).padding(.horizontal, 40)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refreshStatus() }
        .task {
            await insights.volumeHistory.waitForLoad()
            await model.cachesCheckStore.waitForLoad()
            hasDamagedHistory = await !RoomStateStore.shared.damagedFileNames.isEmpty
        }
        .onDisappear { confirmation.finish(forgetID) }
        .onChange(of: controlActiveState) { _, state in
            if state == .key { loginItem.refreshStatus() }
        }
    }

    #if !ROOM_APP_STORE
    private var weeklyCheckRow: some View {
        let threshold = weeklyCheck.thresholdGB
        let thresholdLabel = RoomFormat.overviewBytes(Int64(threshold) * 1_000_000_000)
        let format = String(localized: "settings.general.weekly", defaultValue: "Tell me when caches grow by more than %@ in a week", bundle: RoomCopy.bundle)
        return RoomSettingsFormRow("Weekly check", hint: String(localized: "settings.general.weekly.help",
                defaultValue: "A notification, never an automatic cleanup.", bundle: RoomCopy.bundle)) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                RoomSettingsSwitch(title: String.localizedStringWithFormat(format, thresholdLabel), isOn: Binding(
                    get: { weeklyCheck.enabled || weeklyCheck.permissionPending },
                    set: { weeklyCheck.setEnabled($0) }))
                    .disabled(weeklyCheck.permissionPending)
                    .accessibilityIdentifier("RoomWeeklyCachesCheck")
                Stepper(value: Binding(get: { weeklyCheck.thresholdGB }, set: { weeklyCheck.thresholdGB = $0 }),
                        in: RoomWeeklyCheck.thresholdRangeGB) {
                    Text(thresholdLabel).monospacedDigit()
                }
                .accessibilityLabel("Weekly cache growth threshold")
                if weeklyCheck.permissionDenied { hint("Notifications are off in System Settings.") }
            }
        }
    }
    #endif

    private func suspendHistory(_ value: Bool) {
        insights.volumeHistory.suspendHistory(value)
        model.cachesCheckStore.suspendHistory(value)
        rooms.suspendSizeHistory(value)
        insights.suspendSavedHistory(value)
    }

    private func commitForgetHistory() {
        isForgettingHistory = true
        RoomStateWriter.shared.forgetHistory(preparing: {
            await insights.treeStore.flush()
            await rooms.waitForStateLoad()
            await insights.volumeHistory.waitForLoad()
            await model.cachesCheckStore.waitForLoad()
        }) { _ in
            Task { @MainActor in
                await insights.clearDiskHistory()
                insights.clearPressureHistory()
                insights.volumeHistory.clearInMemory()
                model.cachesCheckStore.clearInMemory()
                rooms.clearSizeHistory()
                NotificationCenter.default.post(name: .roomSavedHistoryForgotten, object: nil)
                suspendHistory(false)
                isForgettingHistory = false
            }
        }
    }

    private var incrementGoal: (() -> Void)? {
        guard goalBytes < RoomMenuBarSettings.maximumGoalBytes else { return nil }
        return { RoomMenuBarSettings.setGoalBytes(RoomMenuBarSettings.steppedGoalBytes(from: goalBytes, by: 1), in: .standard) }
    }

    private var decrementGoal: (() -> Void)? {
        guard goalBytes > RoomMenuBarSettings.minimumGoalBytes else { return nil }
        return { RoomMenuBarSettings.setGoalBytes(RoomMenuBarSettings.steppedGoalBytes(from: goalBytes, by: -1), in: .standard) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(RoomTokens.Typography.micro).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
