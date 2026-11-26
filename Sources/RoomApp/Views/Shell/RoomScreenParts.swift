import AppKit
import SwiftUI

/// Counted dots as a bar: one dot per whole GB, capped so the largest row still fits.
struct RoomDotBar: View {
    let bytes: Int64
    var color: Color = RoomTokens.Ink.secondary
    var dimmed = false

    static func count(_ bytes: Int64) -> Int {
        let gb = Int((Double(bytes) / 1e9).rounded())
        return min(RoomTokens.Screen2.dotBarMax, max(bytes > 0 ? 1 : 0, gb))
    }

    var body: some View {
        let n = Self.count(bytes)
        Canvas { context, size in
            let pitch = RoomTokens.Screen2.dotBarPitch, d = RoomTokens.Screen2.dotBarDot
            let fit = min(n, Int(size.width / pitch))
            for i in 0..<fit {
                let rect = CGRect(x: CGFloat(i) * pitch + (pitch - d) / 2, y: (size.height - d) / 2, width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(height: RoomTokens.Screen2.dotBarPitch)
        .frame(maxWidth: CGFloat(n) * RoomTokens.Screen2.dotBarPitch, alignment: .leading)
        .opacity(dimmed ? 0.3 : 1)
        .accessibilityHidden(true)
    }
}

/// A quiet neutral glyph tile (Settings, History). Hide keeps the tile and drops the glyph.
struct RoomQuietTile: View {
    let glyph: RoomGlyph
    var size: CGFloat = RoomTokens.Screen2.icon
    @Environment(\.roomHide) private var hide

    var body: some View {
        RoundedRectangle(cornerRadius: RoomTokens.Screen2.iconRadius * size / RoomTokens.Screen2.icon)
            .fill(RoomTokens.Surface.tile)
            .overlay {
                if !hide.masksNow {
                    RoomGlyphView(glyph: glyph, size: size * 0.62, weight: 1.5).foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The real icon of a thing a row names (an app, a project folder, a cache place) from NSWorkspace. Things without an
/// app get a coloured stand-in tile (`RoomThingTiles`); a project gets a stable colour. Hide replaces every icon with a
/// blank tile.
struct RoomThingIcon: View {
    let path: String?
    var name: String? = nil
    var fallback: RoomGlyph = .folder
    var size: CGFloat = RoomTokens.Screen2.icon
    var project = false
    @Environment(\.roomHide) private var hide

    var body: some View {
        let radius = RoomTokens.Screen2.iconRadius * size / RoomTokens.Screen2.icon
        Group {
            if hide.masksNow {
                RoundedRectangle(cornerRadius: radius).fill(RoomTokens.Surface.tile)
            } else if let image = RoomThingIconCache.shared.appIcon(named: name) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else if let match = name.flatMap(RoomThingTiles.match) {
                RoomColourTile(color: RoomThingTiles.color(match.color), glyph: match.glyph, size: size)
            } else if project, let name {
                RoomColourTile(color: RoomThingTiles.color(RoomThingTiles.projectColor(name)), glyph: fallback, size: size)
            } else if let image = RoomThingIconCache.shared.icon(for: path) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoomQuietTile(glyph: fallback, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A stand-in app icon: a rounded colour tile with a white glyph, a top highlight and a hairline (mockup `.ai`).
struct RoomColourTile: View {
    let color: Color
    let glyph: RoomGlyph
    var size: CGFloat = RoomTokens.Screen2.icon

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Screen2.iconRadius * size / RoomTokens.Screen2.icon, style: .continuous)
        shape.fill(color)
            .overlay(shape.strokeBorder(RoomTokens.Surface.tileEdge, lineWidth: 0.5))
            .overlay {
                RoomGlyphView(glyph: glyph, size: size * 0.62, weight: 1.5).foregroundStyle(RoomTokens.Surface.onTile)
            }
            .shadow(color: RoomTokens.Surface.tileShadow, radius: 1, y: 1)
    }
}

/// NSWorkspace icons are cheap but not free; rows redraw often while a scan counts.
@MainActor final class RoomThingIconCache {
    static let shared = RoomThingIconCache()
    private var icons: [String: NSImage] = [:]
    private var apps: [String: NSImage?] = [:]

    func icon(for path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let icon = icons[path] { return icon }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    /// The installed app a thing belongs to (Xcode for DerivedData, Safari, Simulator), or nil.
    func appIcon(named name: String?) -> NSImage? {
        guard let name, let id = RoomThingTiles.match(name)?.bundleID else { return nil }
        if let cached = apps[id] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
        apps[id] = icon
        return icon
    }
}

/// One evidence row: icon, name and a quiet meta line, counted dots, the size, and an optional trailing link.
struct RoomEvidenceRow<Icon: View, Trailing: View>: View {
    let name: String
    var meta: String?
    let bytes: Int64
    /// The size as shown; nil formats `bytes` as a disk size. Memory rows pass `RoomFormat.memory`.
    var value: String? = nil
    var masksName = true
    var barColor: Color = RoomTokens.Ink.secondary
    var dimmed = false
    var nameColumn: CGFloat = RoomTokens.Screen2.listNameColumn
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.roomHide) private var hide

    var body: some View {
        HStack(spacing: RoomTokens.Space.group + 2) {
            HStack(spacing: RoomTokens.Space.row) {
                icon()
                Group {
                    if masksName { RoomMaskable(name, kind: .name) } else { Text(name) }
                }
                .font(RoomTokens.Screen2.listName)
                .foregroundStyle(dimmed ? RoomTokens.Ink.tertiary : RoomTokens.Ink.graphite)
                .lineLimit(1)
                .layoutPriority(1)
                if let meta {
                    Text(meta).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: nameColumn, alignment: .leading)
            RoomDotBar(bytes: bytes, color: barColor, dimmed: dimmed)
                .frame(maxWidth: .infinity, alignment: .leading)
            RoomMaskable(value ?? RoomFormat.gb(bytes))
                .font(RoomTokens.Screen2.listValue)
                .foregroundStyle(dimmed ? RoomTokens.Ink.tertiary : RoomTokens.Ink.graphite)
                .frame(minWidth: 56, alignment: .trailing)
            trailing()
        }
        .frame(minHeight: RoomTokens.Screen2.listRow)
        .accessibilityElement(children: .combine)
    }
}

extension RoomEvidenceRow where Trailing == EmptyView {
    init(name: String, meta: String? = nil, bytes: Int64, value: String? = nil, masksName: Bool = true,
         barColor: Color = RoomTokens.Ink.secondary, dimmed: Bool = false,
         nameColumn: CGFloat = RoomTokens.Screen2.listNameColumn, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(name: name, meta: meta, bytes: bytes, value: value, masksName: masksName, barColor: barColor, dimmed: dimmed,
                  nameColumn: nameColumn, icon: icon, trailing: { EmptyView() })
    }
}

/// A small group label above a list ("November", "Privacy").
struct RoomGroupLabel: View {
    let text: String
    var body: some View {
        Text(text).font(RoomTokens.Screen2.groupLabel).foregroundStyle(RoomTokens.Ink.tertiary)
            .padding(.top, RoomTokens.Space.group).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A designed empty state for a list: a quiet glyph tile and one plain sentence, never a blank area.
struct RoomEmptyLine: View {
    let glyph: RoomGlyph
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.row) {
            RoomQuietTile(glyph: glyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(RoomTokens.Screen2.listName).foregroundStyle(RoomTokens.Ink.graphite)
                if let detail {
                    Text(detail).font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: RoomTokens.Screen2.listRow, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The list row hover (mockup `.li:hover`): a quiet wash in a 10 pt rounded rectangle, 120 ms.
private struct RoomRowHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? RoomTokens.Surface.hover : Color.clear, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
            .onHover { inside in withAnimation(RoomTokens.Motion.hover) { hovering = inside } }
    }
}

extension View {
    func roomRowHover() -> some View { modifier(RoomRowHover()) }
}

/// The mockup's switch (`.sw`): a 36 x 22 track, quiet when off and the accent when on, with a white knob that travels
/// on the UI spring. Works the same in a key or a background window.
struct RoomSwitchStyle: ToggleStyle {
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? accent.fill : RoomTokens.Surface.tile)
                    .overlay(Capsule().strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
                Circle().fill(RoomTokens.Surface.onTile)
                    .shadow(color: RoomTokens.Surface.tileShadow, radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: RoomTokens.Screen2.switchWidth, height: RoomTokens.Screen2.switchHeight)
            .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: on)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A list row whose secondary link shows on hover or focus (mockup `.li:hover .lnk`), with the row's hover wash.
struct RoomHoverReveal<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        content(hovering || focused)
            .animation(RoomTokens.Motion.hover, value: hovering)
            .padding(.horizontal, RoomTokens.Space.row)
            .background(hovering ? RoomTokens.Surface.hover : Color.clear, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
            .padding(.horizontal, -RoomTokens.Space.row)
            .focused($focused)
            .onHover { inside in withAnimation(RoomTokens.Motion.hover) { hovering = inside } }
    }
}
