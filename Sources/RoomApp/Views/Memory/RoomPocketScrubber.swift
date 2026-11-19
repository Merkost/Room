import SwiftUI

struct RoomPocketScrubber: View, Animatable {
    let level: RoomPressureLevel?
    let size: CGFloat
    var fill: Double

    init(level: RoomPressureLevel?, size: CGFloat) {
        self.level = level
        self.size = size
        self.fill = level?.pocketFill ?? 0
    }

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    var body: some View {
        Image(nsImage: RoomPocketMark.image(fill: fill, pointSize: size))
            .renderingMode(.template).foregroundStyle(Self.color(level))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func color(_ level: RoomPressureLevel?) -> Color {
        switch level {
        case .normal: RoomTokens.Status.normal
        case .elevated: RoomTokens.Status.elevated
        case .critical: RoomTokens.Status.critical
        case nil: RoomTokens.Ink.secondary
        }
    }
}
