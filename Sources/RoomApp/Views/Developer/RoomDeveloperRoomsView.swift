import AppKit
import RoomCore
import SwiftUI

struct RoomDeveloperRoomsView: View {
    let summary: RoomDevSummary
    let unreferenced: RoomDevUnreferenced
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @AppStorage(RoomDevUnreferenced.preferenceKey) private var threshold = RoomDevUnreferenced.defaultThreshold
    @State private var sort: Sort = .size
    @State private var onlyOrphans = false
    @State private var showingExplanation = false
    @State private var highlightedKind: RoomDevPinKind?
    @State private var selectedSegment: String?
    @State private var hoveredProject: String?

    private enum Sort: String, CaseIterable { case size = "Size", name = "Name" }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            resultControls
            Group {
                if !onlyOrphans { projects }
            }
            .roomPanelChange(onlyOrphans)
            orphans
        }
    }

    private var resultControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.group) {
                sortPicker.fixedSize()
                Spacer(minLength: 0)
                orphanToggle.fixedSize()
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                sortPicker
                orphanToggle
            }
        }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sort) {
            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .controlSize(.small)
    }

    private var orphanToggle: some View {
        Toggle("Only not in any room", isOn: $onlyOrphans)
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private var projects: some View {
        RoomDeveloperGroup(title: "What each project pins",
                           caption: "Read from Gradle wrappers, version catalogs, and Xcode schemes.") {
            if summary.rows.isEmpty {
                Text("No supported projects found in the chosen folders. Check that you chose the folder that holds your projects.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                let fractions = Dictionary(zip(summary.rows.map(\.project.id),
                    RoomDeveloperList.barFractions(summary.rows.map(\.totalBytes))), uniquingKeysWith: { first, _ in first })
                let kinds = Set(summary.rows.flatMap(\.segments).map(\.kind))
                if !kinds.isEmpty { legend(kinds) }
                RoomDeveloperRowList(items: rows.map { IdentifiedProject(row: $0) }) { item in
                    projectRow(item.row, fractions: fractions)
                }
                if summary.sharedBytes > 0 {
                    RoomMaskable("Shared across projects: \(RoomDeveloperFormat.whole(summary.sharedBytes, partial: summary.partial)), counted once.")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                if !kinds.isEmpty {
                    Text("AGP versions live in the shared Gradle cache.")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
        }
    }

    private struct IdentifiedProject: Identifiable {
        let row: RoomDevProjectRow
        var id: String { row.project.id }
    }

    private struct IdentifiedOrphan: Identifiable {
        let artifact: DeveloperToolchainResource
        let reason: RoomDevOrphanReason
        var id: String { artifact.id }
    }

    private func legend(_ kinds: Set<RoomDevPinKind>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: RoomTokens.Space.row)],
                  alignment: .leading, spacing: RoomTokens.Space.row) {
            ForEach(RoomDevPinKind.allCases.filter(kinds.contains), id: \.self) { kind in
                let active = highlightedKind == kind
                Button {
                    highlightedKind = active ? nil : kind
                } label: {
                    HStack(spacing: RoomTokens.Space.tight) {
                        Circle().fill(color(kind)).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(kind.legendTitle).lineLimit(1)
                    }
                    .font(RoomTokens.Typography.caption)
                    .padding(.horizontal, RoomTokens.Space.row)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RoomHoverButtonStyle(isActive: active))
                .help(active ? "Show all toolchains" : "Highlight \(kind.title)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private func projectRow(_ row: RoomDevProjectRow, fractions: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
                    RoomMaskable(row.project.name, kind: .name)
                        .font(RoomTokens.Typography.section)
                        .lineLimit(1)
                        .help(hide.masksNow ? "Project name hidden" : row.project.name)
                    if !row.kindLine.isEmpty {
                        Text(row.kindLine)
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                }
                Spacer(minLength: 0)
                RoomMaskable(row.totalBytes > 0 ? RoomDeveloperFormat.whole(row.totalBytes, partial: row.partial || summary.partial) : "—")
                    .font(RoomTokens.Typography.numeric)
                    .fixedSize()
            }
            if !row.segments.isEmpty { toolchainBar(row, fractions: fractions) }
        }
        .padding(.horizontal, RoomTokens.Space.inner)
        .padding(.vertical, RoomTokens.Space.row)
        .frame(minHeight: RoomTokens.Developer.rowMinHeight)
        .background(RoomTokens.Surface.hover.opacity(hoveredProject == row.project.id ? 1 : 0), in: .rect(cornerRadius: RoomTokens.Radius.row))
        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: hoveredProject)
        .onHover { hoveredProject = $0 ? row.project.id : (hoveredProject == row.project.id ? nil : hoveredProject) }
    }

    private func toolchainBar(_ row: RoomDevProjectRow, fractions: [String: Double]) -> some View {
        let fraction = fractions[row.project.id] ?? 1
        let portions = row.segments.map { max(0.015, Double($0.bytes)) }
        let total = max(1, portions.reduce(0, +))
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(row.segments.enumerated()), id: \.offset) { index, segment in
                    segmentButton(segment, id: "\(row.project.id):\(index)")
                        .frame(width: geometry.size.width * fraction * portions[index] / total)
                }
                Spacer(minLength: 0)
            }
            .clipShape(.rect(cornerRadius: RoomTokens.Radius.tile))
        }
        .frame(height: 20)
    }

    private var orphans: some View {
        RoomDeveloperGroup(title: "Not in any room",
                           caption: summary.orphans.isEmpty ? nil : "No reference does not mean unused. Room never removes these for you.",
                           trailing: { if !summary.orphans.isEmpty { referenceExplanation.fixedSize() } }) {
            if summary.orphans.isEmpty {
                Text("No unreferenced toolchains found in these folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                let groups = RoomDeveloperList.grouped(orphanRows.map { IdentifiedOrphan(artifact: $0.artifact, reason: $0.reason) },
                    key: { $0.artifact.kind.title }, bytes: { $0.artifact.bytes }, name: { $0.artifact.version })
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    ForEach(sort == .name ? [RoomDeveloperList.Group(key: "", bytes: 0, items: orphanRows.map { IdentifiedOrphan(artifact: $0.artifact, reason: $0.reason) })] : groups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
                            if groups.count > 1, sort == .size {
                                HStack {
                                    Text(group.key).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                    Spacer(minLength: 0)
                                    RoomMaskable(RoomDeveloperFormat.whole(group.bytes, partial: summary.partial))
                                        .font(RoomTokens.Typography.captionNumeric).foregroundStyle(RoomTokens.Ink.secondary)
                                }
                                .padding(.horizontal, RoomTokens.Space.inner)
                            }
                            RoomDeveloperRowList(items: group.items, limit: 5) { item in
                                orphanRow(artifact: item.artifact, reason: item.reason)
                            }
                        }
                    }
                }
            }
        }
    }

    private var referenceExplanation: some View {
        Button {
            showingExplanation.toggle()
        } label: {
            Label("About references", systemImage: "info.circle")
                .font(RoomTokens.Typography.caption)
        }
        .roomLink(accent)
        .popover(isPresented: $showingExplanation) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Text("A version can still be in use.")
                    .font(RoomTokens.Typography.section)
                Text("Room can only link projects in the folders you choose. Other projects may use these versions.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .frame(width: 232, alignment: .leading)
            .padding(RoomTokens.Space.group)
        }
    }

    private func orphanRow(artifact: DeveloperToolchainResource, reason: RoomDevOrphanReason) -> some View {
        let age = RoomDevUnreferenced.caption(since: unreferenced.since[artifact.key], now: Date(), thresholdDays: threshold)
        return RoomDeveloperRow(title: artifact.version, titleKind: artifact.kind == .derivedData ? .name : .figure,
                                subtitle: artifact.kind.title + " · " + reason.text, subtitleKind: .figure,
                                note: age,
                                bytes: artifact.bytes, partial: artifact.partial || summary.partial,
                                finderURL: URL(fileURLWithPath: artifact.path))
    }

    private var rows: [RoomDevProjectRow] {
        switch sort {
        case .size: summary.rows.sorted {
            if $0.totalBytes == $1.totalBytes { return $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
            return $0.totalBytes > $1.totalBytes
        }
        case .name: summary.rows.sorted { $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
        }
    }

    private var orphanRows: [(artifact: DeveloperToolchainResource, reason: RoomDevOrphanReason)] {
        switch sort {
        case .size: summary.orphans
        case .name: summary.orphans.sorted { $0.artifact.version.localizedStandardCompare($1.artifact.version) == .orderedAscending }
        }
    }

    private func segmentButton(_ segment: RoomDevSegment, id: String) -> some View {
        let detail = "\(segment.kind.title) \(segment.version) · \(measured(segment.bytes, partial: segment.partial))"
        let dimmed = highlightedKind.map { $0 != segment.kind } ?? false
        return Button { selectedSegment = id } label: {
            Rectangle()
                .fill(segment.countedEarlier ? .clear : color(segment.kind))
                .overlay {
                    if segment.countedEarlier { sharedHatch }
                    if segment.countedEarlier || segment.kind == .gradle {
                        Rectangle().strokeBorder(RoomTokens.Surface.used, lineWidth: 1)
                    }
                }
                .opacity(dimmed ? 0.32 : 1)
                .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: dimmed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hide.masksNow ? segment.kind.title + " · hidden" : detail)
        .accessibilityLabel((hide.masksNow ? segment.kind.title + ", hidden" : detail)
                            + (segment.countedEarlier ? ", counted in another room" : ""))
        .popover(isPresented: Binding(get: { selectedSegment == id }, set: { if !$0 { selectedSegment = nil } })) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Label {
                    Text(segment.kind.title)
                } icon: {
                    Circle().fill(color(segment.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                .font(RoomTokens.Typography.section)
                RoomMaskable(segment.version, kind: segment.kind == .derivedData ? .name : .figure)
                    .font(RoomTokens.Typography.version)
                RoomMaskable(measured(segment.bytes, partial: segment.partial))
                    .font(RoomTokens.Typography.figure)
                if segment.countedEarlier {
                    Text("Shared storage. Counted once in the totals.")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            .padding(RoomTokens.Space.group)
        }
    }

    private var sharedHatch: some View {
        Canvas { context, size in
            var lines = Path()
            for x in stride(from: -size.height, through: size.width, by: 4) {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(lines, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
        }
        .clipped()
    }

    private func color(_ kind: RoomDevPinKind) -> Color {
        switch kind {
        case .derivedData: accent.fill
        case .ndk: RoomTokens.Surface.used
        case .kotlinNative: RoomTokens.Ink.secondary
        case .gradle: RoomTokens.Surface.line2
        }
    }

    private func measured(_ bytes: Int64, partial: Bool) -> String {
        (partial ? "≥ " : "") + RoomFormat.bytes(bytes)
    }
}
