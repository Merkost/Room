import RoomCore
import SwiftUI

struct RoomMapReadout: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: RoomTokens.Space.row) {
            Text(title).font(RoomTokens.Typography.caption.weight(.semibold))
            Spacer(minLength: RoomTokens.Space.row)
            if let detail {
                Text(detail)
                    .font(RoomTokens.Typography.path)
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(RoomTokens.Space.row)
        }
        .accessibilityIdentifier("RoomDiskMapLargestTable")
    }
}

struct RoomMapKindControl: View {
    let node: RoomTreeNode
    let hidden: Bool
    @Binding var filter: String?
    @AppStorage("RoomDiskKindStyle") private var style = "bar"

    var body: some View {
        let totals = RoomKindStrip.totals(node)
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                HStack {
                    Picker("Kind strip", selection: $style) {
                        Text("Bar").tag("bar")
                        Text("Dots").tag("dots")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if filter != nil {
                        Button("All kinds") { filter = nil }.buttonStyle(.borderless)
                    }
                }
                if style == "dots" {
                    dotStrip(totals)
                } else {
                    GeometryReader { geometry in
                        HStack(spacing: RoomKindStrip.barGap) {
                            ForEach(RoomKindStrip.bar(totals, width: geometry.size.width), id: \.kind) { part in
                                Button { toggle(part.kind) } label: {
                                    RoundedRectangle(cornerRadius: RoomTokens.Radius.tile)
                                        .fill(color(part.kind))
                                        .opacity(filter == nil || filter == part.kind ? 1 : RoomTokens.Map.pendingGroupOpacity)
                                        .frame(width: part.width)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(kindLabel(part.kind, totals: totals))
                            }
                        }
                    }
                    .frame(height: RoomTokens.Map.kindBarHeight)
                }
                let legend = RoomKindStrip.legend(totals)
                HStack(spacing: RoomTokens.Space.row) {
                    ForEach(legend.shown, id: \.self) { kind in
                        Button { toggle(kind) } label: {
                            Label(StorageKind(rawValue: kind)?.title ?? "Other", systemImage: "circle.fill")
                                .foregroundStyle(color(kind))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(kindLabel(kind, totals: totals))
                    }
                    if legend.more > 0 {
                        Menu("+\(legend.more)") {
                            ForEach(totals.filter { !legend.shown.contains($0.kind) }, id: \.kind) { amount in
                                Button(kindLabel(amount.kind, totals: totals)) { toggle(amount.kind) }
                            }
                        }
                    }
                }
                .font(RoomTokens.Typography.caption)
            }
        }
    }

    private func dotStrip(_ parts: [(kind: String, bytes: Int64)]) -> some View {
        let field = RoomKindStrip.dots(parts)
        let kinds = parts.flatMap { part in
            Array(repeating: part.kind, count: min(field.counts[part.kind] ?? 0, RoomTokens.Budget.maxDots))
        }.prefix(RoomTokens.Budget.maxDots)
        return Canvas { context, size in
            guard field.columns > 0 else { return }
            let step = min(RoomKindStrip.DotField.pitch, size.width / CGFloat(field.columns))
            let radius = min(RoomKindStrip.DotField.radius, step / 2)
            for (index, kind) in kinds.enumerated() {
                let x = CGFloat(index / RoomKindStrip.DotField.rows) * step
                let y = CGFloat(index % RoomKindStrip.DotField.rows) * RoomKindStrip.DotField.pitch
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color(kind)))
            }
        }
        .frame(height: field.size.height)
        .accessibilityHidden(true)
    }

    private func color(_ kind: String) -> Color {
        RoomTokens.Kind(rawValue: kind)?.mark ?? RoomTokens.Surface.used
    }

    private func kindLabel(_ kind: String, totals: [(kind: String, bytes: Int64)]) -> String {
        let name = StorageKind(rawValue: kind)?.title ?? "Other"
        guard !hidden, let value = totals.first(where: { $0.kind == kind })?.bytes else { return name }
        return name + ", " + RoomFormat.bytes(value)
    }

    private func toggle(_ kind: String) { filter = filter == kind ? nil : kind }
}
