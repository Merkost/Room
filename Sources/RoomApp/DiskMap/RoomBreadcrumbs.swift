import SwiftUI
import RoomCore

struct RoomBreadcrumbs: View {
    var trail: [RoomTreeNode]
    var hidden = false
    var go: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(trail)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: RoomTokens.Space.row) {
                if let root = trail.first { crumb(root) }
                if trail.count > 2 {
                    Menu("…") {
                        ForEach(trail.dropFirst().dropLast(), id: \.relativePath) { crumb($0) }
                    }
                    .accessibilityLabel("Enclosing folders")
                }
                if trail.count > 1, let last = trail.last { crumb(last) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Disk Map location")
    }

    private func row(_ nodes: [RoomTreeNode]) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            ForEach(nodes, id: \.relativePath) { node in
                if node.relativePath != nodes.first?.relativePath {
                    Image(systemName: "chevron.right")
                        .font(RoomTokens.Typography.micro)
                        .accessibilityHidden(true)
                }
                crumb(node)
            }
        }
    }

    @ViewBuilder private func crumb(_ node: RoomTreeNode) -> some View {
        let title = hidden ? (node.relativePath.isEmpty ? "Root folder" : "Folder") : node.name
        if node.relativePath == trail.last?.relativePath {
            Text(title)
                .font(RoomTokens.Typography.section)
                .lineLimit(1)
                .padding(.horizontal, RoomTokens.Space.row)
                .frame(minHeight: 24)
                .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
        } else {
            Button(title) { go(node.relativePath) }
                .buttonStyle(.borderless)
                .lineLimit(1)
        }
    }
}
