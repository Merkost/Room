// The C4 mark as a template NSImage with a pocket fill (hollow 0, half 0.5, full 1).
// Spec: 02 §11, 10-MENU-BAR-AND-POPOVER.md §3. Geometry is RoomMark.svg, unchanged; nothing rotates.
import AppKit

nonisolated enum RoomPocketMark {
    /// Outer soft square and the pocket (inner shape), in the SVG's 64-unit space.
    static func outerPath(in r: CGRect) -> CGPath {
        let p = CGMutablePath(); let f = transform(r)
        p.move(to: f(23, 12)); p.addLine(to: f(41, 12))
        p.addCurve(to: f(52, 23), control1: f(48.18, 12), control2: f(52, 15.82))
        p.addLine(to: f(52, 41))
        p.addCurve(to: f(41, 52), control1: f(52, 48.18), control2: f(48.18, 52))
        p.addLine(to: f(23, 52))
        p.addCurve(to: f(12, 41), control1: f(15.82, 52), control2: f(12, 48.18))
        p.addLine(to: f(12, 23))
        p.addCurve(to: f(23, 12), control1: f(12, 15.82), control2: f(15.82, 12))
        p.closeSubpath(); return p
    }

    static func pocketPath(in r: CGRect) -> CGPath {
        let p = CGMutablePath(); let f = transform(r)
        p.move(to: f(24, 19)); p.addLine(to: f(40, 19))
        p.addCurve(to: f(45, 24), control1: f(43.314, 19), control2: f(45, 20.686))
        p.addLine(to: f(45, 29))
        p.addCurve(to: f(41, 33), control1: f(45, 31.209), control2: f(43.209, 33))
        p.addLine(to: f(39, 33))
        p.addCurve(to: f(33, 39), control1: f(35.686, 33), control2: f(33, 35.686))
        p.addLine(to: f(33, 41))
        p.addCurve(to: f(29, 45), control1: f(33, 43.209), control2: f(31.209, 45))
        p.addLine(to: f(24, 45))
        p.addCurve(to: f(19, 40), control1: f(20.686, 45), control2: f(19, 43.314))
        p.addLine(to: f(19, 24))
        p.addCurve(to: f(24, 19), control1: f(19, 20.686), control2: f(20.686, 19))
        p.closeSubpath(); return p
    }

    /// Board viewBox is "8 8 48 48": the 64-unit mark is cropped to its 48-unit body so 16 pt = 48 units.
    private static func transform(_ r: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let s = min(r.width, r.height) / 48
        // AppKit's y axis points up: flip so the SVG's y=12 is the top edge.
        return { x, y in CGPoint(x: r.minX + (x - 8) * s, y: r.maxY - (y - 8) * s) }
    }

    /// fill: 0 hollow, 0.5 half (elevated or below goal), 1 full (critical). Template: AppKit tints it.
    static func image(fill: Double, pointSize: CGFloat = 16) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(outerPath(in: rect)); ctx.fillPath()      // the solid soft square
            // Erase the part of the pocket that is not filled yet, from the top down to the fill line. Erasing leaves every
            // edge anti-aliased once; filling a clipped rectangle over a hollow mark double-counts the pocket's edge pixels
            // and leaves a faint seam in a full pocket (measured: 16 partly transparent pixels in the centre of a 32 px full mark, 0 now).
            let f = min(1, max(0, fill))
            if f < 1 {
                ctx.saveGState()
                let s = min(rect.width, rect.height) / 48
                let pocketTop = rect.maxY - (19 - 8) * s, pocketBottom = rect.maxY - (45 - 8) * s
                let line = pocketBottom + (pocketTop - pocketBottom) * CGFloat(f)     // top of the filled part; fills from the bottom
                ctx.clip(to: CGRect(x: rect.minX, y: line, width: rect.width, height: rect.maxY - line))
                ctx.setBlendMode(.clear)
                ctx.addPath(pocketPath(in: rect)); ctx.fillPath()
                ctx.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Room"
        return image
    }
}
