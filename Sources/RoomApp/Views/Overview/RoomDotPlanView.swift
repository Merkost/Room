import SwiftUI

struct RoomOverviewPlanGeometry {
    let layout: RoomDotPlan
    let wall: CGRect
    let goal: CGRect?
    let freeLabelArea: CGRect?
    let contextGrid: Path
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
        return Self(layout: layout, wall: wall, goal: goal, freeLabelArea: freeLabelArea, contextGrid: grid, dotCenters: dotCenters)
    }
}

struct RoomDotPlanView: View {
    let plan: RoomOverviewPlanInput
    let belowGoal: Bool
    var hidden = false
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

    private struct Inputs: Equatable {
        let plan: RoomOverviewPlanInput
        let size: CGSize
    }

    var body: some View {
        let presentation = RoomOverviewPlanPresentation(plan: plan, hidden: hidden, format: RoomFormat.overviewBytes)
        GeometryReader { proxy in
            let inputs = Inputs(plan: plan, size: proxy.size)
            ZStack(alignment: .bottomLeading) {
                TimelineView(.animation(paused: field.isAtRest)) { tick in
                    Canvas { context, _ in
                        if let drawing { draw(drawing, presentation: presentation, in: context) }
                    }
                    .onChange(of: tick.date) { _, date in
                        advanceWake(to: date)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if pointer != point, let drawing, drawing.wall.contains(point) {
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
                        guard !didPress, let drawing, drawing.wall.contains(value.startLocation) else { return }
                        didPress = true
                        if field.isAtRest { lastFrame = Date.now }
                        field.press(at: value.startLocation)
                    }
                    .onEnded { _ in didPress = false })
                HStack {
                    Text(presentation.caption)
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
        }
        .frame(width: nil, height: RoomTokens.Density.calm.planSize.height)
        .focusable()
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
                if !hidden {
                    TableColumn(String(localized: "plan.column.dots", defaultValue: "Data dots"), value: \.dots)
                }
            }
        }
        .accessibilityIdentifier("RoomOverviewStoragePlan")
    }

    private func draw(_ geometry: RoomOverviewPlanGeometry, presentation: RoomOverviewPlanPresentation,
                      in context: GraphicsContext) {
        let outline = contrast == .increased ? RoomTokens.Surface.line2 : RoomTokens.Ink.secondary
        context.stroke(Path(roundedRect: geometry.wall, cornerRadius: Tokens.outerRadius),
                       with: .color(outline), lineWidth: Tokens.wall)
        if let unmapped = geometry.notMapped?.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap),
           !unmapped.isEmpty {
            let room = Path(roundedRect: unmapped, cornerRadius: RoomTokens.Radius.planRoom)
            var gridContext = context
            gridContext.clip(to: room)
            gridContext.fill(geometry.contextGrid, with: .color(RoomTokens.Surface.line2))
            context.stroke(room, with: .color(outline), style: Tokens.dashedWall)
        }
        drawDots(geometry, context: context)
        if belowGoal, let free = geometry.free?.insetBy(dx: Tokens.roomGap, dy: Tokens.roomGap), !free.isEmpty {
            context.stroke(Path(roundedRect: free, cornerRadius: RoomTokens.Radius.planRoom),
                           with: .color(RoomTokens.Status.elevated), lineWidth: Tokens.elevatedWall)
        }
        if let goal = geometry.goal {
            context.stroke(Path(roundedRect: goal, cornerRadius: RoomTokens.Radius.planRoom),
                           with: .color(outline), style: Tokens.dashedWall)
            if let text = presentation.goalLabel, goal.width >= Tokens.goalLabelSize.width,
               goal.height >= Tokens.goalLabelSize.height {
                drawLabel(text, in: goal.insetBy(dx: Tokens.goalInset, dy: 0), font: RoomTokens.Typography.micro,
                          ink: RoomTokens.Ink.secondary, centeredVertically: true, context: context)
            }
        }
        if focused || hover != nil {
            let frame = (hover ?? selection).flatMap { geometry.frame(for: $0) } ?? geometry.wall
            let ring = Path(roundedRect: frame.insetBy(dx: -Tokens.focusOffset, dy: -Tokens.focusOffset),
                            cornerRadius: RoomTokens.Radius.planRoom)
            context.stroke(ring, with: .color(accent.text), lineWidth: Tokens.focusWall)
        }
        drawRoomLabels(presentation, geometry: geometry, context: context)
    }

