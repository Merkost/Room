import Foundation

/// Developer's headline per room (nav-v3): "120 GB in projects", "94 GB of toolchains", "20 GB of simulators",
/// "67 GB of build storage", "27 GB of AI tools", "6 GB in worktrees". Pure, so it is tested.
nonisolated struct RoomDeveloperWords: Equatable, Sendable {
    struct Input: Equatable, Sendable {
        var projectsBytes: Int64 = 0
        var unreferencedBytes: Int64 = 0
        var projects = 0
        var versions = 0
        var devicesBytes: Int64 = 0
        var devices = 0
        var storageBytes: Int64 = 0
        var aiBytes: Int64 = 0
        var aiTools = 0
        var worktreesBytes: Int64 = 0
        var worktrees = 0
        var partial = false
    }

    let headline: RoomHeadline
    let supporting: String

    static func make(section: String, _ i: Input) -> RoomDeveloperWords {
        func size(_ bytes: Int64) -> String { i.partial ? RoomFormat.lowerBound(bytes) : RoomFormat.gb(bytes) }
        func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
        switch section {
        case "Rooms":
            guard i.projectsBytes > 0 else { return .init(headline: .words("Projects"), supporting: "Scan a projects folder to measure it") }
            var line = count(i.projects, "project", "projects")
            if i.unreferencedBytes > 0 { line += ", \(RoomFormat.gb(i.unreferencedBytes)) that nothing uses" }
            return .init(headline: RoomHeadline(figure: size(i.projectsBytes), words: "in projects"), supporting: line)
        case "Matrix":
            guard i.projectsBytes > 0 else { return .init(headline: .words("Toolchains"), supporting: "Scan to see which versions each project pins") }
            let line = i.unreferencedBytes > 0 ? "\(count(i.versions, "version", "versions")), old ones can go"
                                               : count(i.versions, "version", "versions")
            return .init(headline: RoomHeadline(figure: size(i.projectsBytes), words: "of toolchains"), supporting: line)
        case "Devices":
            guard i.devicesBytes > 0 else { return .init(headline: .words("Simulators"), supporting: "Choose a device folder to measure it") }
            return .init(headline: RoomHeadline(figure: size(i.devicesBytes), words: "of simulators"),
                         supporting: count(i.devices, "device", "devices"))
        case "Storage":
            guard i.storageBytes > 0 else { return .init(headline: .words("Build storage"), supporting: "Scan to measure build storage") }
            return .init(headline: RoomHeadline(figure: size(i.storageBytes), words: "of build storage"),
                         supporting: "All of it can be made again")
        case "AI Tools":
            guard i.aiBytes > 0 else { return .init(headline: .words("AI tools"), supporting: "Choose a tool folder to measure it") }
            return .init(headline: RoomHeadline(figure: size(i.aiBytes), words: "of AI tools"),
                         supporting: "Models, caches and sessions")
        default:
            guard i.worktreesBytes > 0 else { return .init(headline: .words("Worktrees"), supporting: "Scan a repository to see its worktrees") }
            return .init(headline: RoomHeadline(figure: size(i.worktreesBytes), words: "in worktrees"),
                         supporting: count(i.worktrees, "worktree", "worktrees"))
        }
    }
}
