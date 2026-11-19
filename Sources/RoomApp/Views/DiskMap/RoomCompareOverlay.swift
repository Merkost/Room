import RoomCore
import SwiftUI

struct RoomCompareOverlay: View {
    let earlier: RoomTreeNode
    let current: RoomTreeNode
    let earlierDate: Date
    let hidden: Bool
    @Environment(\.roomAccent) private var accent
    @State private var divider = RoomCompareDivider()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: RoomTokens.Space.row) {
            HStack {
                Text(earlierDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                Spacer()
                Text("Now")
            }
            .font(RoomTokens.Typography.caption)
            GeometryReader { geometry in
                let x = geometry.size.width * divider.position / 100
                ZStack(alignment: .leading) {
                    RoomMapCanvas(level: current, selection: nil, hidden: hidden)
                    RoomMapCanvas(level: earlier, selection: nil, hidden: hidden)
                        .mask(alignment: .leading) { Rectangle().frame(width: max(0, x)) }
                    Rectangle()
                        .fill(accent.text)
                        .frame(width: RoomTokens.Map.focusStroke)
                        .offset(x: x)
                }
                .allowsHitTesting(false)
                .overlay {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard geometry.size.width > 0 else { return }
                            _ = divider.drag(toPercent: Double(value.location.x / geometry.size.width) * 100)
                        })
                }
            }
            .focusable()
            .focused($focused)
            .onKeyPress(.leftArrow) { _ = divider.key(.left); return .handled }
            .onKeyPress(.rightArrow) { _ = divider.key(.right); return .handled }
            .onKeyPress(.home) { _ = divider.key(.home); return .handled }
            .onKeyPress(.end) { _ = divider.key(.end); return .handled }
            .accessibilityLabel("Compare scan dates")
            .accessibilityValue(hidden ? "Hidden" : divider.position.formatted())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: _ = divider.key(.right)
                case .decrement: _ = divider.key(.left)
                @unknown default: break
                }
            }
            .accessibilityChildren {
                if !hidden {
                    ForEach(RoomCompare.rows(then: earlier, now: current), id: \.name) { row in
                        Text(RoomCompare.readout(row, thenLabel: earlierDate.formatted(.dateTime.day().month()),
                            format: RoomFormat.bytes))
                    }
                }
            }
        }
    }
}
