import Observation
import RoomCore
import SwiftUI

nonisolated struct RoomMapReadoutContent: Equatable {
    let title: String
    let detail: String?
    var isHint = false

    static func make(level: RoomTreeNode, hovered: RoomMapItem?, selectedPath: String?, hidden: Bool,
                     showsHint: Bool, showsCleanupTarget: Bool = false, format: (Int64) -> String) -> Self {
        if !showsCleanupTarget, let hovered, node(at: hovered.parentID, inside: level) != nil {
            let name = hovered.isOther ? "Other" : hovered.name
            return measured(name, bytes: hovered.bytes, partial: hovered.isPartial, parent: level,
                            hidden: hidden, isOther: hovered.isOther, format: format)
        }
        if let selectedPath, let selection = node(at: selectedPath, inside: level) {
            return measured(selection.name, bytes: selection.allocatedBytes, partial: selection.isPartial,
                            parent: level,
                            hidden: hidden, format: format)
        }
        if showsHint && !showsCleanupTarget {
            return Self(title: "Bigger tile, more space. Hover to read it. Click a folder header to step inside.",
                        detail: nil, isHint: true)
        }
        return measured(level.name, bytes: level.allocatedBytes, partial: level.isPartial, parent: nil,
                        hidden: hidden, format: format)
    }

    static func node(at path: String, inside level: RoomTreeNode) -> RoomTreeNode? {
        if path == level.relativePath { return level }
        if level.relativePath.isEmpty { return level.descendant(at: path) }
        let prefix = level.relativePath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return level.descendant(at: String(path.dropFirst(prefix.count)))
    }

    private static func measured(_ name: String, bytes: Int64, partial: Bool, parent: RoomTreeNode?,
                                 hidden: Bool, isOther: Bool = false, format: (Int64) -> String) -> Self {
        if hidden { return Self(title: isOther ? "Other" : "Name hidden", detail: "Size hidden") }
        let amount = (partial ? "≥ " : "") + format(bytes)
        guard let parent, parent.allocatedBytes > 0 else { return Self(title: name, detail: amount) }
        let proportion = Double(bytes) / Double(parent.allocatedBytes)
        let share = proportion.formatted(.percent.precision(.fractionLength(0)))
        return Self(title: name, detail: "\(amount) · \(share) of \(parent.name)")
    }
}

@Observable @MainActor
final class RoomMapPointer {
    var item: RoomMapItem?
}

struct RoomMapContextReadout: View {
    let level: RoomTreeNode
    let pointer: RoomMapPointer
    let selectedPath: String?
    let hidden: Bool
    let showsHint: Bool
    let showsCleanupTarget: Bool

    var body: some View {
        let content = RoomMapReadoutContent.make(level: level, hovered: showsCleanupTarget ? nil : pointer.item,
            selectedPath: selectedPath, hidden: hidden, showsHint: showsHint, showsCleanupTarget: showsCleanupTarget,
            format: RoomFormat.bytes)
        RoomMapReadout(title: content.title, detail: content.detail, isHint: content.isHint)
    }
}

struct RoomMapReadout: View {
    let title: String
    let detail: String?
    var isHint = false

