import RoomCore
import SwiftUI

struct RoomMapCanvas: View {
    let level: RoomTreeNode
    let selection: String?
    let hidden: Bool
    var pending: Set<String> = []
    var placedLayer: RoomMapLayer?
    var interactive = true
    var suppressLabels = false
    var activate: (String, Bool, Bool) -> Void = { _, _, _ in }
    var preview: (String) -> Bool = { _ in false }
    var reveal: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let layer = placedLayer ?? RoomMapLayer.make(level: level, size: geometry.size)
            RoomMapCanvasSurface(layer: layer, level: level, selection: selection, hidden: hidden,
                pending: pending, interactive: interactive, suppressLabels: suppressLabels,
                activate: activate, preview: preview, reveal: reveal)
        }
        .background(RoomTokens.Surface.canvas, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.card))
        .accessibilityIdentifier("RoomDiskMapCanvas")
    }
}

private struct RoomMapCanvasSurface: View {
    @Environment(\.roomAccent) private var accent
    @Namespace private var rotor
    @FocusState private var hasFocus: Bool
    @State private var hovered: String?
    @State private var keyboardSelection: String?
    let layer: RoomMapLayer
    let level: RoomTreeNode
    let selection: String?
    let hidden: Bool
    let pending: Set<String>
    let interactive: Bool
    let suppressLabels: Bool
    let activate: (String, Bool, Bool) -> Void
    let preview: (String) -> Bool
    let reveal: (String) -> Void

    private var ordered: [RoomMapItem] {
        layer.items.sorted { lhs, rhs in lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes }
    }

    var body: some View {
        if interactive { interactiveCanvas }
        else { artwork }
    }

    private var artwork: some View {
        Canvas { context, _ in
            for tile in layer.items { draw(tile, in: context) }
        }
    }

    private var interactiveCanvas: some View {
        artwork
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = layer.hit(point)?.id
            case .ended: hovered = nil
            }
        }
        .onTapGesture(count: 2, coordinateSpace: .local) { hit($0, open: true) }
        .onTapGesture(count: 1, coordinateSpace: .local) { hit($0, open: false) }
        .focusable()
        .focused($hasFocus)
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.return) {
            guard let item = keyboardSelection ?? selection ?? ordered.first?.id else { return .ignored }
            activate(item, true, false)
            return .handled
        }
        .onKeyPress(.space) {
            guard let selected = keyboardSelection ?? selection, preview(selected) else { return .ignored }
            return .handled
        }
        .onKeyPress(.escape) {
            keyboardSelection = nil
            return .handled
        }
        .onChange(of: level.relativePath) { _, _ in
            hovered = nil
            keyboardSelection = nil
        }
        .accessibilityLabel("Disk Map")
        .accessibilityChildren {
            ForEach(ordered, id: \.id) { item in
                Button(spoken(item)) { activate(item.id, item.canStepInside, false) }
                    .accessibilityRotorEntry(id: item.id, in: rotor)
                    .accessibilityAction(named: "Show in Finder") { reveal(item.id) }
            }
        }
        .accessibilityRotor("Largest items") {
            ForEach(ordered, id: \.id) { item in
                AccessibilityRotorEntry(Text(verbatim: spoken(item)), id: item.id, in: rotor)
            }
        }
    }

    private func paintName(_ tile: RoomMapItem) -> String {
        if hidden { return tile.isOther ? "Other" : "Hidden" }
        if tile.isOther && tile.otherCount > 0 { return "Other · \(tile.otherCount) small items" }
        return tile.name + (tile.canStepInside && tile.role != .group ? " ›" : "")
    }

    private func spoken(_ tile: RoomMapItem) -> String {
        RoomMapSpeech.label(tile, parentName: level.name, parentBytes: level.allocatedBytes,
                            spoken: RoomFormat.bytes, hidden: hidden)
    }

    private func draw(_ tile: RoomMapItem, in canvas: GraphicsContext) {
        guard tile.drawRect.width > 0, tile.drawRect.height > 0 else { return }
        var context = canvas
        let style = tile.kind.flatMap(RoomTokens.Kind.init(rawValue:))
        let isPending = pending.contains(tile.id)
        let shape = Path(roundedRect: tile.drawRect, cornerRadius: tile.role == .group ? RoomTokens.Radius.field : RoomTokens.Radius.tile)
        let fill = tile.role == .group ? RoomTokens.Surface.track : style?.fill ?? RoomTokens.Surface.track
        context.opacity = isPending ? (tile.role == .group ? RoomTokens.Map.pendingGroupOpacity : RoomTokens.Map.pendingTileOpacity) : 1
        context.fill(shape, with: .color(fill))
        if tile.isPartial || isPending {
            var clipped = context
            clipped.clip(to: shape)
            clipped.stroke(hatch(in: tile.drawRect), with: .color(RoomTokens.Surface.hatch), lineWidth: RoomTokens.Map.hatchStroke)
        }
        if tile.id == selection || tile.id == hovered {
            context.stroke(shape, with: .color(RoomTokens.Ink.graphite), lineWidth: RoomTokens.Map.focusStroke)
        }
        if hasFocus, keyboardSelection == tile.id {
            context.stroke(shape, with: .color(accent.fill), lineWidth: RoomTokens.Map.focusStroke)
        }
        guard !suppressLabels, tile.label != .none else { return }
        let labelBox = (tile.headerRect ?? tile.drawRect).insetBy(dx: RoomTokens.Map.labelPaddingX, dy: RoomTokens.Map.labelPaddingY)
        guard labelBox.width > 0, labelBox.height > 0 else { return }
        let size = hidden ? "Hidden" : (tile.isPartial && !isPending ? "≥ " : "") + RoomFormat.bytes(tile.bytes)
        let name = Text(paintName(tile)).font(tile.role == .group ? RoomTokens.Typography.micro : RoomTokens.Typography.caption.weight(.semibold))
            .foregroundStyle(RoomTokens.Kind.tileInk)
        if tile.role == .group {
            let figure = Text("  " + size).font(RoomTokens.Typography.micro).foregroundStyle(RoomTokens.Kind.tileInk2)
            let label = Text("\(name)\(figure)")
            context.draw(label, in: labelBox)
        } else if tile.label == .nameAndSize {
            let figure = Text("\n" + size).font(RoomTokens.Typography.captionNumeric).foregroundStyle(RoomTokens.Kind.tileInk2)
            let label = Text("\(name)\(figure)")
            context.draw(label, in: labelBox)
        } else {
            context.draw(name, in: labelBox)
        }
    }

    private func hatch(in rect: CGRect) -> Path {
        Path { path in
            for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: RoomTokens.Map.hatchPitch) {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            }
        }
    }

    private func hit(_ point: CGPoint, open: Bool) {
        guard let tile = layer.hit(point) else { return }
        keyboardSelection = nil
        activate(tile.id, open || tile.isHeader, true)
    }

    private func move(_ direction: RoomMapDirection) -> KeyPress.Result {
        guard let first = ordered.first?.id else { return .ignored }
        if let from = keyboardSelection ?? selection {
            keyboardSelection = layer.neighbour(of: from, direction) ?? from
        } else {
            keyboardSelection = first
        }
        if let keyboardSelection { activate(keyboardSelection, false, false) }
        return .handled
    }
}
