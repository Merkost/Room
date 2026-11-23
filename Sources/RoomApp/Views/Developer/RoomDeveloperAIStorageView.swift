import RoomCore
import SwiftUI

struct RoomDeveloperAIStorageView: View {
    let report: DeveloperResourcesReport?
    let hasFolders: Bool
    @Environment(\.roomAccent) private var accent
    @State private var selected: DeveloperAITool?

    var body: some View {
        let groups = Dictionary(grouping: report?.aiStorageResources ?? [], by: \.tool)
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            if groups.isEmpty {
                emptyState
            } else {
                if groups.count > 1 { tools(groups) }
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    ForEach(RoomDeveloperFolderRole.aiRoles) { role in
                        if let tool = role.aiTool, let resources = groups[tool], selected == nil || selected == tool {
                            group(role, resources: resources)
                        }
                    }
                }
                .roomPanelChange(selected)
            }
        }
        .onChange(of: Set(groups.keys)) { _, tools in
            if let selected, !tools.contains(selected) { self.selected = nil }
        }
    }

    private var emptyState: some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: "sparkles")
                .font(RoomTokens.Typography.title)
                .foregroundStyle(accent.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(report == nil ? "Review AI tool storage" : "No recognised storage found")
                    .font(RoomTokens.Typography.section)
                Text(report != nil ? "Check that you chose the tool’s data folder."
                    : hasFolders ? "Scan to see caches, history, and local models."
                    : "Choose a tool folder to see what occupies disk space.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private func tools(_ groups: [DeveloperAITool: [DeveloperAIStorageResource]]) -> some View {
        Picker("Filter tools", selection: $selected) {
            Text("All tools").tag(DeveloperAITool?.none)
            ForEach(RoomDeveloperFolderRole.aiRoles) { role in
                if let tool = role.aiTool, groups[tool] != nil {
                    Text(role.title).tag(Optional(tool))
                }
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func group(_ role: RoomDeveloperFolderRole, resources: [DeveloperAIStorageResource]) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Label(role.title, systemImage: role.symbol)
                .font(RoomTokens.Typography.section)
                .accessibilityHeading(.h2)
            ForEach(resources) { resource in
                row(resource)
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private func row(_ resource: DeveloperAIStorageResource) -> some View {
        let category = presentation(resource.category)
        return HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: category.symbol)
                .foregroundStyle(accent.text)
                .frame(width: RoomTokens.Space.group, height: RoomTokens.Space.group)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(resource.title)
                    .font(RoomTokens.Typography.body.weight(.semibold))
                RoomMaskable(resource.url.path, kind: .name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: RoomTokens.Space.tight) {
                RoomMaskable((resource.isPartial ? "≥ " : "") + RoomFormat.bytes(resource.allocatedBytes))
                    .font(RoomTokens.Typography.figure)
                    .monospacedDigit()
                Text(category.title)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.row)
        .background(RoomTokens.Surface.canvas, in: .rect(cornerRadius: RoomTokens.Radius.row))
        .accessibilityElement(children: .combine)
    }

    private func presentation(_ category: DeveloperAIStorageCategory) -> (title: String, symbol: String) {
        switch category {
        case .cache: ("Cache", "bolt.horizontal")
        case .history: ("History", "clock.arrow.circlepath")
        case .diagnostics: ("Diagnostics", "waveform.path")
        case .runtime: ("Models and tools", "shippingbox")
        case .worktrees: ("Workspace data", "point.3.connected.trianglepath.dotted")
        }
    }
}