    private func resetWake() {
        field = RoomWakeField(dotCount: drawing?.dotCenters.count ?? 0, enabled: motion.isFull)
        lastFrame = nil
    }

    private func advanceWake(to date: Date) {
        guard let drawing, !field.isAtRest else { return }
        let dt = lastFrame.map { date.timeIntervalSince($0) * 1_000 } ?? 16
        field.step(dtMS: dt, dots: drawing.dotCenters)
        lastFrame = field.isAtRest ? nil : date
    }

    private func drawDots(_ geometry: RoomOverviewPlanGeometry, context: GraphicsContext) {
        var paths: [RoomPlanRoom: Path] = [:]
        for (index, dot) in geometry.layout.dots.enumerated() {
            let center = geometry.dotCenters[index]
            let rest = geometry.layout.radius
            let radius = index < field.energy.count ? field.radius(index, rest: rest) : rest
            paths[dot.room, default: Path()].addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        for (room, path) in paths {
            switch room {
            case .free:
                let opacity = contrast == .increased ? 1 : RoomTokens.Dots.freeRingOpacity
                context.stroke(path, with: .color(RoomTokens.Ink.secondary.opacity(opacity)),
                               lineWidth: RoomTokens.Dots.freeRingStroke)
            case .kind(let key):
                if let kind = RoomTokens.Kind(rawValue: key) {
                    let focusedKind = hover ?? selection
                    let dims = focusedKind.map { $0 != room } ?? false
                    context.fill(path, with: .color(kind.mark.opacity(dims ? RoomTokens.OverviewPlan.dimmedKind : 1)))
                }
            case .notMapped: break
            }
        }
        for ring in field.rings {
            guard let style = RoomWakeField.drawnRing(ageMS: ring.ageMS) else { continue }
            let rect = CGRect(x: ring.center.x - style.radius, y: ring.center.y - style.radius,
                              width: 2 * style.radius, height: 2 * style.radius)
            context.stroke(Path(ellipseIn: rect), with: .color(accent.fill.opacity(style.opacity)), lineWidth: Tokens.wall)
        }
    }

    private func drawRoomLabels(_ presentation: RoomOverviewPlanPresentation, geometry: RoomOverviewPlanGeometry,
                                context: GraphicsContext) {
        if let free = geometry.freeLabelArea, let row = presentation.rows.first(where: { $0.id == .free }),
           (geometry.free?.height ?? 0) >= free.height + Tokens.labelInset {
            drawLabel(row.name, in: free, font: Tokens.freeLabel, ink: RoomTokens.Ink.graphite, context: context)
            let size = free.offsetBy(dx: 0, dy: Tokens.labelLineHeight)
            drawLabel(row.visualSize, in: size, font: RoomTokens.Typography.caption,
                      ink: RoomTokens.Ink.secondary, context: context)
        }
        for row in presentation.rows.filter({ if case .kind = $0.id { true } else { false } }).prefix(3) {
            guard let room = geometry.frame(for: row.id) else { continue }
            let bounds = room.insetBy(dx: Tokens.labelInset, dy: Tokens.labelInset)
            let opacity = (motion.isFull ? pointer : nil).map {
                RoomPure.lampOpacity(distance: hypot($0.x - bounds.midX, $0.y - bounds.midY))
            } ?? RoomTokens.OverviewPlan.quietLabelOpacity
            drawLabel(row.name, in: bounds, font: RoomTokens.Typography.micro,
                      ink: RoomTokens.Ink.graphite.opacity(opacity), context: context)
        }
        if let room = geometry.notMapped, let row = presentation.rows.first(where: { $0.id == .notMapped }) {
            let bounds = room.insetBy(dx: Tokens.labelInset, dy: Tokens.labelInset)
            drawLabel("\(row.name) · \(row.visualSize)", in: bounds, font: RoomTokens.Typography.micro,
                      ink: RoomTokens.Ink.graphite, context: context)
        }
    }

    private func drawLabel(_ text: String, in bounds: CGRect, font: Font, ink: Color,
                           centeredVertically: Bool = false, context: GraphicsContext) {
        let label = context.resolve(Text(text).font(font).foregroundStyle(ink))
        let size = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        guard size.width <= bounds.width, size.height <= bounds.height else { return }
        let point = CGPoint(x: bounds.minX, y: centeredVertically ? bounds.midY : bounds.minY)
        context.draw(label, at: point, anchor: centeredVertically ? .leading : .topLeading)
    }
}
