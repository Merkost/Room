import AppKit
import RoomCore
import SwiftUI

struct RoomBlueprintInspector: View {
    let blueprint: RoomBlueprint
    let hidden: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Text("Measured so far").font(RoomTokens.Typography.title).accessibilityAddTraits(.isHeader)
                if hidden {
                    Text("Details hidden").foregroundStyle(RoomTokens.Ink.secondary)
                } else {
                    Text(blueprint.counter(files: { $0.formatted() }, bytes: RoomFormat.bytes))
                        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    ForEach(blueprint.drawn.reversed(), id: \.name) { room in
                        HStack {
                            Text(room.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: RoomTokens.Space.tight)
                            Text((room.isPartial ? "≥ " : "") + RoomFormat.bytes(room.bytes))
                                .monospacedDigit().fixedSize()
                        }
                        .font(RoomTokens.Typography.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RoomTokens.Space.group)
        }
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        .accessibilityIdentifier("RoomDiskMapInspector")
    }
}

struct RoomMapInspector: View {
    let node: RoomTreeNode?
    let url: URL?
    var parent: RoomTreeNode?
    var pin: ((URL) -> Void)?
    let showSizes: Bool
    let isScanning: Bool
    let analysis: StorageAnalysisReport?
    let analysisStatus: String?
    let isAnalyzing: Bool
    let canAnalyze: Bool
    let stepIn: () -> Void
    let map: () -> Void
    let rescan: () -> Void
    let inspect: () -> Void
    @State private var showsReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                if let node {
                    let kind = StorageKind.dominant(node.kindBytes)
                    Text([node.isDirectory ? "Folder" : "File", kind?.title].compactMap { $0 }.joined(separator: " · "))
                        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    Text(showSizes ? node.name : "Name hidden")
                        .font(RoomTokens.Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    if showSizes {
                        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
                            if node.isPartial { Text("≥").font(RoomTokens.Typography.figure) }
                            RoomByteMetric(bytes: node.allocatedBytes, maximumSize: 26)
                        }
                    } else {
                        Text("Size hidden").font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    if let url, showSizes {
                        let path = RoomPillPath.abbreviate(url.path, home: FileManager.default.homeDirectoryForCurrentUser.path)
                        Text(path).font(RoomTokens.Typography.path)
                            .lineLimit(2).truncationMode(.middle)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    VStack(spacing: RoomTokens.Space.tight) {
                        if let parent, parent.relativePath != node.relativePath, parent.allocatedBytes > 0 {
                            let ratio = Double(node.allocatedBytes) / Double(parent.allocatedBytes)
                            if showSizes {
                                fact("Share of \(parent.name)", ratio.formatted(.percent.precision(.fractionLength(0))))
                            }
                        }
                        fact("Measured", node.isPartial ? "Partly · lower bound" : "Fully")
                        if showSizes { fact("Files", node.fileCount.formatted()) }
                    }
                    if node.isDirectory, !node.children.isEmpty {
                        let children = Array(node.children.prefix(4))
                        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                            Text("Inside").font(RoomTokens.Typography.section)
                            insideBar(children, otherBytes: max(0, node.allocatedBytes - children.reduce(0) { $0 + $1.allocatedBytes }))
                            ForEach(children, id: \.relativePath) { child in
                                fact(showSizes ? child.name : "Name hidden", showSizes ?
                                     (child.isPartial ? "≥ " : "") + RoomFormat.bytes(child.allocatedBytes) : "Size hidden")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        if node.isDirectory, node.relativePath != parent?.relativePath {
                            if node.canStepInside {
                                action("Step inside", symbol: "chevron.right", perform: stepIn)
                                if url != nil, !node.relativePath.isEmpty {
                                    Button("Rescan this folder", action: rescan).buttonStyle(.borderless)
                                        .disabled(isScanning)
                                }
                            } else if url != nil, !node.relativePath.isEmpty {
                                action("Map this folder", symbol: "map", perform: map).disabled(isScanning)
                            }
                        }
                        if let url, showSizes {
                            action("Show in Finder", symbol: "arrow.up.right.square") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            if node.isDirectory, let pin {
                                action("Pin as a Room", symbol: "pin") { pin(url) }
                            }
                        }
                    }
                    if showSizes, node.relativePath.isEmpty {
                        storageReview
                    } else if showSizes, let finding = analysis?.findings.first(where: { $0.item.url.path == url?.path }) {
                        DisclosureGroup("Smart review") {
                            Text(finding.reason).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(RoomTokens.Typography.caption)
                    }
                } else {
                    Text("Nothing selected").font(RoomTokens.Typography.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RoomTokens.Space.group)
        }
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        .accessibilityIdentifier("RoomDiskMapInspector")
        .onChange(of: analysisStatus) { _, status in
            if status != nil { showsReview = true }
        }
    }

    private var storageReview: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            action(isAnalyzing ? "Analysing…" : "Analyse storage", symbol: "magnifyingglass", perform: inspect)
                .disabled(!canAnalyze)
                .accessibilityIdentifier("RoomAnalyzeStorage")
            if let analysisStatus {
                Text(analysisStatus).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .accessibilityIdentifier("RoomAnalyzeStorageStatus")
            }
            if let analysis, !analysis.findings.isEmpty {
                DisclosureGroup(isExpanded: $showsReview) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                        Text(analysis.summary).foregroundStyle(RoomTokens.Ink.secondary)
                        ForEach(analysis.findings.prefix(8)) { finding in
                            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                                Text(finding.item.name).fontWeight(.semibold)
                                Text(finding.reason).foregroundStyle(RoomTokens.Ink.secondary)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text("Smart review")
                }
            }
        }
        .font(RoomTokens.Typography.caption)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            Text(label).foregroundStyle(RoomTokens.Ink.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text(value).monospacedDigit().fixedSize()
        }
        .font(RoomTokens.Typography.caption)
        .accessibilityElement(children: .combine)
    }

    private func insideBar(_ children: [RoomTreeNode], otherBytes: Int64) -> some View {
        let outside = "\u{0}outside"
        let amounts = children.map { (kind: $0.relativePath, bytes: $0.allocatedBytes) }
            + [(kind: outside, bytes: otherBytes)]
        return GeometryReader { geometry in
            HStack(spacing: RoomKindStrip.barGap) {
                ForEach(RoomKindStrip.bar(amounts, width: geometry.size.width), id: \.kind) { part in
                    let kind = children.first { $0.relativePath == part.kind }.flatMap { StorageKind.dominant($0.kindBytes) }
                    RoundedRectangle(cornerRadius: RoomTokens.Radius.budgetFill)
                        .fill(kind.flatMap { RoomTokens.Kind(rawValue: $0.rawValue) }?.mark ?? RoomTokens.Surface.track)
                        .frame(width: part.width)
                }
            }
        }
        .frame(height: RoomTokens.Space.row)
        .accessibilityHidden(true)
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .roomSecondary()
    }
}
