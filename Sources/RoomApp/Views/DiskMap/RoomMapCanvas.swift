import AppKit
import RoomCore
import SwiftUI

struct RoomMapCanvas: View {
    let level: RoomTreeNode
    let selection: String?
    let hidden: Bool
    var blueprint: RoomBlueprint?
    var placedLayer: RoomMapLayer?
    var interactive = true
    var onHoverItem: (RoomMapItem?) -> Void = { _ in }
    var activate: (String, Bool, Bool) -> Void = { _, _, _ in }
    var preview: (String) -> Bool = { _ in false }
    var reveal: (String) -> Void = { _ in }

    var body: some View {
        let animatedLayouts = motion.isFull
        GeometryReader { geometry in
            let layer = placedLayer ?? RoomMapLayer.make(level: level, size: geometry.size)
            let scan = blueprint.map {
                RoomBlueprintMotion(blueprint: $0, items: layer.items, size: geometry.size, animates: animatedLayouts)
            }
            RoomMapCanvasSurface(layer: layer, level: level, selection: selection, hidden: hidden,
                scan: scan, interactive: interactive,
                onHoverItem: onHoverItem, activate: activate, preview: preview, reveal: reveal)
        }
        .background(RoomTokens.Surface.canvas, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.card))
        .accessibilityIdentifier("RoomDiskMapCanvas")
    }

    @Environment(\.roomMotion) private var motion
}

private struct RoomMapCanvasSurface: View {
    @Environment(\.roomAccent) private var accent
    @Namespace private var rotor
    @FocusState private var hasFocus: Bool
    @State private var hovered: String?
    @State private var keyboardSelection: String?
    @State private var lastClickedTile: String?
    @State private var settledScan: Date?
    let layer: RoomMapLayer
    let level: RoomTreeNode
    let selection: String?
    let hidden: Bool
    let scan: RoomBlueprintMotion?
    let interactive: Bool
    let onHoverItem: (RoomMapItem?) -> Void
    let activate: (String, Bool, Bool) -> Void
    let preview: (String) -> Bool
    let reveal: (String) -> Void

    private var ordered: [RoomMapItem] {
        layer.items.sorted { lhs, rhs in lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes }
    }

    var body: some View {
        if let scan { blueprintArtwork(scan) }
        else {
            ZStack {
                RoomMapArtwork(items: layer.items, hidden: hidden)
                    .equatable()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if interactive { interactiveCanvas }
                else if selection != nil { highlights }
            }
        }
    }

    private var highlights: some View {
        let focus = interactive && hasFocus ? keyboardSelection ?? selection ?? ordered.first?.id : nil
        let hover = interactive ? hovered : nil
        var frame = RoomCanvasFrame()
        for tile in layer.items where tile.id == selection || tile.id == hover || tile.id == focus {
            let shape = RoomMapArtwork.outline(tile)
            let stroke = RoomTokens.Map.focusStroke
            if tile.id == selection {
                frame.stroke(shape, RoomTokens.Surface.group, lineWidth: stroke + 2)
            }
            if tile.id == selection || tile.id == hover {
                frame.stroke(shape, RoomTokens.Ink.graphite, lineWidth: stroke, clip: shape)
            }
            if tile.id == focus {
                frame.stroke(shape, accent.fill, lineWidth: stroke)
            }
        }
        return Canvas(renderer: frame.renderer)
    }

    private func blueprintArtwork(_ scan: RoomBlueprintMotion) -> some View {
        ZStack {
            if scan.firstScan { blueprintGrid }
            if let start = scan.startedAt, settledScan != start {
                TimelineView(.animation) { tick in
                    scanArtwork(scan, elapsed: tick.date.timeIntervalSince(start))
                }
            } else {
                scanArtwork(scan, elapsed: RoomBlueprintMotion.duration)
            }
        }
        .task(id: scan.startedAt) {
            guard let start = scan.startedAt else { return }
            let remaining = start.addingTimeInterval(RoomBlueprintMotion.duration).timeIntervalSinceNow
            do {
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                guard !Task.isCancelled else { return }
                settledScan = start
            } catch {}
        }
    }

