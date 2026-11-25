import SwiftUI

/// Overview's floor plan (nav-v3): one room per kind, sized by GB, with the kind's glyph and data colour; Free as
/// rings. Pure, so the numbers and order are tested.
nonisolated struct RoomOverviewFloorPlan: Equatable, Sendable {
    struct Room: Equatable, Sendable, Identifiable {
        enum Fill: Equatable, Sendable { case kind(String), notMapped, free }
        let fill: Fill
        let title: String
        let bytes: Int64
        var id: String {
            switch fill { case .kind(let raw): raw; case .notMapped: "not-mapped"; case .free: "free" }
        }
        var isFree: Bool { fill == .free }
    }

    let rooms: [Room]
    let capacityBytes: Int64

    static let maxKinds = 5

    /// `kinds` are StorageKind raw values with decimal GB (RoomHomeKinds). Without a home map the used space is one
    /// quiet "Used" room: Room never guesses what is inside.
    static func make(kinds: [(String, Double)]?, notMappedBytes: Int64, freeBytes: Int64, capacityBytes: Int64) -> RoomOverviewFloorPlan {
        var rooms: [Room] = []
        if let kinds, !kinds.isEmpty {
            let sorted = kinds.map { (raw: $0.0, bytes: Int64($0.1 * 1e9)) }.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            for kind in sorted.prefix(maxKinds) {
                rooms.append(Room(fill: .kind(kind.raw), title: title(kind.raw), bytes: kind.bytes))
            }
            let rest = sorted.dropFirst(maxKinds).reduce(Int64(0)) { $0 + $1.bytes }
            if rest > 0 { rooms.append(Room(fill: .kind("system"), title: "Other", bytes: rest)) }
            if capacityBytes > 0, Double(notMappedBytes) / Double(capacityBytes) >= 0.05 {
                rooms.append(Room(fill: .notMapped, title: "Not mapped", bytes: notMappedBytes))
            }
        } else if capacityBytes > freeBytes {
            rooms.append(Room(fill: .notMapped, title: "Used", bytes: capacityBytes - freeBytes))
        }
        rooms.append(Room(fill: .free, title: "Free", bytes: max(0, freeBytes)))
        return RoomOverviewFloorPlan(rooms: rooms, capacityBytes: capacityBytes)
    }

    static func title(_ raw: String) -> String {
        switch raw {
        case "developer": "Developer"
        case "media": "Media"
        case "documents": "Documents"
        case "apps": "Apps"
        case "archives": "Archives"
        case "system": "System"
        case "hidden": "Hidden"
        default: raw.capitalized
        }
    }

    static func glyph(_ raw: String) -> RoomGlyph {
        switch raw {
        case "developer": .term
        case "media": .film
        case "documents": .doc
        case "apps": .grid
        case "archives": .box
        case "hidden": .eye
        default: .settings
        }
    }

    /// Widths for a row of rooms: proportional to bytes, Free boosted so it reads, nobody under `minimum`.
    static func widths(_ rooms: [Room], total width: CGFloat, gap: CGFloat, minimum: CGFloat, freeBoostGB: Double) -> [CGFloat] {
        guard !rooms.isEmpty else { return [] }
        let usable = max(0, width - gap * CGFloat(rooms.count - 1))
        let weights = rooms.map { max(0.5, Double($0.bytes) / 1e9 + ($0.isFree ? freeBoostGB : 0)) }
        var widths = Array(repeating: minimum, count: rooms.count)
        var flexible = Set(rooms.indices)
        var remaining = usable
        // Give each room its share; rooms that fall under the minimum keep the minimum and leave the pool.
        while !flexible.isEmpty {
            let pool = flexible.reduce(0) { $0 + weights[$1] }
            var changed = false
            for index in flexible {
                let share = remaining * CGFloat(weights[index] / pool)
                if share < minimum {
                    widths[index] = minimum
                    remaining -= minimum
                    flexible.remove(index)
                    changed = true
                }
            }
            if !changed {
                for index in flexible { widths[index] = remaining * CGFloat(weights[index] / pool) }
                break
            }
        }
        return widths
    }

    func percent(of room: Room) -> Int {
        capacityBytes > 0 ? Int((Double(room.bytes) / Double(capacityBytes) * 100).rounded()) : 0
    }
}

