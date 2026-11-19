import SwiftUI

struct RoomOverviewPlanGeometry {
    let layout: RoomDotPlan
    let wall: CGRect
    let goal: CGRect?
    let freeLabelArea: CGRect?
    let contextGrid: Path
    let rings: Path
    let dotCenters: [CGPoint]

    var free: CGRect? { frame(for: .free) }
    var notMapped: CGRect? { frame(for: .notMapped) }

    func frame(for id: RoomPlanRoom) -> CGRect? {
        layout.rooms.first(where: { $0.id == id })?.rect.offsetBy(dx: wall.minX, dy: wall.minY)
    }

    static func make(plan: RoomOverviewPlanInput, size: CGSize) -> Self? {
        typealias Tokens = RoomTokens.OverviewPlan
        let wall = CGRect(x: Tokens.pad, y: Tokens.pad, width: size.width - 2 * Tokens.pad,
                          height: size.height - 2 * Tokens.pad - Tokens.captionHeight)
        guard plan.fitsDotBudget, wall.width > 0, wall.height > 0 else { return nil }
        let layout = plan.layout(size: wall.size)
        let free = layout.rooms.first(where: { $0.id == .free })?.rect.offsetBy(dx: wall.minX, dy: wall.minY)
        let freeLabelArea = free.map {
            CGRect(x: $0.minX + Tokens.labelInset, y: $0.minY + Tokens.labelInset,
                   width: max(0, $0.width - 2 * Tokens.labelInset), height: Tokens.freeLabelHeight)
        }
        let goal = free.flatMap { free in
            plan.goalBytes.flatMap { goalBytes in
                let area = Double(goalBytes) / Double(plan.capacityBytes) * wall.width * wall.height
                let width = min(free.width - 2 * Tokens.goalInset, sqrt(area * 1.7))
                guard width > Tokens.minimumGoalWidth else { return nil as CGRect? }
                let height = area / width
                let rect = CGRect(x: free.minX + Tokens.goalInset, y: free.maxY - height - Tokens.goalInset,
                                  width: width, height: height)
                guard free.contains(rect), freeLabelArea?.intersects(rect) != true else { return nil }
                return rect
            }
        }
        let dotCenters = layout.dots.map {
            CGPoint(x: $0.center.x + wall.minX, y: $0.center.y + wall.minY)
        }
        let rings = Path { path in
            for (index, dot) in layout.dots.enumerated() where dot.room == .free {
                let center = dotCenters[index]
                let radius = layout.radius
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: 2 * radius, height: 2 * radius))
            }
        }
        let unmapped = layout.rooms.first(where: { $0.id == .notMapped })?.rect.offsetBy(dx: wall.minX, dy: wall.minY)
        let grid = Path { path in
            guard let unmapped else { return }
            let step = max(Tokens.gridPoint, layout.pitch * Tokens.gridPitchFactor)
            for y in stride(from: unmapped.minY + step / 2, to: unmapped.maxY, by: step) {
                for x in stride(from: unmapped.minX + step / 2, to: unmapped.maxX, by: step) {
                    path.addEllipse(in: CGRect(x: x, y: y, width: Tokens.gridPoint, height: Tokens.gridPoint))
                }
            }
        }
        return Self(layout: layout, wall: wall, goal: goal, freeLabelArea: freeLabelArea, contextGrid: grid, rings: rings, dotCenters: dotCenters)
    }
}

