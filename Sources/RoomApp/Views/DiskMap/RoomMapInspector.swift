import AppKit
import RoomCore
import SwiftUI

struct RoomMapInspector: View {
    let node: RoomTreeNode?
    let url: URL?
    let showSizes: Bool
    let isScanning: Bool
    let analysis: StorageAnalysisReport?
    let isAnalyzing: Bool
    let stepIn: () -> Void
    let map: () -> Void
    let rescan: () -> Void
    let inspect: () -> Void

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
                    Text(showSizes ? (node.isPartial ? "≥ " : "") + RoomFormat.bytes(node.allocatedBytes) : "Size hidden")
                        .font(RoomTokens.Typography.figure)
                    if let url, showSizes {
                        Text(url.path).font(RoomTokens.Typography.path)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    if showSizes {
                        Text("\(node.fileCount.formatted()) files").font(RoomTokens.Typography.caption)
                    }
                    ForEach(RoomKindStrip.totals(node), id: \.kind) { amount in
                        HStack {
                            Text(StorageKind(rawValue: amount.kind)?.title ?? "Other")
                            Spacer()
                            Text(showSizes ? RoomFormat.bytes(amount.bytes) : "Hidden")
                                .monospacedDigit()
                        }
                        .font(RoomTokens.Typography.caption)
                    }
                    if node.isDirectory {
                        if node.canStepInside {
                            Button("Step inside", action: stepIn).roomSecondary()
                            if !node.relativePath.isEmpty {
                                Button("Rescan this folder", action: rescan).buttonStyle(.borderless)
                                    .disabled(isScanning)
                            }
                        } else if !node.relativePath.isEmpty {
                            Button("Map this folder", action: map).roomSecondary().disabled(isScanning)
                        }
                    }
                    if let url {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.borderless)
                    }
                    if !showSizes { EmptyView() }
                    else if let finding = analysis?.findings.first(where: { $0.item.url == url }) {
                        DisclosureGroup("Smart review") {
                            Text(finding.reason).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(RoomTokens.Typography.caption)
                    } else if analysis?.findings.isEmpty == false && node.relativePath.isEmpty {
                        DisclosureGroup("Smart review") {
                            ForEach(analysis?.findings.prefix(8) ?? []) { finding in
                                Text(finding.reason)
                            }
                        }
                        .font(RoomTokens.Typography.caption)
                    }
                    if node.relativePath.isEmpty {
                        Button(isAnalyzing ? "Analysing…" : "Analyse storage", action: inspect)
                            .buttonStyle(.borderless).disabled(isScanning || isAnalyzing)
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
    }
}
