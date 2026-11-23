import AppKit
import RoomCore
import SwiftUI

struct RoomMenuBarView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var cacheModel: RoomViewModel
    @Bindable var rooms: RoomRoomsModel
    let openRoom: () -> Void
    let showSettings: () -> Void
    @AppStorage(RoomMenuBarSettings.showSwapKey) private var showSwap = RoomMenuBarSettings.showSwapDefault
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var storedGoal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent

    private var presentation: RoomPopoverPresentation {
        // Reading the storage property also refreshes the card when Settings changes the goal.
        _ = storedGoal
        return RoomPopoverPresentation.make(
            input: RoomMenuBarSettings.makeInput(defaults: .standard, memoryReport: insights.memoryReport,
                diskCapacityBytes: insights.diskCapacityBytes, diskAvailableBytes: insights.diskAvailableBytes),
            diskCapacityBytes: insights.diskCapacityBytes,
            swapBytes: insights.memoryReport.flatMap(RoomMonitorPresentation.measuredSwap), showSwap: showSwap,
            caches: cacheModel.cachesCheckStore.check, room: rooms.state,
            format: RoomMenuBarFormat.live,
            formatSize: RoomFormat.gb)
    }

    var body: some View {
        let content = presentation
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.row) {
                Image(nsImage: RoomPocketMark.image(fill: 0, pointSize: 18))
                    .renderingMode(.template).frame(width: 18, height: 18).accessibilityHidden(true)
                Text(RoomPopoverPresentation.title).font(RoomTokens.Typography.section)
                Spacer(minLength: 0)
                Button(action: openSettings) {
                    Image(systemName: "gearshape").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: RoomTokens.Radius.field))
                .help(RoomPopoverPresentation.settingsTitle)
                .accessibilityLabel(RoomPopoverPresentation.settingsTitle)
                .accessibilityIdentifier("RoomPopoverSettings")
            }
            diskCard(content.disk)
            memoryCard(content.memory)
            if let caches = content.caches { cachesCard(caches) }
            roomCard(content.room)
            HStack(spacing: RoomTokens.Space.row) {
                Button(action: openOverview) {
                    Text(RoomPopoverPresentation.openRoomTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(accent.fill)
                .accessibilityIdentifier("RoomPopoverOpenRoom")
                Button(RoomPopoverPresentation.quitTitle) { NSApp.terminate(nil) }
                    .buttonStyle(.glass).accessibilityIdentifier("RoomPopoverQuit")
            }
            .font(RoomTokens.Typography.bodyStrong)
            .padding(.top, RoomTokens.Space.inner - RoomTokens.Space.row)
        }
        .foregroundStyle(RoomTokens.Ink.graphite)
        .padding(14).frame(width: 340)
        .background(RoomTokens.Surface.canvas)
        .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: content.disk.value)
        .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: content.memory.value)
        .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: content.room.accessory)
        .task {
            insights.scanMemory()
            rooms.measureIfNeeded()
        }
    }

    private func diskCard(_ disk: RoomPopoverPresentation.Disk) -> some View {
        Button { open(.disk) } label: {
            card {
                HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
                    metric(disk.value, suffix: " free", maskable: true)
                        .foregroundStyle(disk.belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.graphite)
                    Spacer(minLength: 0)
                    maskedCaption(disk.caption)
                }
                if let used = disk.usedFraction {
                    RoomPopoverDiskBar(usedFraction: used, goalFraction: disk.goalFraction, belowGoal: disk.belowGoal)
                        .padding(.top, 3).accessibilityHidden(true)
                }
                if let goal = disk.goalCaption { maskedCaption(goal) }
            }
        }
        .buttonStyle(.plain).accessibilityLabel(hide.masksNow ? "Free space, hidden" : disk.accessibilityLabel)
        .accessibilityIdentifier("RoomPopoverDiskCard")
    }

    private func memoryCard(_ memory: RoomPopoverPresentation.Memory) -> some View {
        Button { open(.memory) } label: {
            card {
                HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
                    metric(memory.value)
                    caption(memory.caption)
                    Spacer(minLength: 0)
                    if let status = memory.status {
                        HStack(spacing: 4) {
                            if let fill = memory.pocketFill {
                                RoomPopoverPocket(fill: fill).frame(width: 14, height: 14)
                                    .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: fill)
                            }
                            Text(status).font(RoomTokens.Typography.body)
                        }
                        .foregroundStyle(pressureColor(memory.pressure))
                        .fixedSize()
                        .animation(motion.isFull ? RoomTokens.Motion.standard : nil, value: memory.pressure)
                    }
                }
                RoomPopoverSparkline(values: insights.memorySamples.values).frame(height: 22)
                    .accessibilityHidden(true)
                if let swap = memory.swapCaption { caption(swap).contentTransition(.numericText()) }
            }
        }
        .buttonStyle(.plain).accessibilityLabel(memory.accessibilityLabel)
        .accessibilityIdentifier("RoomPopoverMemoryCard")
    }

    private func cachesCard(_ caches: RoomPopoverPresentation.Card) -> some View {
        Button(action: openCaches) {
            card {
                HStack(spacing: RoomTokens.Space.row) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoomMaskable(caches.title).font(RoomTokens.Typography.bodyStrong).contentTransition(.numericText())
                        maskedCaption(caches.caption)
                    }
                    Spacer(minLength: 0)
                    if let action = caches.accessory {
                        Text(action).font(RoomTokens.Typography.body).foregroundStyle(accent.text).fixedSize()
                    }
                }
            }
        }
        .buttonStyle(.plain).accessibilityLabel(hide.masksNow ? "Caches, hidden" : caches.accessibilityLabel)
        .accessibilityIdentifier("RoomPopoverCachesCard")
    }

    private func roomCard(_ room: RoomPopoverPresentation.Card) -> some View {
        Button(action: openPinnedRoom) {
            card {
                HStack(spacing: RoomTokens.Space.row) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoomMaskable(room.title, kind: isEmptyRoom ? .figure : .name).font(RoomTokens.Typography.bodyStrong).lineLimit(1).truncationMode(.middle)
                        maskedCaption(room.caption)
                            .foregroundStyle(isUnreadableRoom ? accent.text : RoomTokens.Ink.secondary)
                    }
                    Spacer(minLength: 0)
                    if let accessory = room.accessory {
                        RoomMaskable(accessory)
                            .font(isEmptyRoom ? RoomTokens.Typography.body : RoomTokens.Typography.numeric)
                            .foregroundStyle(isEmptyRoom ? accent.text : RoomTokens.Ink.graphite)
                            .contentTransition(.numericText()).fixedSize()
                    }
                }
            }
        }
        .buttonStyle(.plain).accessibilityLabel(hide.masksNow ? "Room, hidden" : room.accessibilityLabel)
        .accessibilityIdentifier("RoomPopoverRoomCard")
    }

    private var isEmptyRoom: Bool { if case .empty = rooms.state { true } else { false } }
    private var isUnreadableRoom: Bool { if case .unavailable = rooms.state { true } else { false } }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11).padding(.horizontal, RoomTokens.Space.inner)
            .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.card))
            .contentShape(RoundedRectangle(cornerRadius: RoomTokens.Radius.card))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            .contentTransition(.numericText())
    }

    private func maskedCaption(_ text: String) -> some View {
        RoomMaskable(text).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
    }

    private func metric(_ text: String, suffix: String = "", maskable: Bool = false) -> some View {
        let amount = !suffix.isEmpty && text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
        let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
        let number = parts.first ?? amount
        let unit = parts.count == 2 ? " \(parts[1])\(suffix)" : ""
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Group {
                if maskable { RoomMaskable(number) } else { Text(number) }
            }
            .font(RoomTokens.Typography.figure)
            .tracking(RoomTokens.Typography.tracking(for: 22))
            Text(unit).font(RoomTokens.Typography.unit(for: 22))
        }
        .monospacedDigit().contentTransition(.numericText()).lineLimit(1).fixedSize()
    }

    private func pressureColor(_ pressure: RoomMenuBarPressure) -> Color {
        switch pressure {
        case .normal: RoomTokens.Status.normal
        case .elevated: RoomTokens.Status.elevated
        case .critical: RoomTokens.Status.critical
        case .unknown: RoomTokens.Ink.secondary
        }
    }

    func open(_ destination: RoomInsightDestination) {
        insights.requestedDestination = destination
        openRoom()
    }

    func openCaches() { open(.clean) }

    func openOverview() { open(.overview) }

    func openSettings() {
        showSettings()
    }

    func openPinnedRoom() {
        guard let room = rooms.pinnedRoom, !isUnreadableRoom else {
            openRoom()
            rooms.chooseFolder()
            return
        }
        insights.requestedPinnedRoom = room.id
        openRoom()
    }
}

private struct RoomPopoverDiskBar: View {
    let usedFraction: Double
    let goalFraction: Double?
    let belowGoal: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(RoomTokens.Surface.track)
                Capsule().fill(RoomTokens.Surface.used)
                    .frame(width: geometry.size.width * usedFraction)
                if let goalFraction {
                    Rectangle().fill(belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.graphite)
                        .frame(width: 2, height: 11)
                        .position(x: geometry.size.width * goalFraction, y: 4)
                }
            }
        }.frame(height: 8)
    }
}

private struct RoomPopoverSparkline: View {
    let values: [Int64]
    @Environment(\.roomAccent) private var accent

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points = RoomSparkline.points(values, width: Double(geometry.size.width), height: Double(geometry.size.height))
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))) }
            }.stroke(accent.text, lineWidth: 1.5)
        }
    }
}

/// Re-renders the same pocket geometry at intermediate fills during Motion.standard.
private struct RoomPopoverPocket: View, Animatable {
    nonisolated var fill: Double
    nonisolated var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }
    var body: some View {
        Image(nsImage: RoomPocketMark.image(fill: fill, pointSize: 14)).renderingMode(.template)
    }
}
