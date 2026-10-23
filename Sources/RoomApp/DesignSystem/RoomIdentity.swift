import SwiftUI

struct RoomMark: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + side * x / 64, y: origin.y + side * y / 64)
        }
        // Exact C4 soft-pocket geometry from RoomMark.svg; fill using even-odd.
        var path = Path()
        path.move(to: point(23, 12))
        path.addLine(to: point(41, 12))
        path.addCurve(to: point(52, 23), control1: point(48.18, 12), control2: point(52, 15.82))
        path.addLine(to: point(52, 41))
        path.addCurve(to: point(41, 52), control1: point(52, 48.18), control2: point(48.18, 52))
        path.addLine(to: point(23, 52))
        path.addCurve(to: point(12, 41), control1: point(15.82, 52), control2: point(12, 48.18))
        path.addLine(to: point(12, 23))
        path.addCurve(to: point(23, 12), control1: point(12, 15.82), control2: point(15.82, 12))
        path.closeSubpath()
        path.move(to: point(24, 19))
        path.addLine(to: point(40, 19))
        path.addCurve(to: point(45, 24), control1: point(43.314, 19), control2: point(45, 20.686))
        path.addLine(to: point(45, 29))
        path.addCurve(to: point(41, 33), control1: point(45, 31.209), control2: point(43.209, 33))
        path.addLine(to: point(39, 33))
        path.addCurve(to: point(33, 39), control1: point(35.686, 33), control2: point(33, 35.686))
        path.addLine(to: point(33, 41))
        path.addCurve(to: point(29, 45), control1: point(33, 43.209), control2: point(31.209, 45))
        path.addLine(to: point(24, 45))
        path.addCurve(to: point(19, 40), control1: point(20.686, 45), control2: point(19, 43.314))
        path.addLine(to: point(19, 24))
        path.addCurve(to: point(24, 19), control1: point(19, 20.686), control2: point(20.686, 19))
        path.closeSubpath()
        return path
    }
}

struct RoomAmbientBackground: View {
    var body: some View {
        RoomSurface.canvas.ignoresSafeArea()
    }
}
