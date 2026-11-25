import SwiftUI

/// Room's drawn glyphs: 18 x 18 line drawings from the nav-v3 mockup (`room-site/design/nav-v3/index.html`), stroked
/// with round caps. Places, kinds and quiet setting tiles use these; rows that name a real thing use the system icon.
nonisolated enum RoomGlyph: String, CaseIterable, Sendable {
    // Places (sidebar, rail, Go to)
    case overview, diskMap, caches, developer, memory, history, settings
    // Kinds and quiet tiles
    case term, grid, film, doc, box, photo, down, folder, window, target, eye, bar, cal, wave, search, layers, phone, branch, spark

    fileprivate var parts: [RoomGlyphPart] {
        switch self {
        case .overview: [.rect(2.5, 3.5, 13, 11, 2), .path("M9 3.5v5.5M2.5 9h6.5M9 11.5v3")]
        case .diskMap: [.rect(2.5, 3.5, 13, 11, 2), .path("M2.5 8.5h7M9.5 3.5v11M9.5 11h6")]
        case .caches: [.rect(3.5, 2.5, 11, 13, 2), .path("M3.5 7h11M3.5 11h11")]
        case .developer: [.path("M2.5 7.5h13M4.5 7.5v7M13.5 7.5v7M4.5 11h9M6.5 4h5v3.5")]
        case .memory: [.rect(2.5, 3.5, 13, 11, 2), .path("M5 10.5l2.2-3 2.3 4 2-2.5h1.5")]
        case .history: [.path("M4 2.5h10v13l-1.7-1.2-1.6 1.2L9 14.3l-1.7 1.2-1.6-1.2L4 15.5z"),
                        .path("M6.8 6.5h4.4M6.8 9.5h4.4")]
        case .settings: [.path("M2.5 6h3M9.5 6h6M2.5 12h6M12.5 12h3"), .circle(7.5, 6, 2), .circle(10.5, 12, 2)]
        case .term: [.rect(2.5, 4, 13, 10, 2), .path("M5.5 7.5l2 1.5-2 1.5M9.5 10.5h3")]
        case .grid: [.path("M3.5 3.5H8V8H3.5zM10 3.5h4.5V8H10zM3.5 10H8v4.5H3.5zM10 10h4.5v4.5H10z")]
        case .film: [.rect(3, 4, 12, 10, 1.5), .path("M6 4v10M12 4v10")]
        case .doc: [.path("M5 2.5h5.5l3 3v10H5z"), .path("M10.5 2.5v3h3")]
        case .box: [.path("M3.5 6.5L9 3.5l5.5 3v5.5L9 15l-5.5-3z"), .path("M3.5 6.5L9 9.5l5.5-3M9 9.5V15")]
        case .photo: [.rect(2.5, 4, 13, 10, 2), .circle(6.5, 7.8, 1.2), .path("M3 13l3.5-3 3 2.5 2.5-2 3 2.5")]
        case .down: [.path("M9 3.5v8M5.5 8.5L9 12l3.5-3.5M4 14.5h10")]
        case .folder: [.path("M2.5 5.5q0-1 1-1h3L8 6h6.5q1 0 1 1v6q0 1-1 1h-11q-1 0-1-1z")]
        case .window: [.rect(2.5, 3.5, 13, 11, 2), .path("M2.5 7h13")]
        case .target: [.circle(9, 9, 5.5), .circle(9, 9, 2)]
        case .eye: [.path("M2.5 9q2.5-4.5 6.5-4.5T15.5 9q-2.5 4.5-6.5 4.5T2.5 9z"), .circle(9, 9, 1.8)]
        case .bar: [.rect(2.5, 5, 13, 8, 2), .path("M11 9h2")]
        case .cal: [.rect(3, 4, 12, 11, 2), .path("M3 7.5h12M6.5 2.5v3M11.5 2.5v3")]
        case .wave: [.path("M2.5 9q2-4 3.5-2t1.5 2q1.5 4 3 2t2-2q1-1.5 3-1")]
        case .search: [.circle(7.5, 7.5, 4.5), .path("M11 11l4 4")]
        case .layers: [.path("M9 3.5l6 3-6 3-6-3z"), .path("M3 9.5l6 3 6-3M3 12.5l6 3 6-3")]
        case .phone: [.rect(5.5, 2.5, 7, 13, 1.8), .path("M8 13h2")]
        case .branch: [.circle(5.5, 4.5, 1.5), .circle(5.5, 13.5, 1.5), .circle(12.5, 6.5, 1.5),
                       .path("M5.5 6v6M12.5 8q0 3-7 4")]
        case .spark: [.path("M9 3v3M9 12v3M3 9h3M12 9h3M5 5l2 2M11 11l2 2M13 5l-2 2M7 11l-2 2")]
        }
    }

    /// The path in the glyph's own 18 x 18 box.
    var path: Path {
        var path = Path()
        for part in parts { part.add(to: &path) }
        return path
    }

    static let viewBox: CGFloat = 18
}

