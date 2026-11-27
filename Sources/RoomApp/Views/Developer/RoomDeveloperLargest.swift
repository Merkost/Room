import RoomCore
import Foundation

/// One row of a Developer section: the largest things in it.
nonisolated struct RoomDeveloperLargestRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let meta: String?
    let bytes: Int64
    let path: String?
    var project = false
    var glyph: RoomGlyph = .folder
}

/// The rows each Developer section leads with, largest first.
enum RoomDeveloperLargest {
    static func projects(_ summary: RoomDevSummary?) -> [RoomDeveloperLargestRow] {
        guard let summary else { return [] }
        return summary.rows.filter { $0.totalBytes > 0 }.sorted { $0.totalBytes > $1.totalBytes }.map { row in
            let builds = row.segments.filter { $0.kind == .derivedData }.reduce(Int64(0)) { $0 + $1.bytes }
            let meta = builds > 0 ? "builds \(RoomFormat.gb(builds))" : (row.kindLine.isEmpty ? nil : row.kindLine)
            return RoomDeveloperLargestRow(id: row.project.root, name: row.project.name, meta: meta, bytes: row.totalBytes,
                                           path: row.project.root, project: true, glyph: .term)
        }
    }

    static func devices(_ report: DeveloperResourcesReport?) -> [RoomDeveloperLargestRow] {
        guard let report else { return [] }
        let android = report.androidDevices.map {
            RoomDeveloperLargestRow(id: $0.id, name: $0.displayName, meta: $0.apiLevel.map { "API \($0)" },
                                    bytes: $0.allocatedBytes, path: $0.url.path, glyph: .phone)
        }
        let simulators = report.simulatorDevices.map {
            RoomDeveloperLargestRow(id: $0.id, name: $0.displayName, meta: $0.runtimeIdentifier.map(runtime),
                                    bytes: $0.allocatedBytes, path: $0.url.path, glyph: .phone)
        }
        return (android + simulators).sorted { $0.bytes > $1.bytes }
    }

    static func storage(_ report: DeveloperResourcesReport?) -> [RoomDeveloperLargestRow] {
        guard let report else { return [] }
        return report.storageResources.map {
            RoomDeveloperLargestRow(id: $0.id, name: $0.runtime?.name ?? $0.kind.title,
                                    meta: $0.runtime != nil ? $0.kind.title.lowercased() : "rebuildable",
                                    bytes: $0.allocatedBytes, path: $0.url.path, glyph: .box)
        }.sorted { $0.bytes > $1.bytes }
    }

    static func aiTools(_ report: DeveloperResourcesReport?) -> [RoomDeveloperLargestRow] {
        guard let report else { return [] }
        return Dictionary(grouping: report.aiStorageResources, by: \.tool).map { tool, items in
            let kinds = items.sorted { $0.allocatedBytes > $1.allocatedBytes }.map { $0.title.lowercased() }
            var seen = Set<String>()
            let meta = kinds.filter { seen.insert($0).inserted }.prefix(2).joined(separator: " and ")
            return RoomDeveloperLargestRow(id: tool.rawValue, name: title(tool), meta: meta,
                                           bytes: items.reduce(0) { $0 + $1.allocatedBytes }, path: nil, glyph: .spark)
        }.sorted { $0.bytes > $1.bytes }
    }

    #if !ROOM_APP_STORE
    static func worktrees(_ report: AgentWorkReport?) -> [RoomDeveloperLargestRow] {
        guard let report else { return [] }
        return report.items.map {
            RoomDeveloperLargestRow(id: $0.id, name: $0.title, meta: $0.branch, bytes: $0.allocatedBytes,
                                    path: $0.url.path, glyph: .branch)
        }.sorted { $0.bytes > $1.bytes }
    }
    #endif

    static func title(_ tool: DeveloperAITool) -> String {
        switch tool {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .chatGPT: "ChatGPT"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .copilot: "GitHub Copilot CLI"
        case .ollama: "Local models"
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-1" → "iOS 26.1"; plain names pass through.
    static func runtime(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last, identifier.contains("SimRuntime") else { return identifier }
        let parts = last.split(separator: "-")
        guard let os = parts.first else { return identifier }
        return "\(os) \(parts.dropFirst().joined(separator: "."))"
    }
}
