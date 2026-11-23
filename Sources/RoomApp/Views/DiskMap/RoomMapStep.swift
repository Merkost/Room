import RoomCore
import SwiftUI

nonisolated enum RoomMapStepGeometry {
    /// The tile representing a descendant at this level, including a descendant drawn inside a group.
    static func anchor(for path: String, in layer: RoomMapLayer) -> CGRect? {
        layer.items
            .filter { !$0.isOther && (path == $0.id || path.hasPrefix($0.id + "/")) }
            .max { $0.id.count < $1.id.count }?.drawRect
    }

    /// Maps the viewport onto the selected tile. The inverse expands that tile to fill the viewport.
    static func fit(tile: CGRect, in size: CGSize) -> CGAffineTransform? {
        guard size.width > 0, size.height > 0, tile.width > 0, tile.height > 0 else { return nil }
        return CGAffineTransform(a: tile.width / size.width, b: 0, c: 0, d: tile.height / size.height,
                                 tx: tile.minX, ty: tile.minY)
    }
}

struct RoomMapStep {
    let generation: Int
    let previous: RoomTreeNode
    let selection: String?
    let destination: String
    let into: Bool

    func transforms(previousLayer: RoomMapLayer, currentLayer: RoomMapLayer, size: CGSize)
        -> (incoming: CGAffineTransform, outgoing: CGAffineTransform)? {
        let tile = into ? RoomMapStepGeometry.anchor(for: destination, in: previousLayer)
            : RoomMapStepGeometry.anchor(for: previous.relativePath, in: currentLayer)
        guard let tile, let fit = RoomMapStepGeometry.fit(tile: tile, in: size) else { return nil }
        return into ? (fit, fit.inverted()) : (fit.inverted(), fit)
    }
}

nonisolated struct RoomMapLayerEffect: GeometryEffect {
    var transform: CGAffineTransform

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(transform.a, transform.d), .init(transform.tx, transform.ty)) }
        set {
            transform = CGAffineTransform(a: newValue.first.first, b: 0, c: 0, d: newValue.first.second,
                                          tx: newValue.second.first, ty: newValue.second.second)
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(transform) }
}

/// The outgoing canvas keeps its view identity as its transform changes. A subsequent step can
/// therefore retarget the canvas still on screen from its current presentation.
struct RoomMapViewport: View {
    let level: RoomTreeNode
    let selection: String?
    let hidden: Bool
    let generation: Int
    let step: RoomMapStep?
    let onHoverItem: (RoomMapItem?) -> Void
    let activate: (String, Bool, Bool) -> Void
    let preview: (String) -> Bool
    let reveal: (String) -> Void
    @Environment(\.roomMotion) private var motion
    @State private var layers = RoomMapViewportLayers()

    var body: some View {
        GeometryReader { geometry in
            let currentLayer = layers.layer(for: level, size: geometry.size)
            let outgoing = step.map { layers.layer(for: $0.previous, size: geometry.size) }
            let transforms = motion.isFull ? outgoing.flatMap { layer in
                step?.transforms(previousLayer: layer, currentLayer: currentLayer, size: geometry.size)
            } : nil
            let frames = step.map { [$0.generation - 1, generation] } ?? [generation]
            ZStack {
                ForEach(frames, id: \.self) { frame in
                    let current = frame == generation
                    let entry = transforms.map {
                        AnyTransition.modifier(active: RoomMapLayerEffect(transform: $0.incoming),
                                               identity: RoomMapLayerEffect(transform: .identity)).combined(with: .opacity)
                    } ?? .opacity
                    RoomMapCanvas(level: current ? level : step?.previous ?? level,
                                  selection: current ? selection : step?.selection,
                                  hidden: hidden, placedLayer: current ? currentLayer : outgoing,
                                  interactive: current,
                                  onHoverItem: onHoverItem,
                                  activate: activate, preview: preview, reveal: reveal)
                        .modifier(RoomMapLayerEffect(transform: current ? .identity : transforms?.outgoing ?? .identity))
                        .opacity(current ? 1 : 0)
                        .zIndex(current ? 1 : 0)
                        .allowsHitTesting(current)
                        .accessibilityHidden(!current)
                        .transition(.asymmetric(insertion: entry, removal: .opacity))
                }
            }
            .clipped()
        }
    }
}

/// Keep the current and neighboring layouts available to hover, drill-in and back.
/// Each entry retains only a bounded tree and is invalidated by measurement or resize.
@MainActor
private final class RoomMapViewportLayers {
    private struct Entry {
        let node: RoomTreeNode
        let size: CGSize
        let layer: RoomMapLayer
    }

    private var entries: [Entry] = []

    func layer(for node: RoomTreeNode, size: CGSize) -> RoomMapLayer {
        if let index = entries.firstIndex(where: { $0.size == size && $0.node == node }) {
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.layer
        }
        let layer = RoomMapLayer.make(level: node, size: size)
        entries.insert(Entry(node: node, size: size, layer: layer), at: 0)
        if entries.count > 3 { entries.removeLast() }
        return layer
    }
}
