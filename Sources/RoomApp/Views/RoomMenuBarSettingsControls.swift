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
    /// Opacity only: the 150 ms fade is the board's rule for every change here, with or without Reduce Motion.
    private var fade: Animation? { motion.animation(RoomTokens.Motion.fade) }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("Preview. Left: normal. Right: pressure elevated. It changes as you choose.")
                    .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                previewGrid
                    .opacity(enabled ? 1 : 0.45)
                    .allowsHitTesting(false)
                    .animation(fade, value: enabled)
            }
        }
        Section {
            ForEach(RoomMenuBarSettings.controlOrder, id: \.self) { control in
                controlView(control)
                    .disabled(control != .show && !enabled)
                    .animation(fade, value: enabled)
            }
        }
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
            Toggle("Show in menu bar", isOn: $enabled).toggleStyle(.switch)
        case .value:
            controlRow("Value") {
                Picker("Value", selection: value) {
                    Text("Memory").tag(RoomMenuBarValueMode.memory)
                    Text("Free disk").tag(RoomMenuBarValueMode.disk)
                    Text("Both").tag(RoomMenuBarValueMode.both)
                    Text("None").tag(RoomMenuBarValueMode.none)
                        .disabled(!RoomMenuBarSettings.canSelectValue(.none, icon: input.icon))
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("RoomSettingsMenuBarValue")
            }
        case .icon:
            controlRow("Icon") {
                Picker("Icon", selection: icon) {
                    ForEach(RoomMenuBarSettings.iconOrder, id: \.self) { mode in
                        Text(iconTitle(mode)).tag(mode)
                            .disabled(!RoomMenuBarSettings.canSelectIcon(mode, value: input.value))
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .help("Symbol shows a chip for memory and a drive for storage. Both and Icon only show the Room mark.")
            }
        case .colour:
            controlRow("Colour") {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Toggle("Only when pressure rises or space is below goal", isOn: $tintOnlyWhenNeeded)
                        .toggleStyle(.switch)
                    Text("The pocket fills either way, so colour is never the only signal.")
                        .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .swap:
            controlRow("Swap") {
                Toggle("Show swap in the popover", isOn: $showSwap).toggleStyle(.switch)
            }
        case .pinnedRoom:
            HStack(spacing: RoomTokens.Space.row) {
                Text("Pinned Room")
                Spacer(minLength: 0)
                if let room = rooms.pinnedRoom {
                    Text(room.name).lineLimit(1).truncationMode(.middle).transition(.opacity)
                    Text("·").foregroundStyle(RoomTokens.Ink.secondary).transition(.opacity)
                    Button("Unpin") { rooms.unpin() }
                        .buttonStyle(.plain).foregroundStyle(accent.text).transition(.opacity)
                } else {
                    Button("Pin a Folder…") {
                        NSApp.activate()
                        rooms.chooseFolder()
                    }
                    .buttonStyle(.plain).foregroundStyle(accent.text).transition(.opacity)
                }
            }
            .animation(fade, value: rooms.pinnedRoom?.id)
        }
    }

    private func iconTitle(_ mode: RoomMenuBarIconMode) -> String {
        switch mode { case .mark: "Room mark"; case .symbol: "Symbol"; case .none: "None" }
    }

    private func controlRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            Text(title).frame(width: 54, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
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
