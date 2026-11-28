import AppKit
import RoomCore
import SwiftUI

/// The room map's layout (nav-v3): the largest room gets the first column, the rest pair up in columns; widths and
/// heights follow bytes. Pure, so the frames (and the zoom origins taken from them) are tested.
nonisolated enum RoomDiskRoomsLayout {
    static let maxRooms = 9
    /// Rooms under this share of the level fold into Other once there are more than `foldAfter` rooms, so the last
    /// column never gets so narrow that a name has to be cut (mockup: seven rooms, "Other 8 GB").
    static let foldShare = 0.025
    static let foldAfter = 5
    /// The narrowest a room may be: a 14 pt glyph, a name like "Downloads" and the tile's padding.
    static let minimumTile = CGSize(width: 124, height: 34)

    /// How many of `bytes` (largest first) get a room of their own; the rest join Other.
    static func kept(_ bytes: [Int64], foldedBytes: Int64 = 0) -> Int {
        let total = Double(max(1, bytes.reduce(0, +) + foldedBytes))
        var count = 0
        for (index, value) in bytes.enumerated() {
            if index >= maxRooms - 1 && index < bytes.count - 1 { break }
            if index >= foldAfter && Double(value) / total < foldShare { break }
            count = index + 1
        }
        if count < bytes.count || foldedBytes > 0 { count = min(count, maxRooms - 1) }
        return max(1, count)
    }

    /// Column groups of indices, like the mockup's `cols()`.
    static func columns(count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        var columns: [[Int]] = [[0]]
        var index = 1
        while index < count {
            columns.append(Array(index..<min(index + 2, count)))
            index += 2
        }
        if columns.count > 3, columns.last?.count == 1, let last = columns.popLast() {
            columns[columns.count - 1].append(contentsOf: last)
        }
        return columns
    }

    /// Frames for `bytes` (largest first) in `size`, with `gap` between rooms and a floor so every room can hold a label.
    static func frames(_ bytes: [Int64], in size: CGSize, gap: CGFloat, minimum: CGSize) -> [CGRect] {
        let groups = columns(count: bytes.count)
        guard !groups.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let weight = { (i: Int) in max(1, Double(bytes[i])) }
        let columnWeights = groups.map { $0.reduce(0) { $0 + weight($1) } }
        let usableWidth = max(0, size.width - gap * CGFloat(groups.count - 1))
        var widths = columnWeights.map { CGFloat($0 / columnWeights.reduce(0, +)) * usableWidth }
        let short = widths.indices.filter { widths[$0] < minimum.width }
        if !short.isEmpty, usableWidth > minimum.width * CGFloat(groups.count) {
            let deficit = short.reduce(CGFloat(0)) { $0 + minimum.width - widths[$1] }
            let others = widths.indices.filter { !short.contains($0) }
            let othersTotal = others.reduce(CGFloat(0)) { $0 + widths[$1] }
            for i in short { widths[i] = minimum.width }
            for i in others { widths[i] -= deficit * widths[i] / max(1, othersTotal) }
        }
        var frames = Array(repeating: CGRect.zero, count: bytes.count)
        var x: CGFloat = 0
        for (column, group) in groups.enumerated() {
            let usableHeight = max(0, size.height - gap * CGFloat(group.count - 1))
            let total = group.reduce(0) { $0 + weight($1) }
            var heights = group.map { CGFloat(weight($0) / total) * usableHeight }
            if group.count == 2 {
                if heights[1] < minimum.height { heights = [usableHeight - minimum.height, minimum.height] }
                else if heights[0] < minimum.height { heights = [minimum.height, usableHeight - minimum.height] }
            }
            var y: CGFloat = 0
            for (row, index) in group.enumerated() {
                frames[index] = CGRect(x: x, y: y, width: widths[column], height: heights[row])
                y += heights[row] + gap
            }
            x += widths[column] + gap
        }
        return frames
    }

    /// Where a step inside zooms from: the room's centre in the map's unit space.
    static func anchor(of frame: CGRect, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: frame.midX / size.width, y: frame.midY / size.height)
    }
}

/// One room on the map, as the view needs it.
struct RoomDiskRoom: Identifiable, Equatable {
    let room: RoomMapSelection.Room
    let kind: StorageKind?
    let canStepInside: Bool
    let isOther: Bool
    var id: String { room.path }
}

/// The Disk Map evidence: rooms for the current level. Click to look, click again (or Step inside) to go one level in;
/// a tick on each room, or ⌘-click, selects several. Protected rooms have no tick.
struct RoomDiskRoomsView: View {
    let rooms: [RoomDiskRoom]
    let picked: String?
    let selection: RoomMapSelection
    let ticksAvailable: Bool
    let pick: (String) -> Void
    let toggle: (RoomDiskRoom) -> Void
    let stepInside: (String, UnitPoint) -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geometry in
            let frames = RoomDiskRoomsLayout.frames(rooms.map(\.room.bytes), in: geometry.size,
                                                    gap: RoomTokens.Screen2.planGap, minimum: RoomDiskRoomsLayout.minimumTile)
            let total = max(1, rooms.reduce(Int64(0)) { $0 + $1.room.bytes })
            ZStack(alignment: .topLeading) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    if frames.indices.contains(index) {
                        tile(room, index: index, small: Double(room.room.bytes) / Double(total) < 0.06,
                             anchor: RoomDiskRoomsLayout.anchor(of: frames[index], in: geometry.size))
                            .frame(width: frames[index].width, height: frames[index].height)
                            .offset(x: frames[index].minX, y: frames[index].minY)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rooms in this folder")
    }