struct RoomDotPlanView: View {
    let plan: RoomOverviewPlanInput
    let belowGoal: Bool
    var hidden = false
    var displayHeight: CGFloat?
    var staticPreview = false
    var density = RoomTokens.Density.calm
    var solidKinds = false
    var showsUnmappedFigure = true
    let openDiskMap: () -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.roomMotion) private var motion
    @FocusState private var focused: Bool
    @State private var drawing: RoomOverviewPlanGeometry?
    @State private var selection: RoomPlanRoom?
    @State private var hover: RoomPlanRoom?
    @State private var pointer: CGPoint?
    @State private var field = RoomWakeField(dotCount: 0, enabled: false)
    @State private var lastFrame: Date?
    @State private var didPress = false

    private typealias Tokens = RoomTokens.OverviewPlan
    private var usesSolidKinds: Bool { solidKinds && !plan.kindValues.isEmpty }

    private struct Inputs: Equatable {
        let plan: RoomOverviewPlanInput
        let size: CGSize
    }

    var body: some View {
        let presentation = RoomOverviewPlanPresentation(plan: plan, hidden: hidden, solidKinds: usesSolidKinds, format: RoomFormat.overviewBytes)
        GeometryReader { proxy in
            let inputs = Inputs(plan: plan, size: proxy.size)
            ZStack(alignment: .bottomLeading) {
                TimelineView(.animation(paused: field.isAtRest)) { tick in
                    Canvas(renderer: paint(presentation).renderer)
                    .onChange(of: tick.date) { _, date in
                        advanceWake(to: date)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if !usesSolidKinds, pointer != point, let drawing, drawing.wall.contains(point) {
                            if !field.isAtRest || !drawing.layout.dots.isEmpty {
                                lastFrame = field.isAtRest ? Date.now : lastFrame
                                field.pointerMoved(to: point, dots: drawing.dotCenters)
                            }
                        }
                        pointer = point
                        hover = presentation.rows.first { drawing?.frame(for: $0.id)?.contains(point) == true }?.id
                    case .ended:
                        pointer = nil
                        hover = nil
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !usesSolidKinds, !didPress, let drawing, drawing.wall.contains(value.startLocation) else { return }
                        didPress = true
                        if field.isAtRest { lastFrame = Date.now }
                        field.press(at: value.startLocation)
                    }
                    .onEnded { _ in didPress = false })
                HStack {
                    Text(presentation.caption)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: RoomTokens.Space.row)
                    if let readout = presentation.rows.first(where: { $0.id == (hover ?? selection) }) {
                        Text(readout.readout).lineLimit(1)
                    }
                }
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .frame(height: Tokens.captionHeight)
                .padding(.horizontal, Tokens.pad)
            }
            .onChange(of: inputs, initial: true) { _, inputs in
                drawing = RoomOverviewPlanGeometry.make(plan: inputs.plan, size: inputs.size)
                resetWake()
            }
            .onChange(of: motion) { _, _ in resetWake() }
            .onChange(of: usesSolidKinds) { _, _ in resetWake() }
        }
        .frame(height: displayHeight ?? density.planSize.height)
        .focusable(!staticPreview)
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, focused in
            if !focused { selection = nil }
        }
        .onKeyPress(.leftArrow) {
            selection = presentation.nextFocus(from: selection, step: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            selection = presentation.nextFocus(from: selection, step: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        }
        .onKeyPress(.return) {
            openDiskMap()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityAction(.default, openDiskMap)
        .accessibilityChildren {
            Table(presentation.rows) {
                TableColumn(String(localized: "plan.column.room", defaultValue: "Room")) { row in
                    Text(row.name).accessibilityLabel(row.spoken)
                }
                TableColumn(String(localized: "plan.column.size", defaultValue: "Size"), value: \.size)
                if !hidden && !usesSolidKinds {
                    TableColumn(String(localized: "plan.column.dots", defaultValue: "Data dots"), value: \.dots)
                }
            }
        }
        .accessibilityIdentifier("RoomOverviewStoragePlan")
    }

    private func paint(_ presentation: RoomOverviewPlanPresentation) -> RoomOverviewPaint {
        var paint = RoomOverviewPaint()
        guard let geometry = drawing else { return paint }
        let outline = contrast == .increased ? RoomTokens.Surface.line2 : RoomTokens.Ink.secondary
        paint.stroke(Path(roundedRect: geometry.wall, cornerRadius: Tokens.outerRadius), outline, lineWidth: Tokens.wall)
        if let unmapped = geometry.notMapped?.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap),
           !unmapped.isEmpty {
            let room = Path(roundedRect: unmapped, cornerRadius: RoomTokens.Radius.planRoom)
            paint.fill(geometry.contextGrid, RoomTokens.Surface.line2, clip: room)
            paint.stroke(room, outline, style: Tokens.dashedWall)
        }
        if usesSolidKinds {
            drawSolidKinds(geometry, paint: &paint)
            drawFreeRings(geometry, paint: &paint)
        } else {
            drawDots(geometry, paint: &paint)
        }
        if belowGoal, let free = geometry.free?.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap), !free.isEmpty {
            paint.stroke(Path(roundedRect: free, cornerRadius: RoomTokens.Radius.planRoom),
                         RoomTokens.Status.elevated, lineWidth: Tokens.elevatedWall)
        }
        if let goal = geometry.goal {
            paint.stroke(Path(roundedRect: goal, cornerRadius: RoomTokens.Radius.planRoom), outline, style: Tokens.dashedWall)
            if let text = presentation.goalLabel, goal.width >= Tokens.goalLabelSize.width,
               goal.height >= Tokens.goalLabelSize.height {
                paint.label(text, in: goal.insetBy(dx: Tokens.goalInset, dy: 0), font: RoomTokens.Typography.micro,
                            ink: RoomTokens.Ink.secondary, centeredVertically: true)
            }
        }
        if focused || hover != nil {
            let frame = (hover ?? selection).flatMap { geometry.frame(for: $0) } ?? geometry.wall
            let ring = Path(roundedRect: frame.insetBy(dx: -Tokens.focusOffset, dy: -Tokens.focusOffset),
                            cornerRadius: RoomTokens.Radius.planRoom)
            paint.stroke(ring, accent.text, lineWidth: Tokens.focusWall)
        }
        drawRoomLabels(presentation, geometry: geometry, paint: &paint)
        return paint
    }

    private func resetWake() {
        field = RoomWakeField(dotCount: drawing?.dotCenters.count ?? 0, enabled: motion.isFull && !usesSolidKinds)
        lastFrame = nil
    }

    private func advanceWake(to date: Date) {
        guard let drawing, !field.isAtRest else { return }
        let dt = lastFrame.map { date.timeIntervalSince($0) * 1_000 } ?? 16
        field.step(dtMS: dt, dots: drawing.dotCenters)
        lastFrame = field.isAtRest ? nil : date
    }

    private func drawSolidKinds(_ geometry: RoomOverviewPlanGeometry, paint: inout RoomOverviewPaint) {
        let focus = hover ?? selection
        for room in geometry.layout.rooms {
            guard case let .kind(key) = room.id, let kind = RoomTokens.Kind(rawValue: key),
                  let bounds = geometry.frame(for: room.id)?.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap),
                  !bounds.isEmpty else { continue }
            let opacity = focus.map { $0 != room.id ? Tokens.dimmedKind : 1 } ?? 1
            paint.fill(Path(roundedRect: bounds, cornerRadius: RoomTokens.Radius.planRoom), kind.fill.opacity(opacity))
        }
    }

    private var freeInk: Color {
        RoomTokens.Ink.secondary.opacity(contrast == .increased ? 1 : RoomTokens.Dots.freeRingOpacity)
    }

    private func drawFreeRings(_ geometry: RoomOverviewPlanGeometry, paint: inout RoomOverviewPaint) {
        paint.stroke(geometry.rings, freeInk, lineWidth: RoomTokens.Dots.freeRingStroke)
    }

    private func drawDots(_ geometry: RoomOverviewPlanGeometry, paint: inout RoomOverviewPaint) {
        if field.isAtRest { drawFreeRings(geometry, paint: &paint) }
        var paths: [RoomPlanRoom: Path] = [:]
        for (index, dot) in geometry.layout.dots.enumerated() where dot.room != .free || !field.isAtRest {
            let center = geometry.dotCenters[index]
            let rest = geometry.layout.radius
            let radius = index < field.energy.count ? field.radius(index, rest: rest) : rest
            paths[dot.room, default: Path()].addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        for (room, path) in paths {
            switch room {
            case .free:
                paint.stroke(path, freeInk, lineWidth: RoomTokens.Dots.freeRingStroke)
            case .kind(let key):
                if let kind = RoomTokens.Kind(rawValue: key) {
                    let focusedKind = hover ?? selection
                    let dims = focusedKind.map { $0 != room } ?? false
                    paint.fill(path, kind.mark.opacity(dims ? Tokens.dimmedKind : 1))
                }
            case .notMapped: break
            }
        }
        for ring in field.rings {
            guard let style = RoomWakeField.drawnRing(ageMS: ring.ageMS) else { continue }
            let rect = CGRect(x: ring.center.x - style.radius, y: ring.center.y - style.radius,
                              width: 2 * style.radius, height: 2 * style.radius)
            paint.stroke(Path(ellipseIn: rect), accent.fill.opacity(style.opacity), lineWidth: Tokens.wall)
        }
    }

    private func drawRoomLabels(_ presentation: RoomOverviewPlanPresentation, geometry: RoomOverviewPlanGeometry,
                                paint: inout RoomOverviewPaint) {
        if let free = geometry.freeLabelArea, let row = presentation.rows.first(where: { $0.id == .free }),
           (geometry.free?.height ?? 0) >= free.height + Tokens.labelInset {
            paint.label(row.name, in: free, font: Tokens.freeLabel, ink: RoomTokens.Ink.graphite)
            let size = free.offsetBy(dx: 0, dy: Tokens.labelLineHeight)
            paint.label(row.visualSize, in: size, font: RoomTokens.Typography.caption, ink: RoomTokens.Ink.secondary)
        }
        let kindRows = presentation.rows.filter { if case .kind = $0.id { true } else { false } }
        let labelCount = usesSolidKinds ? kindRows.count : RoomTokens.Dots.quietLabels
        for row in kindRows.prefix(labelCount) {
            guard let room = geometry.frame(for: row.id) else { continue }
            let bounds = room.insetBy(dx: Tokens.labelInset, dy: Tokens.labelInset)
            let defaultOpacity: Double = usesSolidKinds ? 1 : Tokens.quietLabelOpacity
            let lampOpacity = (motion.isFull ? pointer : nil).map { point in
                Double(RoomPure.lampOpacity(distance: hypot(point.x - bounds.midX, point.y - bounds.midY)))
            }
            let opacity = lampOpacity ?? defaultOpacity
            let ink = usesSolidKinds ? RoomTokens.Kind.tileInk : RoomTokens.Ink.graphite
            paint.label(row.name, in: bounds, font: RoomTokens.Typography.micro, ink: ink.opacity(opacity))
        }
        if let room = geometry.notMapped, let row = presentation.rows.first(where: { $0.id == .notMapped }) {
            let bounds = room.insetBy(dx: Tokens.labelInset, dy: Tokens.labelInset)
            let label = showsUnmappedFigure ? "\(row.name) · \(row.visualSize)" : row.name
            paint.label(label, in: bounds, font: RoomTokens.Typography.micro, ink: RoomTokens.Ink.graphite)
        }
    }
}

