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
    /// Build folders in it that can be ticked and moved to Trash.
    var buildBytes: Int64 = 0
    /// Sizes are lower bounds.
    var partial = false
}

/// The rows each Developer section leads with, largest first.
enum RoomDeveloperLargest {
    /// Every project found, of any kind: its build folders, plus what Gradle and Xcode keep for it elsewhere.
    /// Projects Room suggests clearing lead, so nothing ticked hides behind "N more"; ticking never reorders the list.
    static func projects(_ summary: RoomDevSummary?, scan: DeveloperProjectScan? = nil, now: Date = Date()) -> [RoomDeveloperLargestRow] {
        let suggested = RoomDeveloperBuildFolders.suggested(scan, now: now)
        var rows: [String: RoomDeveloperLargestRow] = [:]
        for row in summary?.rows ?? [] where row.totalBytes > 0 {
            let builds = row.segments.filter { $0.kind == .derivedData }.reduce(Int64(0)) { $0 + $1.bytes }
            let meta = builds > 0 ? "builds \(RoomFormat.gb(builds))" : (row.kindLine.isEmpty ? nil : row.kindLine)
            let path = URL(fileURLWithPath: row.project.root).standardizedFileURL.path
            rows[path] = RoomDeveloperLargestRow(id: path, name: row.project.name, meta: meta, bytes: row.totalBytes,
                                                 path: row.project.root, project: true, glyph: .term)
        }
        for project in scan?.projects ?? [] where project.buildBytes > 0 {
            let path = project.url.standardizedFileURL.path
            let elsewhere = rows[path]?.bytes ?? 0
            rows[path] = RoomDeveloperLargestRow(id: project.id, name: project.name,
                                                 meta: RoomDeveloperBuildFolders.meta(project, now: now, alsoElsewhere: elsewhere > 0),
                                                 bytes: RoomDeveloperPresentation.sum([project.buildBytes, elsewhere]),
                                                 path: project.url.path, project: true, glyph: .term,
                                                 buildBytes: project.buildBytes, partial: project.partial)
        }
        return rows.values.sorted { left, right in
            let (a, b) = (suggested.contains(left.id), suggested.contains(right.id))
            if a != b { return a }
            return left.bytes == right.bytes ? left.id < right.id : left.bytes > right.bytes
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
        case .claudeCode: "Claude Code"
        case .chatGPT: "ChatGPT"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .copilot: "GitHub Copilot CLI"
        case .ollama: "Ollama"
        case .claudeApp: "Claude app"
        case .codexApp: "Codex app"
        case .lmStudio: "LM Studio"
        case .huggingFace: "Hugging Face"
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