    var body: some View {
        HStack(spacing: RoomTokens.Space.row) {
            Text(title)
                .font(isHint ? RoomTokens.Typography.caption : RoomTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(isHint ? RoomTokens.Ink.secondary : RoomTokens.Ink.graphite)
                .lineLimit(isHint ? 2 : 1)
            Spacer(minLength: RoomTokens.Space.row)
            if let detail {
                Text(detail)
                    .font(RoomTokens.Typography.caption.monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .frame(minHeight: RoomTokens.Map.readoutHeight)
        .padding(.horizontal, RoomTokens.Space.row)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
        .accessibilityElement(children: .combine)
    }
}

struct RoomLargestTable: View {
    let level: RoomTreeNode
    let hidden: Bool
    var selection: String? = nil
    let select: (String) -> Void

    var body: some View {
        let result = RoomLargest.rows(in: level)
        ScrollView {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Text(hidden ? "Largest items" : "Largest \(result.rows.count) of \(result.itemCount.formatted()) items")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, row in
                    Button { select(row.id) } label: {
                        HStack {
                            Text("\(index + 1)").font(RoomTokens.Typography.micro)
                                .foregroundStyle(RoomTokens.Ink.secondary)
                            Text(hidden ? "Name hidden" : row.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let kind = row.kind.flatMap(StorageKind.init(rawValue:)) {
                                Text(kind.title).foregroundStyle(RoomTokens.Ink.secondary)
                            }
                            Text(hidden ? "Hidden" : (row.isPartial ? "≥ " : "") + RoomFormat.bytes(row.bytes))
                                .monospacedDigit()
                        }
                        .font(RoomTokens.Typography.body)
                        .frame(minHeight: RoomTokens.Map.largestRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RoomHoverButtonStyle(isActive: selection == row.id))
                    .accessibilityAddTraits(selection == row.id ? .isSelected : [])
                }
            }
            .padding(RoomTokens.Space.row)
        }
        .accessibilityIdentifier("RoomDiskMapLargestTable")
    }
}

struct RoomMapCleanupControl: View {
    let action: RoomMapCleanupAction
    let activate: () -> Void
    @Environment(\.roomAccent) private var accent

    var body: some View {
        Group {
            switch action {
            case .check:
                button("Check Caches", symbol: "magnifyingglass")
                    .help("Check for eligible caches in Room’s cache locations, then review items in this selection.")
            case .checking:
                ProgressView("Checking caches…").controlSize(.small)
            case .review:
                button("Review Cleanup", symbol: "checklist")
                    .help("Review the clearable cache items inside this selection.")
            case .empty:
                button("Check Again", symbol: "arrow.clockwise")
                    .help("The last check found no clearable caches here.")
            }
        }
        .font(RoomTokens.Typography.caption)
        .foregroundStyle(RoomTokens.Ink.secondary)
        .fixedSize()
    }

    private func button(_ title: String, symbol: String) -> some View {
        Button(action: activate) { Label(title, systemImage: symbol) }
            .buttonStyle(.glassProminent)
            .tint(accent.fill)
            .controlSize(.regular)
            .accessibilityIdentifier("RoomDiskMapCleanup")
    }
}

struct RoomMapKindControl: View {
    let node: RoomTreeNode
    let hidden: Bool
    @Binding var filter: String?
    @Environment(\.roomMotion) private var motion
    @State private var hoveredKind: String?

    var body: some View {
        let totals = RoomKindStrip.totals(node)
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                bar(totals)
                ViewThatFits(in: .horizontal) {
                    legend(totals).fixedSize()
                    ScrollView(.horizontal) { legend(totals) }
                        .scrollIndicators(.hidden)
                }
            }
            .onChange(of: node.relativePath) { _, _ in hoveredKind = nil }
        }
    }

    private func bar(_ totals: [(kind: String, bytes: Int64)]) -> some View {
        GeometryReader { geometry in
            HStack(spacing: RoomKindStrip.barGap) {
                ForEach(RoomKindStrip.bar(totals, width: geometry.size.width), id: \.kind) { part in
                    Button { toggle(part.kind) } label: {
                        RoundedRectangle(cornerRadius: RoomTokens.Radius.tile)
                            .fill(color(part.kind))
                            .opacity(opacity(part.kind))
                            .frame(width: part.width)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kindLabel(part.kind, totals: totals))
                    .accessibilityAddTraits(filter == part.kind ? .isSelected : [])
                    .onHover { trackHover(part.kind, inside: $0) }
                }
            }
        }
        .frame(height: RoomTokens.Map.kindBarHeight)
        .animation(motion.animation(RoomTokens.Motion.fade, fallback: nil), value: hoveredKind)
    }

    private func legend(_ totals: [(kind: String, bytes: Int64)]) -> some View {
        let legend = RoomKindStrip.legend(totals)
        return HStack(spacing: RoomTokens.Space.inner) {
            ForEach(legend.shown, id: \.self) { kind in
                Button { toggle(kind) } label: {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: RoomTokens.Radius.budgetFill)
                            .fill(color(kind))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(kindName(kind)).foregroundStyle(RoomTokens.Ink.secondary)
                        if let amount = amount(kind, totals: totals) {
                            Text(amount).monospacedDigit().foregroundStyle(RoomTokens.Ink.graphite)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kindLabel(kind, totals: totals))
                .accessibilityAddTraits(filter == kind ? .isSelected : [])
                .onHover { trackHover(kind, inside: $0) }
            }
            if legend.more > 0 {
                Menu("+\(legend.more)") {
                    ForEach(totals.filter { !legend.shown.contains($0.kind) }, id: \.kind) { item in
                        Button(kindLabel(item.kind, totals: totals)) { toggle(item.kind) }
                    }
                }
                .accessibilityLabel("\(legend.more) more storage kinds")
            }
            if let filter {
                Button("Clear \(kindName(filter))", systemImage: "xmark.circle", action: { self.filter = nil })
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
            }
        }
        .font(RoomTokens.Typography.caption)
    }

    private func color(_ kind: String) -> Color {
        RoomTokens.Kind(rawValue: kind)?.mark ?? RoomTokens.Surface.used
    }

    private func kindName(_ kind: String) -> String {
        StorageKind(rawValue: kind)?.title ?? "Other"
    }

    private func amount(_ kind: String, totals: [(kind: String, bytes: Int64)]) -> String? {
        guard !hidden, let value = totals.first(where: { $0.kind == kind })?.bytes else { return nil }
        return (node.isPartial ? "≥ " : "") + RoomFormat.bytes(value)
    }

    private func kindLabel(_ kind: String, totals: [(kind: String, bytes: Int64)]) -> String {
        [kindName(kind), amount(kind, totals: totals)].compactMap { $0 }.joined(separator: ", ")
    }

    private func opacity(_ kind: String) -> Double {
        if let hoveredKind { return kind == hoveredKind ? 1 : RoomTokens.Map.kindHoverOpacity }
        return filter == nil || filter == kind ? 1 : RoomTokens.Map.pendingGroupOpacity
    }

    private func trackHover(_ kind: String, inside: Bool) {
        if inside { hoveredKind = kind }
        else if hoveredKind == kind { hoveredKind = nil }
    }

    private func toggle(_ kind: String) { filter = filter == kind ? nil : kind }
}
