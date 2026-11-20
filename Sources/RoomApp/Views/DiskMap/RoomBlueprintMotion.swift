import SwiftUI

/// A scan publishes new layouts at most once a second. Sample that single batch as it settles
/// so the canvas needs no per-tile state or timer.
struct RoomBlueprintMotion {
    struct Reveal {
        let wall: Double
        let fill: Double
    }

    let startedAt: Date?
    let previous: [String: RoomMapItem]
    let pending: Set<String>
    let previousPending: Set<String>
    let firstScan: Bool
    private let order: [String: Int]

    init(blueprint: RoomBlueprint, items: [RoomMapItem], size: CGSize, animates: Bool) {
        startedAt = animates && blueprint.phase == .scanning ? blueprint.lastReflow : nil
        firstScan = blueprint.earlierDate == nil
        let rooms = blueprint.rooms
        let waiting = Set(rooms.filter(\.isEarlier).map(\.name))
        pending = waiting
        guard startedAt != nil else {
            previous = [:]
            previousPending = []
            order = [:]
            return
        }
        let earlier = Set(blueprint.beforeLastReflow.filter(\.isEarlier).map(\.name))
        let tree = RoomBlueprint.tree(rooms: blueprint.beforeLastReflow, maximumTiles: RoomMapLayer.maxTiles)
        let prior = RoomMapLayer.layout(tree, in: CGRect(origin: .zero, size: size))
        let old = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, $0) })
        previous = old
        previousPending = earlier
        let measuredChanges = items.filter { item in
            !waiting.contains(item.id) && (old[item.id] == nil || earlier.contains(item.id))
        }
        order = Dictionary(uniqueKeysWithValues: measuredChanges.enumerated().map { ($0.element.id, $0.offset) })
    }

    private static let easing = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1),
                                                endControlPoint: UnitPoint(x: 0.32, y: 1))
    private static let reflowSpring = Spring(response: RoomTokens.Motion.pageResponse, dampingRatio: 1)

    static var duration: TimeInterval {
        RoomTokens.Dots.blueprintWall + RoomTokens.Dots.blueprintFill
            + Double(RoomTokens.Motion.maxStaggered - 1) * RoomTokens.Motion.stagger
    }

    func reveal(_ id: String, at elapsed: TimeInterval) -> Reveal {
        guard startedAt != nil, let index = order[id] else { return Reveal(wall: 0, fill: 1) }
        let delay = Double(min(index, RoomTokens.Motion.maxStaggered - 1)) * RoomTokens.Motion.stagger
        let time = elapsed - delay
        if previousPending.contains(id) { return Reveal(wall: 0, fill: Self.progress(time, over: RoomTokens.Dots.blueprintFill)) }
        return Reveal(wall: Self.progress(time, over: RoomTokens.Dots.blueprintWall),
                      fill: Self.progress(time - RoomTokens.Dots.blueprintWall, over: RoomTokens.Dots.blueprintFill))
    }

    func geometry(at elapsed: TimeInterval) -> Double {
        guard startedAt != nil, elapsed < Self.duration else { return 1 }
        return Self.reflowSpring.value(target: 1.0, initialVelocity: 0, time: max(0, elapsed))
    }

    func place(_ item: RoomMapItem, at progress: Double) -> RoomMapItem {
        guard progress < 1, let old = previous[item.id] else { return item }
        var frame = item
        frame.drawRect = CGRect(x: old.drawRect.minX + (item.drawRect.minX - old.drawRect.minX) * progress,
                                y: old.drawRect.minY + (item.drawRect.minY - old.drawRect.minY) * progress,
                                width: old.drawRect.width + (item.drawRect.width - old.drawRect.width) * progress,
                                height: old.drawRect.height + (item.drawRect.height - old.drawRect.height) * progress)
        return frame
    }

    private static func progress(_ elapsed: TimeInterval, over duration: TimeInterval) -> Double {
        easing.value(at: min(1, max(0, elapsed / duration)))
    }
}

/// Counter-only progress can arrive between layout batches. Keep it out of the tile view.
struct RoomBlueprintArtwork: View, Equatable {
    let blueprint: RoomBlueprint
    let hidden: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.blueprint.id == rhs.blueprint.id && lhs.blueprint.lastReflow == rhs.blueprint.lastReflow
            && lhs.blueprint.phase == rhs.blueprint.phase && lhs.hidden == rhs.hidden
    }

    var body: some View {
        RoomMapCanvas(level: RoomBlueprint.tree(rooms: blueprint.rooms, maximumTiles: RoomMapLayer.maxTiles),
                      selection: nil, hidden: hidden, blueprint: blueprint, interactive: false)
            .id(blueprint.id)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
