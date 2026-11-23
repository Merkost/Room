import SwiftUI

nonisolated struct RoomOverviewCapacityBalance {
    let plan: RoomOverviewPlanInput
    let goal: Int64?

    init(plan: RoomOverviewPlanInput, goal: Int64?) {
        self.plan = plan
        self.goal = goal.flatMap { $0 > 0 && $0 <= plan.capacityBytes ? $0 : nil }
    }

    var usedBytes: Int64 { plan.capacityBytes - plan.freeBytes }
    var usedFraction: Double { Double(usedBytes) / Double(plan.capacityBytes) }
    var goalPosition: Double? { goal.map { 1 - Double($0) / Double(plan.capacityBytes) } }
    var goalDifference: Int64? { goal.map { plan.freeBytes - $0 } }
}

struct RoomOverviewStoragePanel: View {
    let volumeName: String?
    let balance: RoomOverviewCapacityBalance
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    private var hidden: Bool { hide.masksNow }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Label(hidden ? "Storage" : volumeName ?? "Storage", systemImage: "internaldrive")
                .font(RoomTokens.Typography.title)
                .foregroundStyle(RoomTokens.Ink.graphite)
                .lineLimit(1)
                .accessibilityHeading(.h1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: RoomTokens.Space.breath2) {
                    availability.frame(minWidth: 168, idealWidth: 200)
                    breakdown.frame(minWidth: 246)
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    availability
                    breakdown
                }
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.popover))
        .accessibilityIdentifier("RoomOverviewStorage")
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text("Available")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            RoomByteMetric(bytes: balance.plan.freeBytes, maximumSize: 58, hero: true, animatesChanges: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hidden ? "Available space hidden" : "\(RoomFormat.gb(balance.plan.freeBytes, hero: true)) available")
            if let difference = balance.goalDifference {
                HStack(spacing: RoomTokens.Space.tight) {
                    Image(systemName: difference < 0 ? "arrow.down.right" : "checkmark")
                        .accessibilityHidden(true)
                    RoomMaskable(goalStatus(difference))
                }
                .font(RoomTokens.Typography.bodyStrong)
                .foregroundStyle(difference < 0 ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                figure("Used", bytes: balance.usedBytes)
                Spacer(minLength: 0)
                figure("Capacity", bytes: balance.plan.capacityBytes)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                HStack(spacing: 0) {
                    Rectangle().fill(RoomTokens.Surface.used.opacity(0.48))
                        .frame(width: width * balance.usedFraction)
                    Rectangle().fill(accent.fill)
                }
                .clipShape(Capsule())
                .overlay(alignment: .leading) {
                    if let position = balance.goalPosition {
                        Capsule()
                            .fill(RoomTokens.Ink.graphite)
                            .frame(width: 2, height: 18)
                            .offset(x: max(0, min(width - 2, width * position - 1)))
                    }
                }
            }
            .frame(height: 12)
            .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: balance.usedFraction)
            .accessibilityHidden(true)

            HStack(spacing: RoomTokens.Space.inner) {
                key("Used", color: RoomTokens.Surface.used.opacity(0.48))
                key("Available", color: accent.fill)
                if let goal = balance.goal {
                    RoomMaskable("\(RoomFormat.gb(goal)) goal")
                        .font(RoomTokens.Typography.micro)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func goalStatus(_ difference: Int64) -> String {
        if difference < 0 { return "\(RoomFormat.gb(-difference)) below goal" }
        if difference > 0 { return "\(RoomFormat.gb(difference)) above goal" }
        return "At your storage goal"
    }

    private func figure(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text(title).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            RoomMaskable(RoomFormat.gb(bytes))
                .font(RoomTokens.Typography.figure)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func key(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(title).font(RoomTokens.Typography.micro).foregroundStyle(RoomTokens.Ink.secondary)
        }
        .accessibilityHidden(true)
    }
}

struct RoomOverviewStorageMap: View {
    let plan: RoomOverviewPlanInput
    let belowGoal: Bool
    var returnedBytes: Int64 = 0
    let hidden: Bool
    let density: RoomTokens.Density
    let solidKinds: Bool
    let openDiskMap: () -> Void
    let isMapping: Bool
    let isChoosingFolder: Bool
    let mapHome: () -> Void
    let mapAnotherFolder: () -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var hoveredLegend: RoomPlanRoom?
    @State private var hoveredMapRoom: RoomPlanRoom?
    @State private var selection: RoomPlanRoom?

    private typealias Tokens = RoomTokens.OverviewPlan
    private var highlightedRoom: RoomPlanRoom? { hoveredMapRoom ?? hoveredLegend ?? selection }

    var body: some View {
        let rows = RoomOverviewPlanPresentation(plan: plan, hidden: hidden,
            solidKinds: solidKinds && !plan.kindValues.isEmpty, format: RoomFormat.gb).rows
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoomTokens.Space.group) {
                    heading
                    Spacer(minLength: 0)
                    mapActions.fixedSize()
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    heading
                    mapActions
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: RoomTokens.Space.group) {
                    diagram(height: density == .calm ? Tokens.chartHeight : Tokens.compactChartHeight)
                        .frame(minWidth: Tokens.chartMinimumWidth)
                    legend(rows, columns: [GridItem(.flexible())]).frame(width: Tokens.legendWidth)
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    diagram(height: Tokens.compactChartHeight)
                    legend(rows, columns: [GridItem(.adaptive(minimum: Tokens.legendColumnMinimum),
                                                   spacing: RoomTokens.Space.inner)])
                }
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.popover))
        .onChange(of: rows.map(\.id)) { _, valid in
            if let selection, !valid.contains(selection) { self.selection = nil }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text("Storage map").font(RoomTokens.Typography.title).accessibilityHeading(.h2)
            if plan.mapping != nil {
                Text("Categories update as folders finish.").font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private var mapActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.row) {
                mappingMenu
                mapButton
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                mapButton
                mappingMenu
            }
        }
    }

    private var mappingMenu: some View {
        Menu {
            Button("Map Home Again", systemImage: "arrow.clockwise", action: mapHome)
            Button("Map Another Folder…", systemImage: "folder.badge.plus", action: mapAnotherFolder)
        } label: {
            Label("Map again", systemImage: "arrow.clockwise")
        }
        .disabled(isMapping || isChoosingFolder)
        .accessibilityIdentifier("RoomOverviewMapAgain")
    }

    private var mapButton: some View {
        Button(action: openDiskMap) {
            Label("Open Disk Map", systemImage: "arrow.up.right")
                .labelStyle(.titleAndIcon)
        }
        .roomSecondary()
        .accessibilityIdentifier("RoomOverviewOpenDiskMap")
    }

    private func diagram(height: CGFloat) -> some View {
        RoomDotPlanView(plan: plan, belowGoal: belowGoal, returnedBytes: returnedBytes, hidden: hidden,
                        displayHeight: height, density: density, solidKinds: solidKinds,
                        usesExternalLegend: true, legendHighlight: hoveredLegend, selection: $selection,
                        onHoverChange: { hoveredMapRoom = $0 }, openDiskMap: openDiskMap)
    }

    private func legend(_ rows: [RoomOverviewPlanPresentation.Row], columns: [GridItem]) -> some View {
        let ordered = rows.filter { $0.id == .free } + rows.filter {
            if case .kind = $0.id { return true }
            return false
        } + rows.filter { $0.id == .notMapped }
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(ordered) { row in
                legendRow(row)
            }
        }
    }

    private func legendRow(_ row: RoomOverviewPlanPresentation.Row) -> some View {
        let highlighted = highlightedRoom == row.id
        let selected = selection == row.id
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.field)
        return Button {
            selection = selected ? nil : row.id
        } label: {
            HStack(spacing: RoomTokens.Space.row) {
                swatch(row.id).frame(width: Tokens.swatchSize, height: Tokens.swatchSize)
                Text(row.name).lineLimit(1)
                Spacer(minLength: RoomTokens.Space.tight)
                Text(verbatim: row.visualSize)
                    .monospacedDigit().foregroundStyle(RoomTokens.Ink.secondary).fixedSize()
            }
            .font(RoomTokens.Typography.caption)
            .padding(.horizontal, RoomTokens.Space.row)
            .frame(minHeight: Tokens.legendRowHeight)
            .background { shape.fill(RoomTokens.Surface.hover).opacity(highlighted ? 1 : 0) }
            .overlay { shape.strokeBorder(accent.text.opacity(selected ? 0.65 : 0)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: highlighted)
        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: selected)
        .onHover { inside in
            if inside { hoveredLegend = row.id }
            else if hoveredLegend == row.id { hoveredLegend = nil }
        }
        .accessibilityLabel(row.spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func swatch(_ id: RoomPlanRoom) -> some View {
        switch id {
        case .free:
            Circle().strokeBorder(RoomTokens.Ink.secondary, lineWidth: 1.5)
        case .notMapped:
            RoundedRectangle(cornerRadius: RoomTokens.Radius.budgetFill)
                .strokeBorder(RoomTokens.Ink.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        case .kind(let key):
            Circle().fill(RoomTokens.Kind(rawValue: key)?.mark ?? RoomTokens.Ink.secondary)
        }
    }
}
