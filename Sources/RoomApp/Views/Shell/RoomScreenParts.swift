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

/// The real icon of a thing a row names (an app, a project folder, a cache place) from NSWorkspace. Hide replaces it
/// with a blank tile; a missing path falls back to a quiet glyph tile.
struct RoomThingIcon: View {
    let path: String?
    var fallback: RoomGlyph = .folder
    var size: CGFloat = RoomTokens.Screen2.icon
    @Environment(\.roomHide) private var hide

    var body: some View {
        Group {
            if hide.masksNow {
                RoundedRectangle(cornerRadius: RoomTokens.Screen2.iconRadius * size / RoomTokens.Screen2.icon)
                    .fill(RoomTokens.Surface.tile)
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

/// NSWorkspace icons are cheap but not free; rows redraw often while a scan counts.
@MainActor final class RoomThingIconCache {
    static let shared = RoomThingIconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let icon = icons[path] { return icon }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
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
