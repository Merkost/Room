import AppKit
import SwiftUI

/// Settings owns every menu-bar preference; the popover only opens destinations.
@MainActor
struct RoomMenuBarSettingsControls: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var rooms: RoomRoomsModel
    @Binding var enabled: Bool
    // An optional default must stay absent so opening Settings preserves legacy read-through.
    @AppStorage(RoomMenuBarSettings.valueKey) private var storedValue: String?
    @AppStorage(RoomMenuBarSettings.layoutKey) private var storedLayout = RoomMenuBarLayoutMode.inline.rawValue
    @AppStorage(RoomMenuBarSettings.iconKey) private var storedIcon = RoomMenuBarIconMode.symbol.rawValue
    @AppStorage(RoomMenuBarSettings.tintOnlyWhenNeededKey) private var tintOnlyWhenNeeded = true
    @AppStorage(RoomMenuBarSettings.showSwapKey) private var showSwap = RoomMenuBarSettings.showSwapDefault
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent

    private var input: RoomMenuBarInput {
        var input = RoomMenuBarSettings.makeInput(defaults: .standard, memoryReport: nil,
            diskCapacityBytes: 0, diskAvailableBytes: 0)
        if let storedValue { input.value = RoomMenuBarValueMode(rawValue: storedValue) ?? .memory }
        input.layout = RoomMenuBarLayoutMode(rawValue: storedLayout) ?? .inline
        input.icon = RoomMenuBarIconMode(rawValue: storedIcon) ?? .symbol
        input.tintOnlyWhenNeeded = tintOnlyWhenNeeded
        input.goalBytes = RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal))
        return input
    }

    private var value: Binding<RoomMenuBarValueMode> {
        Binding(get: { input.value }, set: { RoomMenuBarSettings.setValue($0, in: .standard) })
    }
    private var icon: Binding<RoomMenuBarIconMode> {
        Binding(get: { input.icon }, set: { RoomMenuBarSettings.setIcon($0, in: .standard) })
    }
    private var layout: Binding<RoomMenuBarLayoutMode> {
        Binding(get: { input.layout }, set: { RoomMenuBarSettings.setLayout($0, in: .standard) })
    }
    /// Opacity only: the 150 ms fade is the board's rule for every change here, with or without Reduce Motion.
    private var fade: Animation? { motion.animation(RoomTokens.Motion.fade) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("Preview. Left: normal. Right: pressure elevated. It changes as you choose.")
                    .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                previewGrid
                    .opacity(enabled ? 1 : 0.45)
                    .allowsHitTesting(false)
                    .animation(fade, value: enabled)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                ForEach(RoomMenuBarSettings.controlOrder, id: \.self) { control in
                    if control != .layout || input.value == .both {
                        controlView(control)
                            .disabled(control != .show && !enabled)
                            .animation(fade, value: enabled)
                            .transition(.opacity)
                    }
                }
            }
            .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: input.value)
        }
        .padding(.top, 18).padding(.bottom, 18).padding(.horizontal, 40)
        .font(RoomTokens.Typography.body)
        .foregroundStyle(RoomTokens.Ink.graphite)
    }

    private var previewGrid: some View {
        let scenarios = RoomMenuBarPreviewScenarios.inputs(from: input)
        return Grid(horizontalSpacing: RoomTokens.Space.row, verticalSpacing: RoomTokens.Space.row) {
            GridRow {
                RoomMenuBarPreviewStrip(input: scenarios.normal, appearance: .aqua)
                RoomMenuBarPreviewStrip(input: scenarios.elevated, appearance: .aqua)
            }
            GridRow {
                RoomMenuBarPreviewStrip(input: scenarios.normal, appearance: .darkAqua)
                RoomMenuBarPreviewStrip(input: scenarios.elevated, appearance: .darkAqua)
            }
        }
    }

    @ViewBuilder
    private func controlView(_ control: RoomMenuBarSettings.Control) -> some View {
        switch control {
        case .show:
            RoomSettingsFormRow("Show in menu bar") {
                HStack(spacing: 8) {
                    Toggle("Show in menu bar", isOn: $enabled).toggleStyle(.switch).labelsHidden().fixedSize()
                    Text(enabled ? "On" : "Off").foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(fade, value: enabled)
                }
            }
        case .value:
            RoomSettingsFormRow("Value") {
                Picker("Value", selection: value) {
                    Text("Memory").tag(RoomMenuBarValueMode.memory)
                    Text("Free disk").tag(RoomMenuBarValueMode.disk)
                    Text("Both").tag(RoomMenuBarValueMode.both)
                    Text("None").tag(RoomMenuBarValueMode.none)
                        .disabled(!RoomMenuBarSettings.canSelectValue(.none, icon: input.icon))
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("RoomSettingsMenuBarValue")
            }
        case .layout:
            RoomSettingsFormRow("Layout") {
                Picker("Layout", selection: layout) {
                    Text("Side by side").tag(RoomMenuBarLayoutMode.inline)
                    Text("Stacked").tag(RoomMenuBarLayoutMode.stacked)
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("RoomSettingsMenuBarLayout")
            }
        case .icon:
            RoomSettingsFormRow("Icon") {
                Picker("Icon", selection: icon) {
                    ForEach(RoomMenuBarSettings.iconOrder, id: \.self) { mode in
                        Text(iconTitle(mode)).tag(mode)
                            .disabled(!RoomMenuBarSettings.canSelectIcon(mode, value: input.value))
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .help("Symbol shows a chip for memory and a drive for storage. Both and Icon only show the Room mark.")
            }
        case .colour:
            RoomSettingsFormRow("Colour", hint: "The pocket fills either way, so colour is never the only signal.") {
                RoomSettingsSwitch(title: "Only when pressure rises or space is below goal", isOn: $tintOnlyWhenNeeded)
            }
        case .swap:
            RoomSettingsFormRow("Swap") {
                RoomSettingsSwitch(title: "Show swap in the popover", isOn: $showSwap)
            }
        case .pinnedRoom:
            RoomSettingsFormRow("Room in the popover") {
                HStack(spacing: RoomTokens.Space.row) {
                    if !rooms.visibleRooms.isEmpty {
                        Picker("Room in the popover", selection: Binding(get: { rooms.popoverRoom?.id }, set: { id in
                            if let id { rooms.move(id: id, to: 0) }
                        })) {
                            ForEach(rooms.visibleRooms) { room in Text(room.name).tag(Optional(room.id)) }
                        }.labelsHidden().fixedSize()
                    }
                    Button("Pin a Folder…") {
                        NSApp.activate()
                        rooms.chooseFolder()
                    }
                    .buttonStyle(.plain).foregroundStyle(accent.text)
                    .disabled(!rooms.canChooseFolder)
                }
            }
        }
    }

    private func iconTitle(_ mode: RoomMenuBarIconMode) -> String {
        switch mode { case .mark: "Room mark"; case .symbol: "Symbol"; case .none: "None" }
    }
}

@MainActor
private struct RoomMenuBarPreviewStrip: View {
    let input: RoomMenuBarInput
    let appearance: NSAppearance.Name
    @Environment(\.roomMotion) private var motion

    var body: some View {
        GeometryReader { geometry in
            let fixed = RoomMenuBarPreview.make(input: input, format: RoomMenuBarPreview.settingsFormat,
                appearance: appearance, width: geometry.size.width, layers: .surfaceAndClock)
            let preview = RoomMenuBarPreview.make(input: input, format: RoomMenuBarPreview.settingsFormat,
                appearance: appearance, width: geometry.size.width, layers: .itemOnly)
            // The surface and the clock stay put; only the item cross-fades, and only when it changes (150 ms).
            // Fading the whole strip dipped to the page colour half way (measured: +20 grey levels).
            let identity = String(describing: preview.output)
            ZStack {
                Image(nsImage: fixed.image).renderingMode(.original)
                    .frame(width: geometry.size.width, height: RoomMenuBarPreview.stripHeight)
                ZStack {
                    Image(nsImage: preview.image).renderingMode(.original)
                        .frame(width: geometry.size.width, height: RoomMenuBarPreview.stripHeight)
                        .id(identity)
                        .transition(.opacity)
                }
                .animation(motion.animation(RoomTokens.Motion.fade), value: identity)
            }
            .accessibilityLabel(appearance == .darkAqua ? "Dark menu bar preview" : "Light menu bar preview")
            .accessibilityValue(preview.output.accessibilityValue)
        }
        .frame(height: RoomMenuBarPreview.stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: RoomTokens.Radius.tile))
    }
}
