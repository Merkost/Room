import RoomCore
import SwiftUI

struct RoomDeveloperAIStorageView: View {
    let report: DeveloperResourcesReport?
    let hasFolders: Bool
    @State private var selected: DeveloperAITool?

    var body: some View {
        let groups = Dictionary(grouping: report?.aiStorageResources ?? [], by: \.tool)
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            if groups.isEmpty {
                emptyState
            } else {
                if groups.count > 1 { tools(groups) }
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    ForEach(RoomDeveloperFolderRole.aiRoles.sorted { total($0, groups) > total($1, groups) }) { role in
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
        RoomDeveloperGroup(title: report == nil ? "AI tool storage" : "No recognised storage found") {
            Text(report != nil ? "Check that you chose the tool’s data folder."
                : hasFolders ? "Scan to see caches, history, and local models."
                : "Choose a tool folder to see what occupies disk space.")
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
    }

    private func total(_ role: RoomDeveloperFolderRole, _ groups: [DeveloperAITool: [DeveloperAIStorageResource]]) -> Int64 {
        role.aiTool.flatMap { groups[$0] }.map { RoomDeveloperPresentation.sum($0.map(\.allocatedBytes)) } ?? 0
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
        RoomDeveloperGroup(title: role.title) {
            RoomDeveloperRowList(items: RoomDeveloperList.bySize(resources, bytes: \.allocatedBytes, name: \.title)) { resource in
                RoomDeveloperRow(title: resource.title, masksTitle: false, subtitle: resource.url.path,
                                 note: presentation(resource.category).title,
                                 bytes: resource.allocatedBytes, partial: resource.isPartial, finderURL: resource.url)
            }
        }
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