/// The plan drawn: kind rooms with dots in their data colour, Free as rings. No motion at rest; a change in size
/// eases on the slow room spring.
struct RoomOverviewFloorPlanView: View {
    let plan: RoomOverviewFloorPlan
    var hover: (RoomOverviewFloorPlan.Room?) -> Void = { _ in }

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geometry in
            let widths = RoomOverviewFloorPlan.widths(plan.rooms, total: geometry.size.width, gap: RoomTokens.Screen2.planGap,
                                                      minimum: RoomTokens.Screen2.planMinFreeWidth,
                                                      freeBoostGB: RoomTokens.Screen2.planFreeBoost)
            HStack(spacing: RoomTokens.Screen2.planGap) {
                ForEach(Array(plan.rooms.enumerated()), id: \.element.id) { index, room in
                    roomView(room)
                        .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                        .opacity(hovered == nil || hovered == room.id ? 1 : 0.45)
                        .onHover { inside in
                            hovered = inside ? room.id : (hovered == room.id ? nil : hovered)
                            hover(inside ? room : nil)
                        }
                }
            }
            .animation(motion.animation(RoomTokens.Motion.room, fallback: nil), value: widths)
            .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: hovered)
        }
        .frame(height: RoomTokens.Screen2.planHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floor plan of this Mac")
    }

    private func roomView(_ room: RoomOverviewFloorPlan.Room) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Screen2.planRadius)
        return ZStack(alignment: .topLeading) {
            if room.isFree {
                shape.strokeBorder(RoomTokens.Surface.line, lineWidth: 1)
            } else {
                shape.fill(RoomTokens.Surface.tile)
            }
            RoomPlanDots(color: dotColor(room), rings: room.isFree, ringOpacity: RoomContrast.ringOpacity(contrast))
                .padding(.top, RoomTokens.Screen2.planDotsTop)
                .padding([.horizontal, .bottom], RoomTokens.Screen2.planPad)
                .opacity(room.fill == .notMapped ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if case .kind(let raw) = room.fill {
                        RoomGlyphView(glyph: RoomOverviewFloorPlan.glyph(raw), size: 14, weight: 1.5)
                            .foregroundStyle(kindColor(raw))
                    }
                    Text(room.title)
                        .font(RoomTokens.Typography.bodyStrong)
                        .foregroundStyle(room.isFree ? accent.text : RoomTokens.Ink.graphite)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                RoomMaskable(RoomFormat.gb(room.bytes))
                    .font(RoomTokens.Typography.captionNumeric)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
            }
            .padding(RoomTokens.Screen2.planPad)
        }
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(room.title)
        .accessibilityValue(RoomFormat.gb(room.bytes))
    }

    private func kindColor(_ raw: String) -> Color {
        (RoomTokens.Kind(rawValue: raw) ?? .system).mark
    }

    private func dotColor(_ room: RoomOverviewFloorPlan.Room) -> Color {
        switch room.fill {
        case .kind(let raw): kindColor(raw)
        case .notMapped: RoomTokens.Ink.tertiary
        case .free: RoomTokens.Ink.tertiary
        }
    }
}

/// A lattice of dots (or rings for Free), drawn once per size change; no animation at rest.
struct RoomPlanDots: View {
    let color: Color
    var rings = false
    var ringOpacity: Double = 1

    var body: some View {
        Canvas { context, size in
            let pitch = RoomTokens.Screen2.planPitch, d = RoomTokens.Screen2.planDot
            let columns = max(1, Int((size.width + pitch - d) / pitch))
            let rows = max(1, Int((size.height + pitch - d) / pitch))
            let spareX = (size.width - (CGFloat(columns - 1) * pitch + d)) / 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(x: spareX + CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: d, height: d)
                    if rings {
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(color.opacity(ringOpacity)),
                                       lineWidth: RoomTokens.Dots.freeRingStroke)
                    } else {
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
