import AppKit

let destination = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let outer = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 220, yRadius: 220)
NSGradient(colors: [NSColor(calibratedRed: 0.23, green: 0.32, blue: 0.43, alpha: 1),
    NSColor(calibratedRed: 0.075, green: 0.12, blue: 0.19, alpha: 1)])!.draw(in: outer, angle: -75)
NSColor.white.withAlphaComponent(0.18).setStroke()
outer.lineWidth = 2
outer.stroke()

// The mark sits directly on one glass surface, with no nested icon tile.

// Match RoomMark exactly, converting SwiftUI's top-down coordinates to AppKit.
let side: CGFloat = 720
let origin: CGFloat = (1024 - side) / 2
let radius = side * 0.14
let curve = radius * 0.5522847498
func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin + x * side, y: 1024 - origin - y * side) }
let mark = NSBezierPath()
mark.lineWidth = 26
mark.lineCapStyle = .round
mark.lineJoinStyle = .round
for index in 0..<3 {
    let inset = CGFloat(index) * 0.215
    let left = 0.10 + inset
    let top = 0.09 + inset
    mark.move(to: point(left, 0.91))
    mark.line(to: point(left, top + 0.14))
    mark.curve(to: point(left + 0.14, top),
        controlPoint1: NSPoint(x: origin + left * side, y: 1024 - origin - (top * side + radius - curve)),
        controlPoint2: NSPoint(x: origin + left * side + radius - curve, y: 1024 - origin - top * side))
    mark.line(to: point(0.90, top))
}
NSColor(calibratedWhite: 0.98, alpha: 0.96).setStroke()
mark.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
