import SwiftUI

struct RoomBudgetFrameView: View {
    let layout: RoomBudgetFrame
    let color: Color

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: RoomBudgetFrame.originX, y: RoomBudgetFrame.originY,
                             width: RoomBudgetFrame.frameWidth, height: size.height - 8)
            context.fill(Path(roundedRect: layout.fill, cornerRadius: 2), with: .color(color))
            if let overrun = layout.overrun {
                context.fill(Path(roundedRect: overrun, cornerRadius: 1), with: .color(RoomTokens.Status.elevated))
            }
            var outline = Path()
            outline.move(to: CGPoint(x: box.maxX, y: box.minY))
            outline.addLine(to: CGPoint(x: box.minX, y: box.minY))
            outline.addLine(to: CGPoint(x: box.minX, y: box.maxY))
            outline.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            if !layout.frameOpenAtRight { outline.closeSubpath() }
            context.stroke(outline, with: .color(RoomTokens.Ink.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }.accessibilityHidden(true)
    }
}