    private func tile(_ room: RoomDiskRoom, index: Int, small: Bool, anchor: UnitPoint) -> some View {
        let isPicked = picked == room.id && selection.isEmpty
        let isTicked = selection.contains(room.id)
        let showsTick = ticksAvailable && room.room.protection == nil && !room.isOther
            && (hovered == room.id || !selection.isEmpty || isTicked)
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Screen2.mapTileRadius)
        let ink = max(4, 20 - Double(index) * 2.6) / 100
        return ZStack(alignment: .topLeading) {
            shape.fill(RoomTokens.Ink.graphite.opacity(hovered == room.id ? ink + 0.05 : ink))
            if isTicked {
                shape.strokeBorder(accent.text, lineWidth: 2)
            } else if isPicked {
                shape.strokeBorder(RoomTokens.Ink.secondary, lineWidth: contrast == .increased ? 2 : 1.5)
            }
            label(room, small: small)
                .padding(.horizontal, RoomTokens.Space.row)
                .padding(.vertical, small ? 0 : 10)
                .frame(maxHeight: small ? .infinity : nil, alignment: .leading)
            if showsTick {
                Button { toggle(room) } label: { RoomTick(on: isTicked) }
                    .buttonStyle(.plain)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: small ? .infinity : nil,
                           alignment: small ? .trailing : .topTrailing)
                    .accessibilityLabel(isTicked ? "Untick \(spokenName(room))" : "Tick \(spokenName(room))")
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { inside in hovered = inside ? room.id : (hovered == room.id ? nil : hovered) }
        .onTapGesture(count: 2) { if room.canStepInside { stepInside(room.id, anchor) } }
        .onTapGesture { tap(room, anchor: anchor) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(room))
        .accessibilityValue(hide.masksNow ? "size hidden" : RoomFormat.gb(room.room.bytes))
        .accessibilityAddTraits(isTicked || isPicked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { tap(room, anchor: anchor) }
        .accessibilityActions {
            if room.canStepInside { Button("Step inside") { stepInside(room.id, anchor) } }
            if ticksAvailable, room.room.protection == nil, !room.isOther {
                Button(isTicked ? "Untick" : "Tick") { toggle(room) }
            }
        }
    }

    private func tap(_ room: RoomDiskRoom, anchor: UnitPoint) {
        let command = NSEvent.modifierFlags.contains(.command)
        if ticksAvailable && (command || !selection.isEmpty) {
            toggle(room)
        } else if picked == room.id, room.canStepInside {
            stepInside(room.id, anchor)
        } else {
            pick(room.id)
        }
    }

    private func spokenName(_ room: RoomDiskRoom) -> String { hide.masksNow ? "Room, name hidden" : room.room.name }

    @ViewBuilder private func label(_ room: RoomDiskRoom, small: Bool) -> some View {
        let glyph = room.kind.map { RoomOverviewFloorPlan.glyph($0.rawValue) } ?? .folder
        let color = room.kind.flatMap { RoomTokens.Kind(rawValue: $0.rawValue) }?.mark ?? RoomTokens.Ink.secondary
        let name = HStack(spacing: 6) {
            RoomGlyphView(glyph: glyph, size: 14, weight: 1.5).foregroundStyle(color)
            RoomMaskable(room.room.name, kind: .name)
                .font(RoomTokens.Typography.bodyStrong)
                .foregroundStyle(RoomTokens.Ink.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .layoutPriority(1)
        let size = RoomMaskable(RoomFormat.gb(room.room.bytes))
            .font(RoomTokens.Typography.captionNumeric)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .lineLimit(1)
        if small {
            // One line when it fits ("Other 8 GB"); otherwise the name keeps the room and the size gives way.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { name; size }
                name
            }
        } else {
            VStack(alignment: .leading, spacing: 2) { name; size }
        }
    }
}

/// The zoom when stepping inside (from the room's centre, slightly small) or back out (from the middle, slightly
/// large). Reduce Motion keeps only the fade; the keyboard never animates it.
struct RoomDiskZoom: ViewModifier {
    let scale: CGFloat
    let anchor: UnitPoint
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(scale, anchor: anchor).opacity(opacity).blur(radius: blur)
    }

    static func transition(inward: Bool, anchor: UnitPoint, motion: RoomMotionPolicy) -> AnyTransition {
        guard motion.isFull else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: RoomDiskZoom(scale: inward ? 0.9 : 1.06, anchor: inward ? anchor : .center,
                                                     opacity: 0, blur: 4),
                                 identity: RoomDiskZoom(scale: 1, anchor: inward ? anchor : .center, opacity: 1, blur: 0)),
            removal: .identity)
    }
}