    private var blueprintGrid: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pitch = RoomTokens.Map.blueprintGridPitch
            let dot = RoomTokens.Map.blueprintGridDot
            let grid = Path { path in
                for y in stride(from: pitch / 2, to: size.height, by: pitch) {
                    for x in stride(from: pitch / 2, to: size.width, by: pitch) {
                        path.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                    }
                }
            }
            grid.fill(RoomTokens.Surface.line2)
        }
    }

    private func scanArtwork(_ scan: RoomBlueprintMotion, elapsed: TimeInterval) -> some View {
        var artwork = RoomCanvasFrame()
        let geometry = scan.geometry(at: elapsed)
        for item in layer.items {
            let frame = scan.place(item, at: geometry)
            let reveal = scan.reveal(item.id, at: elapsed)
            let mixed = item.isOther && !scan.pending.isEmpty
            if reveal.fill < 1, scan.previousPending.contains(item.id), var earlier = scan.previous[item.id] {
                earlier.drawRect = frame.drawRect
                RoomMapArtwork.draw(earlier, in: &artwork, hidden: hidden, pending: true, opacity: 1 - reveal.fill)
            }
            RoomMapArtwork.draw(frame, in: &artwork, hidden: hidden, pending: scan.pending.contains(item.id) || mixed,
                               opacity: reveal.fill, hideFigure: mixed)
            if reveal.wall > 0 {
                let shape = Path(roundedRect: frame.drawRect, cornerRadius: RoomTokens.Radius.tile)
                artwork.stroke(shape.trimmedPath(from: 0, to: reveal.wall), RoomTokens.Ink.secondary,
                               lineWidth: RoomTokens.Map.blueprintWallStroke, opacity: 1 - reveal.fill)
            }
        }
        return Canvas(renderer: artwork.renderer)
    }

    private var interactiveCanvas: some View {
        highlights
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let item: RoomMapItem?
            switch phase {
            case .active(let point): item = layer.hit(point)?.item
            case .ended: item = nil
            }
            guard hovered != item?.id else { return }
            hovered = item?.id
            onHoverItem(item)
        }
        .onTapGesture(coordinateSpace: .local) { hit($0) }
        .focusable()
        // AppKit rasterizes the entire transformed focus ring during a zoom.
        .focusEffectDisabled()
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
        .onChange(of: level) { _, _ in
            hovered = nil
            keyboardSelection = nil
            lastClickedTile = nil
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

    private func spoken(_ tile: RoomMapItem) -> String {
        RoomMapSpeech.label(tile, parentName: level.name, parentBytes: level.allocatedBytes,
                            spoken: RoomFormat.bytes, hidden: hidden)
    }

    private func hit(_ point: CGPoint) {
        guard let tile = layer.hit(point) else { lastClickedTile = nil; return }
        let click = NSApp.currentEvent
        let count = click?.type == .leftMouseUp ? click?.clickCount ?? 1 : 1
        let id = tile.item.id
        // A second click that lands on a newly opened level must not open another folder.
        guard count == 1 || (count == 2 && lastClickedTile == id) else { return }
        lastClickedTile = id
        keyboardSelection = nil
        activate(id, count == 2 || tile.isHeader, true)
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

/// Layout changes redraw the artwork. Hover, focus and selection update only the outlines above it.
private struct RoomMapArtwork: View, Equatable {
    let items: [RoomMapItem]
    let hidden: Bool

    var body: some View {
        var frame = RoomCanvasFrame()
        for tile in items { Self.draw(tile, in: &frame, hidden: hidden) }
        return Canvas(rendersAsynchronously: true, renderer: frame.renderer)
    }

    static func outline(_ tile: RoomMapItem) -> Path {
        Path(roundedRect: tile.drawRect,
             cornerRadius: tile.role == .group ? RoomTokens.Radius.field : RoomTokens.Radius.tile)
    }

    private static func paintName(_ tile: RoomMapItem, hidden: Bool) -> String {
        if hidden { return tile.isOther ? "Other" : "Hidden" }
        if tile.isOther && tile.otherCount > 0 { return "Other · \(tile.otherCount) small items" }
        return tile.name + (tile.canStepInside && tile.role != .group ? " ›" : "")
    }

    static func draw(_ tile: RoomMapItem, in canvas: inout RoomCanvasFrame, hidden: Bool, pending isPending: Bool = false,
                     opacity: Double = 1, hideFigure: Bool = false) {
        guard opacity > 0, tile.drawRect.width > 0, tile.drawRect.height > 0 else { return }
        let style = tile.kind.flatMap(RoomTokens.Kind.init(rawValue:))
        let shape = outline(tile)
        let fill = tile.role == .group ? RoomTokens.Surface.track : style?.fill ?? RoomTokens.Surface.track
        let alpha = opacity * (isPending
            ? (tile.role == .group ? RoomTokens.Map.pendingGroupOpacity : RoomTokens.Map.pendingTileOpacity) : 1)
        canvas.fill(shape, fill, opacity: alpha)
        if tile.isPartial || isPending {
            canvas.stroke(hatch(in: tile.drawRect), RoomTokens.Surface.hatch,
                          lineWidth: RoomTokens.Map.hatchStroke, clip: shape, opacity: alpha)
        }
        guard tile.label != .none else { return }
        let labelBox = (tile.headerRect ?? tile.drawRect).insetBy(dx: RoomTokens.Map.labelPaddingX, dy: RoomTokens.Map.labelPaddingY)
        guard labelBox.width > 0, labelBox.height > 0 else { return }
        let size = hidden ? "Hidden" : (tile.isPartial && !isPending ? "≥ " : "") + RoomFormat.bytes(tile.bytes)
        let titleFont = tile.drawRect.width >= 140 && tile.drawRect.height >= 70
            ? RoomTokens.Typography.section : RoomTokens.Typography.caption.weight(.semibold)
        let grouped = tile.role == .group
        let name = RoomCanvasFrame.Line(value: paintName(tile, hidden: hidden),
            font: grouped ? RoomTokens.Typography.micro.weight(.semibold) : titleFont, ink: RoomTokens.Kind.tileInk)
        let figure = RoomCanvasFrame.Line(value: size,
            font: grouped ? RoomTokens.Typography.micro : RoomTokens.Typography.captionNumeric, ink: RoomTokens.Kind.tileInk2)
        canvas.lines(name, tile.label == .nameAndSize && !hideFigure ? figure : nil,
                     in: labelBox, inline: grouped, opacity: alpha)
    }

    private static func hatch(in rect: CGRect) -> Path {
        Path { path in
            for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: RoomTokens.Map.hatchPitch) {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            }
        }
    }

}
