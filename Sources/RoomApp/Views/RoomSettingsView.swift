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
                if selectedTab == RoomSettingsTab.general.rawValue { RoomGeneralSettingsView().transition(.opacity) }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(RoomSettingsTab.general.rawValue)

            VStack {
                if selectedTab == RoomSettingsTab.menubar.rawValue {
                    Form {
                        RoomMenuBarSettingsControls(insights: insights, rooms: rooms, enabled: $menuBarEnabled)
                    }
                    .formStyle(.grouped).scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                }
            }
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            .tag(RoomSettingsTab.menubar.rawValue)

            VStack {
                if selectedTab == RoomSettingsTab.folders.rawValue {
                    RoomFolderAccessSettingsView(insights: insights).transition(.opacity)
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
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)

            Picker("Open on", selection: $openOn) {
                Text("Overview").tag(RoomOpenOn.overview.rawValue)
                Text("Last place I was").tag(RoomOpenOn.last.rawValue)
            }
            .pickerStyle(.segmented)

            LabeledContent("Free-space goal") {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Stepper(onIncrement: incrementGoal, onDecrement: decrementGoal) {
                        (Text("Keep ") + Text("\(goalBytes / 1_000_000_000)").bold() + Text(" GB free"))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(goalBytes)))
                            .animation(motion.animation(RoomTokens.Motion.standard), value: goalBytes)
                    }
                    .accessibilityIdentifier("RoomSettingsFreeSpaceGoal")
                    hint("Below it, the Overview and the menu-bar icon turn amber.")
                }
            }

            LabeledContent("Motion") {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    // Spec 13 §3.1: disabled and off while Reduce Motion is on, with the sentence below.
                    Toggle("Gentle motion", isOn: reduceMotion ? .constant(false) : $motionEnabled).toggleStyle(.switch)
                        .disabled(reduceMotion)
                        .accessibilityHint("Follows Reduce Motion in System Settings.")
                    hint("Follows Reduce Motion in System Settings.")
                }
            }

            LabeledContent("Login") {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Toggle("Open Room at login", isOn: Binding(
                        get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                        .toggleStyle(.switch)
                    if let approval = loginItem.approvalHint {
                        hint(approval).transition(.opacity)
                        Button("Open Login Items…") { RoomLoginItemModel.openLoginItems() }.transition(.opacity)
                    }
                    if let error = loginItem.errorMessage { hint(error).transition(.opacity) }
                }
                .animation(motion.animation(RoomTokens.Motion.standard), value: loginItem.approvalHint)
                .animation(motion.animation(RoomTokens.Motion.standard), value: loginItem.errorMessage)
            }
        }
        .formStyle(.grouped).scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refreshStatus() }
        .onChange(of: controlActiveState) { _, state in
            if state == .key { loginItem.refreshStatus() }
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
        Text(text).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
