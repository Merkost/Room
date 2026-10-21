import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic vector rendering of Resources/RoomIcon.svg. Coordinates use the
// same 1000-unit, top-down canvas as both editable SVGs and the native RoomMark.
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
context.scaleBy(x: CGFloat(pixels) / 1000, y: -CGFloat(pixels) / 1000)

// One flat slate surface reaches the canvas edges. Only its corners are clear.
context.setFillColor(color(22, 47, 58)) // #162F3A
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1000, height: 1000),
    cornerWidth: 224, cornerHeight: 224, transform: nil))
context.fillPath()

// The original room/frame idea, reduced to three equal-weight open corners.
// A 64-unit stroke on 112...888 coordinates occupies 84% of the tile bounds.
let mark = CGMutablePath()
for index in 0..<3 {
    let corner = CGFloat(112 + index * 224)
    mark.move(to: CGPoint(x: corner, y: 888))
    mark.addLine(to: CGPoint(x: corner, y: corner + 96))
    mark.addQuadCurve(to: CGPoint(x: corner + 96, y: corner), control: CGPoint(x: corner, y: corner))
    mark.addLine(to: CGPoint(x: 888, y: corner))
}
context.addPath(mark)
context.setStrokeColor(color(234, 241, 243)) // #EAF1F3
context.setLineWidth(64)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw NSError(domain: "RoomIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the PNG output."])
}
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else {
    throw NSError(domain: "RoomIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not save the PNG output."])
}