private nonisolated enum RoomGlyphPart: Sendable {
    case path(String)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case circle(CGFloat, CGFloat, CGFloat)

    func add(to path: inout Path) {
        switch self {
        case .path(let d): RoomGlyphPathParser.add(d, to: &path)
        case .rect(let x, let y, let w, let h, let r):
            path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
        case .circle(let x, let y, let r):
            path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }
}

/// The small subset of SVG path data the glyphs use: M L H V Q T Z, absolute and relative, with implicit repeats.
nonisolated enum RoomGlyphPathParser {
    static func add(_ data: String, to path: inout Path) {
        var scanner = Tokens(data)
        var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
        var command: Character = "M"
        while let next = scanner.next() {
            if case .command(let c) = next { command = c } else { scanner.pushBack(next) }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased().first! {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                current = CGPoint(x: base.x + x, y: base.y + y); start = current
                path.move(to: current)
                command = relative ? "l" : "L"   // implicit lineto after a moveto pair
                lastControl = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                current = CGPoint(x: base.x + x, y: base.y + y); path.addLine(to: current); lastControl = nil
            case "H":
                guard let x = scanner.number() else { return }
                current.x = (relative ? current.x : 0) + x; path.addLine(to: current); lastControl = nil
            case "V":
                guard let y = scanner.number() else { return }
                current.y = (relative ? current.y : 0) + y; path.addLine(to: current); lastControl = nil
            case "Q":
                guard let cx = scanner.number(), let cy = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return }
                let control = CGPoint(x: base.x + cx, y: base.y + cy)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: control); lastControl = control
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return }
                let control = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: control); lastControl = control
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
            default:
                return
            }
        }
    }

    enum Token: Equatable { case command(Character), number(CGFloat) }

    struct Tokens {
        private let chars: [Character]
        private var index = 0
        private var pushed: Token?

        init(_ text: String) { chars = Array(text) }

        mutating func pushBack(_ token: Token) { pushed = token }

        mutating func number() -> CGFloat? {
            guard let token = next() else { return nil }
            if case .number(let value) = token { return value }
            pushBack(token)
            return nil
        }

        mutating func next() -> Token? {
            if let pushed { self.pushed = nil; return pushed }
            while index < chars.count, chars[index] == " " || chars[index] == "," { index += 1 }
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter { index += 1; return .command(c) }
            var text = String(c); index += 1
            var seenDot = c == "."
            while index < chars.count {
                let d = chars[index]
                if d.isNumber { text.append(d) }
                else if d == "." && !seenDot { seenDot = true; text.append(d) }
                else { break }
                index += 1
            }
            return Double(text).map { .number(CGFloat($0)) }
        }
    }
}

/// A glyph scaled into its frame. The stroke stays the mockup's weight at 18 pt and scales with the frame.
nonisolated struct RoomGlyphShape: Shape {
    let glyph: RoomGlyph
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / RoomGlyph.viewBox
        return glyph.path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

struct RoomGlyphView: View {
    let glyph: RoomGlyph
    var size: CGFloat = RoomTokens.Nav.glyph
    var weight: CGFloat = RoomTokens.Nav.glyphStroke

    var body: some View {
        RoomGlyphShape(glyph: glyph)
            .stroke(style: StrokeStyle(lineWidth: weight * size / RoomGlyph.viewBox, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
