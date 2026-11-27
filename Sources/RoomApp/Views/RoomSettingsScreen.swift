import SwiftUI

/// Settings as a place in the window (nav-v3): General, Privacy, Monitor, Motion. Everything else (menu bar details,
/// folder access, About) stays in the Settings window, one link away.
struct RoomSettingsScreen: View {
    let openAllSettings: () -> Void

    @AppStorage("RoomOpenOn") private var openOn = RoomOpenOn.last.rawValue
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    #if !ROOM_APP_STORE
    private let weeklyCheck = RoomWeeklyCheckScheduler.shared
    #endif
    private let hideControl = RoomHideControl.shared

    private var goalBytes: Int64 { RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal)) }

    var body: some View {
        RoomScreenFrame(headline: .words("Settings"), supporting: "How Room looks and what it watches",
                        note: nil, scrollsEvidence: true) {
            VStack(alignment: .leading, spacing: 0) {
                RoomGroupLabel(text: "General")
                row(.window, "Open on", "The screen Room starts with") {
                    Menu {
                        Picker("Open on", selection: $openOn) {
                            Text("Overview").tag(RoomOpenOn.overview.rawValue)
                            Text("Last place").tag(RoomOpenOn.last.rawValue)
                        }
                        .pickerStyle(.inline).labelsHidden()
                    } label: {
                        valueLabel(openOn == RoomOpenOn.overview.rawValue ? "Overview" : "Last place")
                    }
                    .roomDropdown()
                    .accessibilityLabel("Open on")
                }
                row(.target, "Free space goal", "Overview measures against it") {
                    Menu {
                        ForEach(Self.goalChoices, id: \.self) { gb in
                            Button {
                                RoomMenuBarSettings.setGoalBytes(RoomMenuBarSettings.clampGoalBytes(gb * 1_000_000_000), in: .standard)
                            } label: {
                                if gb * 1_000_000_000 == goalBytes { Label("\(gb) GB", systemImage: "checkmark") } else { Text(verbatim: "\(gb) GB") }
                            }
                        }
                        Divider()
                        Button("Smaller") { step(-1)?() }.disabled(step(-1) == nil)
                        Button("Larger") { step(1)?() }.disabled(step(1) == nil)
                    } label: {
                        valueLabel(RoomFormat.gb(goalBytes), masked: true)
                    }
                    .roomDropdown()
                    .accessibilityLabel("Free space goal")
                    .accessibilityValue(hide.masksNow ? "size hidden" : RoomFormat.gb(goalBytes))
                }
                RoomGroupLabel(text: "Privacy")
                row(.eye, "Hide sizes and names", "For screen sharing") {
                    Toggle("Hide sizes and names", isOn: Binding(get: { hideControl.state.isOn },
                                                                 set: { if $0 != hideControl.state.isOn { hideControl.toggle() } }))
                        .toggleStyle(RoomSwitchStyle()).labelsHidden()
                }
                RoomGroupLabel(text: "Monitor")
                row(.bar, "Menu bar monitor", "Free space and pressure, always in view") {
                    Toggle("Menu bar monitor", isOn: $menuBarEnabled).toggleStyle(RoomSwitchStyle()).labelsHidden()
                }
                #if !ROOM_APP_STORE
                row(.cal, "Weekly check", "A quiet note when caches pass \(weeklyCheck.thresholdGB) GB") {
                    Toggle("Weekly check", isOn: Binding(get: { weeklyCheck.enabled || weeklyCheck.permissionPending },
                                                         set: { weeklyCheck.setEnabled($0) }))
                        .toggleStyle(RoomSwitchStyle()).labelsHidden()
                        .disabled(weeklyCheck.permissionPending)
                }
                #endif
                RoomGroupLabel(text: "Motion")
                row(.wave, "Gentle motion", reduceMotion ? "Off while Reduce Motion is on" : "Room moves a little. Off follows Reduce Motion") {
                    Toggle("Gentle motion", isOn: reduceMotion ? .constant(false) : $motionEnabled)
                        .toggleStyle(RoomSwitchStyle()).labelsHidden()
                        .disabled(reduceMotion)
                }
                Button("More settings…", action: openAllSettings)
                    .roomLink(accent)
                    .font(RoomTokens.Typography.bodyStrong)
                    .padding(.top, RoomTokens.Space.group)
                    .accessibilityHint("Opens the Settings window: menu bar, folder access and About")
            }
        } action: {
            EmptyView()
        }
    }

    static let goalChoices: [Int64] = [20, 30, 40, 50, 75, 100]

    /// A dropdown's current value; the shared dropdown style draws the capsule and chevron.
    @ViewBuilder private func valueLabel(_ text: String, masked: Bool = false) -> some View {
        if masked { RoomMaskable(text).monospacedDigit() } else { Text(text).monospacedDigit() }
    }

    private func step(_ steps: Int) -> (() -> Void)? {
        let next = RoomMenuBarSettings.steppedGoalBytes(from: goalBytes, by: steps)
        guard next != goalBytes else { return nil }
        return { RoomMenuBarSettings.setGoalBytes(next, in: .standard) }
    }

    private func row<Control: View>(_ glyph: RoomGlyph, _ title: String, _ detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            RoomQuietTile(glyph: glyph)
            Text(title).font(RoomTokens.Screen2.listName).foregroundStyle(RoomTokens.Ink.graphite)
            Text(detail).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary).lineLimit(1)
            Spacer(minLength: RoomTokens.Space.group)
            control()
        }
        .frame(minHeight: RoomTokens.Screen2.listRow + 2)
        .padding(.horizontal, RoomTokens.Space.row)
        .roomRowHover()
        .padding(.horizontal, -RoomTokens.Space.row)
        .accessibilityElement(children: .contain)
    }
}
