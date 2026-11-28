import Foundation
import RoomCore

/// Developer on one screen: the total, what it is made of, and one supporting line. Pure, so it is tested.
struct RoomDeveloperPage: Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case projects, devices, storage, aiTools, worktrees
        var title: String {
            switch self {
            case .projects: "Projects"
            case .devices: "Devices"
            case .storage: "Tool storage"
            case .aiTools: "AI tools"
            case .worktrees: "Worktrees"
            }
        }
    }

    struct Part: Equatable, Sendable, Identifiable {
        let kind: Kind
        let bytes: Int64
        var id: Kind { kind }
    }

    let parts: [Part]
    let headline: RoomHeadline
    let supporting: String

    var total: Int64 { RoomDeveloperPresentation.sum(parts.map(\.bytes)) }

    static func make(headline: RoomDeveloperHeadline, worktreesBytes: Int64, projects: Int,
                     clearable: Int64 = 0) -> RoomDeveloperPage {
        func bytes(_ kind: RoomDeveloperHeadline.Kind) -> Int64 { headline.parts.first { $0.kind == kind }?.bytes ?? 0 }
        let parts = [
            Part(kind: .projects, bytes: RoomDeveloperPresentation.sum([bytes(.inUse), bytes(.unreferenced), bytes(.buildFolders)])),
            Part(kind: .devices, bytes: bytes(.devices)),
            Part(kind: .storage, bytes: bytes(.toolStorage)),
            Part(kind: .aiTools, bytes: bytes(.aiTools)),
            Part(kind: .worktrees, bytes: worktreesBytes),
        ].filter { $0.bytes > 0 }
        let total = RoomDeveloperPresentation.sum(parts.map(\.bytes))
        let words: RoomHeadline = total > 0
            ? RoomHeadline(figure: headline.partial ? RoomFormat.lowerBound(total) : RoomFormat.gb(total), words: "of developer files")
            : .words("No developer files")
        let unused = bytes(.unreferenced)
        let supporting = clearable > 0 ? "\(RoomFormat.gb(clearable)) of build folders in projects untouched for a month"
            : unused > 0 ? "\(RoomFormat.gb(unused)) that nothing uses"
            : projects == 1 ? "1 project" : "\(projects) projects"
        return RoomDeveloperPage(parts: parts, headline: words, supporting: supporting)
    }
}

/// One version your projects pin, or one on disk that nothing pins.
struct RoomDeveloperVersionChip: Equatable, Identifiable {
    let id: String
    let label: String
    let detail: String
    var unused = false
    /// Names of the projects that pin it.
    var projects: [String] = []
    /// The folder of an unused version, and the record key its first-unused date is kept under.
    var path: String?
    var key: String?

    static func make(projects: [DeveloperProject], summary: RoomDevSummary?) -> [RoomDeveloperVersionChip] {
        let pins: [(String, (DeveloperProject) -> String?)] = [
            ("Gradle", { $0.gradle?.version }), ("Kotlin", \.kotlin), ("AGP", \.agp), ("NDK", \.ndk),
        ]
        var chips: [RoomDeveloperVersionChip] = []
        for (title, version) in pins {
            var using: [String: [String]] = [:]
            for project in projects {
                if let value = version(project) { using[value, default: []].append(project.name) }
            }
            let ordered = using.sorted { left, right in
                if left.value.count != right.value.count { return left.value.count > right.value.count }
                return left.key.compare(right.key, options: .numeric) == .orderedDescending
            }
            for (value, names) in ordered {
                chips.append(RoomDeveloperVersionChip(id: "\(title):\(value)", label: "\(title) \(value)",
                    detail: names.count == 1 ? "1 project" : "\(names.count) projects", projects: names.sorted()))
            }
        }
        let orphans = summary?.orphans.map(\.artifact) ?? []
        chips += orphans.filter { $0.kind != .derivedData }.map { artifact in
            let name = artifact.kind == .kotlinNative ? "Kotlin/Native" : artifact.kind.title
            let version = artifact.kind == .gradle ? String(artifact.version.prefix { $0 != "-" }) : artifact.version
            return RoomDeveloperVersionChip(id: "unused:\(artifact.path)", label: "\(name) \(version)",
                detail: "unused, \(RoomFormat.gb(artifact.bytes))", unused: true, path: artifact.path, key: artifact.key)
        }
        let builds = orphans.filter { $0.kind == .derivedData }
        if let largest = builds.max(by: { $0.bytes < $1.bytes }) {
            chips.append(RoomDeveloperVersionChip(id: "unused:builds",
                label: builds.count == 1 ? "1 old build folder" : "\(builds.count) old build folders",
                detail: "unused, \(RoomFormat.gb(builds.reduce(0) { $0 + $1.bytes }))", unused: true,
                path: (largest.path as NSString).deletingLastPathComponent))
        }
        return chips
    }
}
