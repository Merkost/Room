import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic vector rendering of Resources/RoomIcon.svg. Coordinates use the
// same 64-unit, top-down canvas as both editable SVGs and the native RoomMark.
guard CommandLine.arguments.count == 2 else {
    throw NSError(domain: "RoomIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: swift MakeIcon.swift /absolute/path/Room-1024.png"])
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let pixels = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    throw NSError(domain: "RoomIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the icon canvas."])
}
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [red / 255, green / 255, blue / 255, 1])!
}
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.translateBy(x: 0, y: CGFloat(pixels))
context.scaleBy(x: CGFloat(pixels) / 64, y: -CGFloat(pixels) / 64)

// Graphite tile and white mark match the approved C4 comparison.
context.setFillColor(color(34, 37, 39)) // #222527
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64),
    cornerWidth: 15.5, cornerHeight: 15.5, transform: nil))
context.fillPath()

let mark = CGMutablePath()
mark.move(to: CGPoint(x: 23, y: 12))
mark.addLine(to: CGPoint(x: 41, y: 12))
mark.addCurve(to: CGPoint(x: 52, y: 23), control1: CGPoint(x: 48.18, y: 12), control2: CGPoint(x: 52, y: 15.82))
mark.addLine(to: CGPoint(x: 52, y: 41))
mark.addCurve(to: CGPoint(x: 41, y: 52), control1: CGPoint(x: 52, y: 48.18), control2: CGPoint(x: 48.18, y: 52))
mark.addLine(to: CGPoint(x: 23, y: 52))
mark.addCurve(to: CGPoint(x: 12, y: 41), control1: CGPoint(x: 15.82, y: 52), control2: CGPoint(x: 12, y: 48.18))
mark.addLine(to: CGPoint(x: 12, y: 23))
mark.addCurve(to: CGPoint(x: 23, y: 12), control1: CGPoint(x: 12, y: 15.82), control2: CGPoint(x: 15.82, y: 12))
mark.closeSubpath()
mark.move(to: CGPoint(x: 24, y: 19))
mark.addLine(to: CGPoint(x: 40, y: 19))
mark.addCurve(to: CGPoint(x: 45, y: 24), control1: CGPoint(x: 43.314, y: 19), control2: CGPoint(x: 45, y: 20.686))
mark.addLine(to: CGPoint(x: 45, y: 29))
mark.addCurve(to: CGPoint(x: 41, y: 33), control1: CGPoint(x: 45, y: 31.209), control2: CGPoint(x: 43.209, y: 33))
mark.addLine(to: CGPoint(x: 39, y: 33))
mark.addCurve(to: CGPoint(x: 33, y: 39), control1: CGPoint(x: 35.686, y: 33), control2: CGPoint(x: 33, y: 35.686))
mark.addLine(to: CGPoint(x: 33, y: 41))
mark.addCurve(to: CGPoint(x: 29, y: 45), control1: CGPoint(x: 33, y: 43.209), control2: CGPoint(x: 31.209, y: 45))
mark.addLine(to: CGPoint(x: 24, y: 45))
mark.addCurve(to: CGPoint(x: 19, y: 40), control1: CGPoint(x: 20.686, y: 45), control2: CGPoint(x: 19, y: 43.314))
mark.addLine(to: CGPoint(x: 19, y: 24))
mark.addCurve(to: CGPoint(x: 24, y: 19), control1: CGPoint(x: 19, y: 20.686), control2: CGPoint(x: 20.686, y: 19))
mark.closeSubpath()
context.addPath(mark)
context.setFillColor(color(255, 255, 255))
context.drawPath(using: .eoFill)

guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw NSError(domain: "RoomIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the PNG output."])
}
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else {
    throw NSError(domain: "RoomIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not save the PNG output."])
}
