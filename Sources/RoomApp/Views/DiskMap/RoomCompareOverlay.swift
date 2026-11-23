import RoomCore
import SwiftUI

struct RoomCompareOverlay: View {
    let earlier: RoomTreeNode
    let current: RoomTreeNode
    let earlierDate: Date
    let hidden: Bool
    let close: () -> Void
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var divider = RoomCompareDivider()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: RoomTokens.Space.row) {
            HStack {
                Text(tag(earlierDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), bytes: earlier.allocatedBytes))
                Spacer()
                Text(tag("Now", bytes: current.allocatedBytes))
                Button("Done", action: close).buttonStyle(.borderless)
            }
            .font(RoomTokens.Typography.caption)
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * divider.position / 100
                let stroke = RoomTokens.Map.focusStroke
                ZStack(alignment: .leading) {
                    RoomMapCanvas(level: current, selection: nil, hidden: hidden, interactive: false)
                        .mask(alignment: .trailing) { Rectangle().frame(width: max(0, width - x)) }
                    RoomMapCanvas(level: earlier, selection: nil, hidden: hidden, interactive: false)
                        .mask(alignment: .leading) { Rectangle().frame(width: max(0, x)) }
                    Rectangle()
                        .fill(accent.text)
                        .frame(width: stroke)
                        .offset(x: min(max(0, x - stroke / 2), max(0, width - stroke)))
                    Image(systemName: "chevron.left.chevron.right")
                        .font(RoomTokens.Typography.micro)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                        .frame(width: 26, height: 26)
                        .background(RoomTokens.Surface.group, in: Circle())
                        .overlay { Circle().strokeBorder(focused ? accent.text : RoomTokens.Surface.line2) }
                        .offset(x: min(max(0, x - 13), max(0, width - 26)))
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .overlay {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(dividerGesture(width: width))
                }
            }
            .focusable()
            .focused($focused)
            .onKeyPress(.leftArrow) { key(.left) }
            .onKeyPress(.rightArrow) { key(.right) }
            .onKeyPress(.home) { key(.home) }
            .onKeyPress(.end) { key(.end) }
            .onKeyPress(.escape) { close(); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compare scan dates")
            .accessibilityValue((divider.position / 100).formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: _ = key(.right)
                case .decrement: _ = key(.left)
                @unknown default: break
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !hidden {
                Color.clear.frame(height: 0)
                    .accessibilityChildren {
                        ForEach(RoomCompare.rows(then: earlier, now: current), id: \.name) { row in
                            Text(RoomCompare.readout(row, thenLabel: earlierDate.formatted(.dateTime.day().month()),
                                format: RoomFormat.gb))
                        }
                    }
            }
        }
    }

    private func dividerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard width > 0 else { return }
                focused = true
                roomWithoutMotion { _ = divider.drag(toPercent: value.location.x / width * 100) }
            }
            .onEnded { value in
                guard width > 0 else { return }
                var next = divider
                next.reduceMotion = !motion.isFull
                _ = next.drag(toPercent: value.location.x / width * 100)
                let move = next.release(velocityPtPerMS: value.velocity.width / 1_000)
                apply(next, move: move)
            }
            .exclusively(before: SpatialTapGesture().onEnded { value in
                guard width > 0 else { return }
                focused = true
                var next = divider
                next.reduceMotion = !motion.isFull
                let move = next.press(atPercent: value.location.x / width * 100)
                apply(next, move: move)
            })
    }

    private func apply(_ next: RoomCompareDivider, move: RoomCompareDivider.Move) {
        switch move {
        case .instant: roomWithoutMotion { divider = next }
        case .jump120: withAnimation(RoomTokens.Motion.quick) { divider = next }
        case .glide360: withAnimation(RoomTokens.Motion.compareGlide) { divider = next }
        }
    }

    private func key(_ key: RoomCompareDivider.Key) -> KeyPress.Result {
        roomWithoutMotion { _ = divider.key(key) }
        return .handled
    }

    private func tag(_ name: String, bytes: Int64) -> String {
        hidden ? name : "\(name) · \(RoomFormat.gb(bytes))"
    }
}
