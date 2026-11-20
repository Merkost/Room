import AppKit
import SwiftUI

/// Settings owns every menu-bar preference; the popover only opens destinations.
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
    @Environment(\.roomAccent) private var accent

    private var input: RoomMenuBarInput {
        var input = RoomMenuBarSettings.makeInput(defaults: .standard, memoryReport: insights.memoryReport,
            diskCapacityBytes: insights.diskCapacityBytes, diskAvailableBytes: insights.diskAvailableBytes)
        if let storedValue { input.value = RoomMenuBarValueMode(rawValue: storedValue) ?? .memory }
        input.icon = RoomMenuBarIconMode(rawValue: storedIcon) ?? .symbol
        input.tintOnlyWhenNeeded = tintOnlyWhenNeeded
        input.goalBytes = goalBytes
        return input
    }

    private var goalBytes: Int64 { RoomMenuBarSettings.clampGoalBytes(Int64(storedGoal)) }
    private var value: Binding<RoomMenuBarValueMode> {
        Binding(get: { input.value }, set: { RoomMenuBarSettings.setValue($0, in: .standard) })
    }
    private var icon: Binding<RoomMenuBarIconMode> {
        Binding(get: { input.icon }, set: { RoomMenuBarSettings.setIcon($0, in: .standard) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: RoomTokens.Space.tight) {
                RoomMenuBarPreviewStrip(input: input, appearance: .aqua)
                RoomMenuBarPreviewStrip(input: input, appearance: .darkAqua)
            }
            .disabled(!enabled)
            Toggle("Show in menu bar", isOn: $enabled).toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 14) {
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
                controlRow("Icon") {
                    Picker("Icon", selection: icon) {
                        Text("Symbol").tag(RoomMenuBarIconMode.symbol)
                        Text("Room mark").tag(RoomMenuBarIconMode.mark)
                        Text("None").tag(RoomMenuBarIconMode.none)
                            .disabled(!RoomMenuBarSettings.canSelectIcon(.none, value: input.value))
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .help("Symbol shows a chip for memory and a drive for storage. Both and Icon only show the Room mark.")
                }
                controlRow("Colour") {
                    Toggle("Only when pressure rises or space is below goal", isOn: $tintOnlyWhenNeeded)
                        .toggleStyle(.switch)
                        .help("The pocket fills either way, so colour is never the only signal.")
                }
                controlRow("Swap") {
                    Toggle("Show swap in the popover", isOn: $showSwap).toggleStyle(.switch)
                }
                Stepper(onIncrement: incrementGoal, onDecrement: decrementGoal) {
                    (Text("Keep ") + Text("\(goalBytes / 1_000_000_000)").bold() + Text(" GB free"))
                        .monospacedDigit().contentTransition(.numericText())
                }
                .help("Below it, the menu-bar icon turns amber.")
                .accessibilityIdentifier("RoomSettingsFreeSpaceGoal")
                HStack(spacing: RoomTokens.Space.row) {
                    Text("Pinned Room")
                    Spacer(minLength: 0)
                    if let room = rooms.pinnedRoom {
                        Text(room.name).lineLimit(1).truncationMode(.middle)
                        Text("·").foregroundStyle(RoomTokens.Ink.secondary)
                        Button("Unpin") { rooms.unpin() }
                            .buttonStyle(.plain).foregroundStyle(accent.text)
                    } else {
                        Button("Pin a Folder…") {
                            NSApp.activate()
                            rooms.chooseFolder()
                        }
                        .buttonStyle(.plain).foregroundStyle(accent.text)
                    }
                }
            }
            .disabled(!enabled)
        }
        .font(RoomTokens.Typography.body)
        .foregroundStyle(RoomTokens.Ink.graphite)
    }

    private var incrementGoal: (() -> Void)? {
        guard goalBytes < RoomMenuBarSettings.maximumGoalBytes else { return nil }
        return { RoomMenuBarSettings.setGoalBytes(RoomMenuBarSettings.steppedGoalBytes(from: goalBytes, by: 1), in: .standard) }
    }

    private var decrementGoal: (() -> Void)? {
        guard goalBytes > RoomMenuBarSettings.minimumGoalBytes else { return nil }
        return { RoomMenuBarSettings.setGoalBytes(RoomMenuBarSettings.steppedGoalBytes(from: goalBytes, by: -1), in: .standard) }
    }

    private func controlRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Text(title).frame(width: 54, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
    }
}

private struct RoomMenuBarPreviewStrip: View {
    let input: RoomMenuBarInput
    let appearance: NSAppearance.Name

    var body: some View {
        GeometryReader { geometry in
            let preview = RoomMenuBarPreview.make(input: input,
                format: RoomMenuBarFormat(
                    memory: { bytes in MainActor.assumeIsolated { RoomFormat.memoryBytes(bytes) } },
                    disk: { bytes in MainActor.assumeIsolated { RoomFormat.bytes(bytes) } }),
                appearance: appearance, width: geometry.size.width)
            Image(nsImage: preview.image).renderingMode(.original)
                .frame(width: geometry.size.width, height: 22)
                .accessibilityLabel(appearance == .darkAqua ? "Dark menu bar preview" : "Light menu bar preview")
                .accessibilityValue(preview.output.accessibilityValue)
        }
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: RoomTokens.Radius.tile))
    }
}
