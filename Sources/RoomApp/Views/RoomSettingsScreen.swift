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
                    Picker("Open on", selection: $openOn) {
                        Text("Overview").tag(RoomOpenOn.overview.rawValue)
                        Text("Last place").tag(RoomOpenOn.last.rawValue)
                    }
                    .labelsHidden().fixedSize()
                }
                row(.target, "Free space goal", "Overview measures against it") {
                    Stepper(onIncrement: step(1), onDecrement: step(-1)) {
                        Text(verbatim: RoomFormat.gb(goalBytes)).monospacedDigit().foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    .fixedSize()
                    .accessibilityLabel("Free space goal")
                    .accessibilityValue(RoomFormat.gb(goalBytes))
                }
                RoomGroupLabel(text: "Privacy")
                row(.eye, "Hide sizes and names", "For screen sharing") {
                    Toggle("Hide sizes and names", isOn: Binding(get: { hideControl.state.isOn },
                                                                 set: { if $0 != hideControl.state.isOn { hideControl.toggle() } }))
                        .toggleStyle(.switch).labelsHidden()
                }
                RoomGroupLabel(text: "Monitor")
                row(.bar, "Menu bar monitor", "Free space and pressure, always in view") {
                    Toggle("Menu bar monitor", isOn: $menuBarEnabled).toggleStyle(.switch).labelsHidden()
                }
                #if !ROOM_APP_STORE
                row(.cal, "Weekly check", "A quiet note when caches pass \(weeklyCheck.thresholdGB) GB") {
                    Toggle("Weekly check", isOn: Binding(get: { weeklyCheck.enabled || weeklyCheck.permissionPending },
                                                         set: { weeklyCheck.setEnabled($0) }))
                        .toggleStyle(.switch).labelsHidden()
                        .disabled(weeklyCheck.permissionPending)
                }
                #endif
                RoomGroupLabel(text: "Motion")
                row(.wave, "Gentle motion", reduceMotion ? "Off while Reduce Motion is on" : "Room moves a little. Off follows Reduce Motion") {
                    Toggle("Gentle motion", isOn: reduceMotion ? .constant(false) : $motionEnabled)
                        .toggleStyle(.switch).labelsHidden()
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
        .accessibilityElement(children: .contain)
    }
}
