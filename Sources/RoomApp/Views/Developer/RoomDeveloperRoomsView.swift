import AppKit
import RoomCore
import SwiftUI

struct RoomDeveloperRoomsView: View {
    let summary: RoomDevSummary
    let unreferenced: RoomDevUnreferenced
    @Environment(\.roomAccent) private var accent
    @AppStorage(RoomDevUnreferenced.preferenceKey) private var threshold = RoomDevUnreferenced.defaultThreshold
    @State private var sort: Sort = .size
    @State private var onlyOrphans = false
    @State private var showingExplanation = false
    @State private var selectedSegment: String?

    private enum Sort: String, CaseIterable { case size = "Size", name = "Name" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                figure("Pinned by \(summary.pinnedProjectCount) \(summary.pinnedProjectCount == 1 ? "project" : "projects")", summary.pinnedBytes)
                figure("Not in any room", summary.orphanBytes)
                figure("Shared by two rooms, counted once", summary.sharedBytes)
            }
            HStack {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                Toggle("Only not in any room", isOn: $onlyOrphans)
                Spacer()
            }
            if !onlyOrphans { projects }
            orphans
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What each project pins").fontWeight(.semibold)
                Spacer()
                Text("Read from wrappers, libs.versions.toml and Xcode schemes")
                    .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(RoomDevPinKind.allCases, id: \.self) { kind in
                    Label { Text(kind.title) } icon: {
                        Circle().fill(color(kind)).frame(width: 7, height: 7)
                    }
                }
            }.font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            if summary.rows.isEmpty {
                Text("No supported projects found in the chosen folders.").foregroundStyle(.secondary)
            }
            let largest = summary.rows.map(\.totalBytes).max() ?? 0
            ForEach(rows, id: \.project.id) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.project.name).fontWeight(.semibold).lineLimit(1)
                        if !row.kindLine.isEmpty {
                            Text(row.kindLine).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                        }
                    }.frame(width: 155, alignment: .leading)
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(Array(row.segments.enumerated()), id: \.offset) { index, segment in
                                segmentButton(segment, id: "\(row.project.id):\(index)")
                                    .frame(width: max(geometry.size.width * 0.015,
                                                      geometry.size.width * Double(segment.bytes) / Double(max(1, largest))))
                            }
                        }
                    }.frame(height: 20)
                    Text(row.totalBytes > 0 ? measured(row.totalBytes, partial: row.partial || summary.partial) : "—")
                        .monospacedDigit().fontWeight(.semibold).frame(width: 85, alignment: .trailing)
                }
            }
            Text("Android Gradle Plugin versions live inside the shared Gradle module cache, so they add no bar of their own.")
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
        }.font(RoomTokens.Typography.body)
    }

    private var orphans: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Not in any room").fontWeight(.semibold)
                Spacer()
                Text("No reference does not mean unused.").foregroundStyle(.secondary)
                Button("Why?") { showingExplanation.toggle() }
                    .buttonStyle(.plain).foregroundStyle(accent.text)
                    .popover(isPresented: $showingExplanation) {
                        Text("Another project may use these versions. Room can link only the projects and version files in the folders you chose.")
                            .frame(width: 250, alignment: .leading).padding(14)
                    }
            }
            Text("\(measured(summary.orphanBytes, partial: summary.partial)) · no selected project refers to these")
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            let largest = summary.orphans.map { $0.artifact.bytes }.max() ?? 1
            ForEach(orphanRows, id: \.artifact.id) { row in
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.artifact.version).fontWeight(.medium).lineLimit(1)
                        Text(row.artifact.kind.title).font(RoomTokens.Typography.micro).foregroundStyle(.secondary)
                    }.frame(width: 142, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.reason.text).foregroundStyle(.secondary)
                        if let caption = RoomDevUnreferenced.caption(since: unreferenced.since[row.artifact.key],
                                                                     now: Date(), thresholdDays: threshold) {
                            Text(caption).font(RoomTokens.Typography.micro).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Capsule().fill(RoomTokens.Surface.used)
                        .frame(width: 90 * Double(row.artifact.bytes) / Double(max(1, largest)), height: 5)
                        .frame(width: 90, alignment: .leading).accessibilityHidden(true)
                    Text(measured(row.artifact.bytes, partial: row.artifact.partial || summary.partial))
                        .monospacedDigit().frame(width: 80, alignment: .trailing)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.artifact.path)])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show \(row.artifact.version) in Finder")
                }.padding(.vertical, 4)
                Divider()
            }
        }.font(RoomTokens.Typography.body)
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
        return Button { selectedSegment = id } label: {
            Rectangle().fill(segment.countedEarlier ? .clear : color(segment.kind))
                .overlay {
                    if segment.countedEarlier {
                        Canvas { context, size in
                            var lines = Path()
                            for x in stride(from: -size.height, through: size.width, by: 4) {
                                lines.move(to: CGPoint(x: x, y: size.height))
                                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                            }
                            context.stroke(lines, with: .color(RoomTokens.Surface.hatch), lineWidth: 1)
                        }.clipped()
                    }
                }
                .overlay {
                    if segment.countedEarlier || segment.kind == .gradle {
                        Rectangle().strokeBorder(RoomTokens.Surface.used, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(detail)
        .accessibilityLabel(detail + (segment.countedEarlier ? ", counted in another room" : ""))
        .popover(isPresented: Binding(get: { selectedSegment == id }, set: { if !$0 { selectedSegment = nil } })) {
            Text(detail).padding(12)
        }
    }

    private func color(_ kind: RoomDevPinKind) -> Color {
        switch kind {
        case .derivedData: accent.fill
        case .ndk: RoomTokens.Surface.used
        case .kotlinNative: RoomTokens.Ink.secondary
        case .gradle: RoomTokens.Surface.line2
        }
    }

    private func figure(_ label: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            Text(measured(bytes, partial: summary.partial)).font(RoomTokens.Typography.figure).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func measured(_ bytes: Int64, partial: Bool) -> String {
        (partial ? "≥ " : "") + RoomFormat.bytes(bytes)
    }
}
