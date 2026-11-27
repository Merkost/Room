import SwiftUI

/// The scan animation, in two sizes. A room's walls trace while it is read, dots (or a wash) rise only as far as the
/// engine has counted, and the figure appears when it is done. Nothing moves once the scan ends.

/// Overview's version: large rooms that fill with counted dots.
struct RoomScanBoard: View {
    let tiles: [RoomScanTile]
    let open: (String) -> Void

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    private var rows: [[RoomScanTile]] {
        stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }

    var body: some View {
        VStack(spacing: RoomTokens.Screen2.planGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: RoomTokens.Screen2.planGap) {
                    ForEach(row) { tile in room(tile) }
                }
            }
        }
        .frame(minHeight: RoomTokens.Scan.boardMinHeight, maxHeight: .infinity)
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan progress")
    }

    private func room(_ tile: RoomScanTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Screen2.planRadius)
        let done = tile.state == .done
        return Button { open(tile.id) } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(done || tile.isReading ? RoomTokens.Surface.tile : Color.clear)
                flood(tile)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        RoomGlyphView(glyph: tile.glyph, size: 14, weight: 1.5)
                            .foregroundStyle(done || tile.isReading ? accent.text : RoomTokens.Ink.tertiary)
                        Text(tile.title).font(RoomTokens.Typography.bodyStrong).foregroundStyle(RoomTokens.Ink.graphite)
                        Spacer(minLength: 0)
                        if done { RoomScanCheck() }
                    }
                    if done, let value = tile.value {
                        RoomMaskable(value)
                            .font(RoomTokens.Screen2.figure)
                            .foregroundStyle(RoomTokens.Ink.graphite)
                            .transition(.opacity.combined(with: .offset(y: motion.isFull ? RoomTokens.Screen2.enterRise : 0)))
                    } else {
                        Text(tile.detail)
                            .font(RoomTokens.Typography.captionNumeric)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .lineLimit(1)
                .padding(RoomTokens.Screen2.planPad)
                RoomScanOutline(cornerRadius: RoomTokens.Screen2.planRadius, reading: tile.isReading, done: done)
            }
            .contentShape(shape)
            .clipShape(shape)
        }
        .buttonStyle(RoomPressStyle())
        .animation(motion.animation(RoomTokens.Motion.room, fallback: RoomTokens.Motion.fade), value: tile)
        .accessibilityLabel(tile.title)
        .accessibilityValue(spoken(tile))
        .accessibilityHint("Opens \(tile.title)")
    }

    /// Dots rising from the floor to the counted fraction.
    private func flood(_ tile: RoomScanTile) -> some View {
        GeometryReader { geometry in
            // Whole rows only, rounded down, so a room never reads fuller than the count or cuts a dot in half.
            let pitch = RoomTokens.Screen2.planPitch, gap = pitch - RoomTokens.Screen2.planDot
            let rows = max(0, ((geometry.size.height + gap) / pitch).rounded(.down))
            RoomPlanDots(color: accent.text)
                .frame(height: max(0, rows * pitch - gap + 0.5))   // the half point keeps the last row
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: (rows * tile.fill).rounded(.down) * pitch)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(tile.state == .done ? RoomTokens.Scan.restingDots : 1)
        .padding(.top, RoomTokens.Screen2.planDotsTop)
        .padding([.horizontal, .bottom], RoomTokens.Screen2.planPad)
    }

    private func spoken(_ tile: RoomScanTile) -> String {
        guard tile.state == .done, let value = tile.value else { return tile.detail }
        return hide.masksNow ? "done, size hidden" : "done, \(value)"
    }
}

/// The smaller version for Developer: one short room per part, washed in as each is read.
struct RoomScanStrip: View {
    let tiles: [RoomScanTile]

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(spacing: RoomTokens.Screen2.planGap) {
            ForEach(tiles) { tile in room(tile) }
        }
        .frame(height: RoomTokens.Scan.stripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan progress")
    }

    private func room(_ tile: RoomScanTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.card)
        let done = tile.state == .done
        return ZStack(alignment: .topLeading) {
            shape.fill(done ? accent.wash : tile.isReading ? RoomTokens.Surface.tile : Color.clear)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title).font(RoomTokens.Typography.bodyStrong).foregroundStyle(RoomTokens.Ink.graphite)
                Group {
                    if done, let value = tile.value { RoomMaskable(value) } else { Text(tile.detail) }
                }
                .font(RoomTokens.Typography.captionNumeric)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .contentTransition(.opacity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(RoomTokens.Space.row)
            RoomScanOutline(cornerRadius: RoomTokens.Radius.card, reading: tile.isReading, done: done)
        }
        .frame(maxWidth: .infinity)
        .animation(motion.animation(RoomTokens.Motion.room, fallback: RoomTokens.Motion.fade), value: tile)
        .accessibilityElement(children: .combine)
    }
}

/// The smallest version, for a scan that only counts places (Caches, Disk Map): one wall segment per place.
struct RoomScanSegments: View {
    let done: Int
    let total: Int

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent

    var body: some View {
        // Past this many places the segments would be hairlines, so they stand for equal shares instead.
        let count = min(total, RoomTokens.Scan.maxSegments)
        let filled = total > 0 ? done * count / total : 0
        HStack(spacing: 3) {
            ForEach(0..<max(0, count), id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(index < filled ? accent.text : RoomTokens.Surface.track)
                    if index == filled { RoomScanOutline(cornerRadius: 3, reading: true, done: false) }
                }
            }
        }
        .frame(height: RoomTokens.Scan.segmentHeight)
        .animation(motion.animation(RoomTokens.Motion.room, fallback: RoomTokens.Motion.fade), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(done) of \(total)")
    }
}

/// A room's wall: a dash that laps it while it is read, a dashed plan before, a quiet line after.
struct RoomScanOutline: View {
    let cornerRadius: CGFloat
    let reading: Bool
    let done: Bool

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius).inset(by: 1)
        Group {
            if reading, motion.isFull {
                TimelineView(.animation) { context in
                    let lap = RoomTokens.Motion.traceLap
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lap) / lap
                    let end = phase + Double(RoomTokens.Motion.traceDashFraction)
                    ZStack {
                        shape.stroke(accent.text.opacity(0.25), lineWidth: 1.5)
                        shape.trim(from: phase, to: min(1, end)).stroke(accent.text, lineWidth: 2)
                        if end > 1 { shape.trim(from: 0, to: end - 1).stroke(accent.text, lineWidth: 2) }
                    }
                }
            } else if reading {
                shape.stroke(accent.text, lineWidth: 2)
            } else {
                shape.stroke(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: 1, dash: done ? [] : [4, 4]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The finished room's check, drawn once.
private struct RoomScanCheck: View {
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var drawn = false

    var body: some View {
        RoomTickMark()
            .trim(from: 0, to: drawn || !motion.isFull ? 1 : 0)
            .stroke(accent.text, style: StrokeStyle(lineWidth: RoomTokens.Screen2.tickStroke, lineCap: .round, lineJoin: .round))
            .frame(width: RoomTokens.Screen2.tick, height: RoomTokens.Screen2.tick)
            .onAppear { withAnimation(motion.animation(RoomTokens.Motion.success, fallback: nil)) { drawn = true } }
            .accessibilityHidden(true)
    }
}