/// Canvas can render off the main actor. The renderer captures a frame of values,
/// leaving hover, selection and wake state on the view's actor.
private nonisolated struct RoomOverviewPaint {
    private enum Mark {
        case stroke(Path, Color, StrokeStyle)
        case fill(Path, Color, clip: Path?)
        case label(Text, CGRect, centeredVertically: Bool)
    }

    private var marks: [Mark] = []

    mutating func stroke(_ path: Path, _ ink: Color, lineWidth: CGFloat) {
        stroke(path, ink, style: StrokeStyle(lineWidth: lineWidth))
    }

    mutating func stroke(_ path: Path, _ ink: Color, style: StrokeStyle) {
        marks.append(.stroke(path, ink, style))
    }

    mutating func fill(_ path: Path, _ ink: Color, clip: Path? = nil) {
        marks.append(.fill(path, ink, clip: clip))
    }

    mutating func label(_ text: String, in bounds: CGRect, font: Font, ink: Color, centeredVertically: Bool = false) {
        marks.append(.label(Text(text).font(font).foregroundStyle(ink), bounds, centeredVertically: centeredVertically))
    }

    var renderer: (inout GraphicsContext, CGSize) -> Void {
        { context, _ in
            for mark in marks {
                switch mark {
                case let .stroke(path, ink, style):
                    context.stroke(path, with: .color(ink), style: style)
                case let .fill(path, ink, clip):
                    if let clip {
                        var clipped = context
                        clipped.clip(to: clip)
                        clipped.fill(path, with: .color(ink))
                    } else {
                        context.fill(path, with: .color(ink))
                    }
                case let .label(text, bounds, centeredVertically):
                    let label = context.resolve(text)
                    let size = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                    guard size.width <= bounds.width, size.height <= bounds.height else { continue }
                    let point = CGPoint(x: bounds.minX, y: centeredVertically ? bounds.midY : bounds.minY)
                    context.draw(label, at: point, anchor: centeredVertically ? .leading : .topLeading)
                }
            }
        }
    }
}
