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

    private enum Sort: String, CaseIterable { case size = "Size", name = "Name" }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            overviewFigures
            resultControls
            Group {
                if !onlyOrphans { projects }
            }
            .roomPanelChange(onlyOrphans)
            orphans
        }
    }

    private var overviewFigures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.row) { figures }
            VStack(spacing: RoomTokens.Space.row) { figures }
        }
    }

    @ViewBuilder private var figures: some View {
        figure("Pinned tools", symbol: "pin", bytes: summary.pinnedBytes,
               projectCount: summary.pinnedProjectCount)
        figure("Not in any room", symbol: "square.dashed", bytes: summary.orphanBytes)
        figure("Shared across projects", symbol: "square.on.square", bytes: summary.sharedBytes,
               note: "Counted once")
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
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("What each project pins")
                    .font(RoomTokens.Typography.title)
                    .accessibilityHeading(.h2)
                Text("Read from Gradle wrappers, version catalogs, and Xcode schemes.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            if summary.rows.isEmpty {
                Text("No supported projects found in the chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                let largest = summary.rows.map(\.totalBytes).max() ?? 0
                let kinds = Set(summary.rows.flatMap(\.segments).map(\.kind))
                if !kinds.isEmpty { legend(kinds) }
                VStack(spacing: RoomTokens.Space.inner) {
                    ForEach(rows, id: \.project.id) { row in
                        projectRow(row, largest: largest)
                    }
                }
                if !kinds.isEmpty {
                    Text("AGP versions live in the shared Gradle cache.")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private func legend(_ kinds: Set<RoomDevPinKind>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: RoomTokens.Space.row)],
                  alignment: .leading, spacing: RoomTokens.Space.row) {
            ForEach(RoomDevPinKind.allCases.filter(kinds.contains), id: \.self) { kind in
                let active = highlightedKind == kind
                Button {
                    highlightedKind = active ? nil : kind
                } label: {
                    HStack(spacing: RoomTokens.Space.tight) {
                        Circle().fill(color(kind)).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(kind.title).lineLimit(2)
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

    private func projectRow(_ row: RoomDevProjectRow, largest: Int64) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
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
                RoomMaskable(row.totalBytes > 0 ? measured(row.totalBytes, partial: row.partial || summary.partial) : "—")
                    .font(RoomTokens.Typography.bodyStrong)
                    .fixedSize()
            }
            if !row.segments.isEmpty { toolchainBar(row, largest: largest) }
        }
        .padding(RoomTokens.Space.inner)
        .background(RoomTokens.Surface.canvas, in: .rect(cornerRadius: RoomTokens.Radius.row))
    }

    private func toolchainBar(_ row: RoomDevProjectRow, largest: Int64) -> some View {
        let portions = row.segments.map { max(0.015, Double($0.bytes) / Double(max(1, largest))) }
        let total = max(1, portions.reduce(0, +))
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(row.segments.enumerated()), id: \.offset) { index, segment in
                    segmentButton(segment, id: "\(row.project.id):\(index)")
                        .frame(width: geometry.size.width * portions[index] / total)
                }
            }
            .clipShape(.rect(cornerRadius: RoomTokens.Radius.tile))
        }
        .frame(height: 20)
    }

    private var orphans: some View {
        let largest = summary.orphans.map { $0.artifact.bytes }.max() ?? 1
        return VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
                Text("Not in any room")
                    .font(RoomTokens.Typography.title)
                    .accessibilityHeading(.h2)
                Spacer(minLength: 0)
                if !summary.orphans.isEmpty { referenceExplanation.fixedSize() }
            }
            if summary.orphans.isEmpty {
                Text("No unreferenced toolchains found in these folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                VStack(spacing: RoomTokens.Space.row) {
                    ForEach(orphanRows, id: \.artifact.id) { row in
                        orphanRow(artifact: row.artifact, reason: row.reason, largest: largest)
                    }
                }
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
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

    private func orphanRow(artifact: DeveloperToolchainResource, reason: RoomDevOrphanReason, largest: Int64) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            HStack(spacing: RoomTokens.Space.inner) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    RoomMaskable(artifact.version, kind: artifact.kind == .derivedData ? .name : .figure)
                        .font(RoomTokens.Typography.section)
                        .lineLimit(1)
                    Text(artifact.kind.title)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                Spacer(minLength: 0)
                RoomMaskable(measured(artifact.bytes, partial: artifact.partial || summary.partial))
                    .font(RoomTokens.Typography.bodyStrong)
                    .fixedSize()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artifact.path)])
                } label: {
                    Image(systemName: "arrow.up.forward.app").frame(width: 28, height: 28)
                }
                .buttonStyle(RoomHoverButtonStyle())
                .help("Show in Finder")
                .accessibilityLabel("Show \(hide.masksNow ? "version" : artifact.version) in Finder")
            }
            Text(reason.text).foregroundStyle(RoomTokens.Ink.secondary)
            if let caption = RoomDevUnreferenced.caption(since: unreferenced.since[artifact.key],
                                                         now: Date(), thresholdDays: threshold) {
                RoomMaskable(caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
            GeometryReader { geometry in
                Capsule().fill(color(artifact.kind))
                    .frame(width: geometry.size.width * Double(artifact.bytes) / Double(max(1, largest)))
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .font(RoomTokens.Typography.caption)
        .padding(RoomTokens.Space.inner)
        .background(RoomTokens.Surface.canvas, in: .rect(cornerRadius: RoomTokens.Radius.row))
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

    private func figure(_ label: String, symbol: String, bytes: Int64, projectCount: Int? = nil,
                        note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Label(label, systemImage: symbol)
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            RoomMaskable(measured(bytes, partial: summary.partial))
                .font(RoomTokens.Typography.figure)
                .fixedSize()
            if let projectCount {
                RoomMaskable("\(projectCount) \(projectCount == 1 ? "project" : "projects")")
                    .font(RoomTokens.Typography.micro)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else if let note {
                Text(note)
                    .font(RoomTokens.Typography.micro)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(minWidth: 128, maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
        .accessibilityElement(children: .combine)
    }

    private func measured(_ bytes: Int64, partial: Bool) -> String {
        (partial ? "≥ " : "") + RoomFormat.bytes(bytes)
    }
}
