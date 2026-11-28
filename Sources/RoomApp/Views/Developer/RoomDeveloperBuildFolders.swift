import Foundation
import RoomCore

/// What Developer suggests clearing from projects' build folders, and how it words them. Pure, so it is tested.
nonisolated enum RoomDeveloperBuildFolders {
    /// A project nothing in has changed for this long is ticked for you.
    static let staleDays = 30

    static func isStale(_ project: DeveloperFoundProject, now: Date) -> Bool {
        guard let changed = project.lastChanged else { return false }
        return now.timeIntervalSince(changed) >= TimeInterval(staleDays) * 86_400
    }

    /// Projects ticked for you: untouched for a month, with something to clear, and read in full, since a search cut
    /// short can make a project look older than it is.
    static func suggested(_ scan: DeveloperProjectScan?, now: Date) -> Set<String> {
        Set((scan?.projects ?? []).filter { $0.buildBytes > 0 && $0.fullyRead && isStale($0, now: now) }.map(\.id))
    }

    static func bytes(_ scan: DeveloperProjectScan?, selection: Set<String>) -> Int64 {
        sum((scan?.projects ?? []).filter { selection.contains($0.id) }.map(\.buildBytes))
    }

    /// The build folders that could be cleared in projects untouched for a month.
    static func staleBytes(_ scan: DeveloperProjectScan?, now: Date) -> Int64 {
        sum((scan?.projects ?? []).filter { isStale($0, now: now) }.map(\.buildBytes))
    }

    /// Adds sizes without overflowing; a negative size counts as nothing.
    static func sum(_ bytes: [Int64]) -> Int64 {
        bytes.reduce(0) { total, value in
            let next = total.addingReportingOverflow(max(0, value))
            return next.overflow ? Int64.max : next.partialValue
        }
    }

    static func removing(_ paths: Set<String>, from scan: DeveloperProjectScan) -> DeveloperProjectScan {
        DeveloperProjectScan(projects: scan.projects.map { project in
            DeveloperFoundProject(url: project.url, kinds: project.kinds,
                                  buildFolders: project.buildFolders.filter { !paths.contains($0.url.standardizedFileURL.path) },
                                  lastChanged: project.lastChanged, fullyRead: project.fullyRead)
        }, partial: scan.partial, scannedAt: scan.scannedAt)
    }

    /// "today", "yesterday", "4 days ago", "3 weeks ago", "5 months ago", "2 years ago".
    static func age(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let days = Int(max(0, now.timeIntervalSince(date)) / 86_400)
        func plural(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s") ago" }
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return plural(days, "day")
        case 14..<60: return plural(days / 7, "week")
        case 60..<730: return plural(days / 30, "month")
        default: return plural(days / 365, "year")
        }
    }

    /// The row's quiet line: "3 GB to clear · 4 months ago", the part a tick moves and how fresh the project is.
    /// When the row's size is all build folders, the size is already beside it, so only the age is said.
    static func meta(_ project: DeveloperFoundProject, now: Date, alsoElsewhere: Bool = true) -> String {
        if !alsoElsewhere, let age = age(project.lastChanged, now: now) { return age }
        let size = RoomFormat.gb(project.buildBytes)
        let clear = (project.partial ? RoomFormat.lowerBound(size) : size) + " to clear"
        return [clear, age(project.lastChanged, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Node · node_modules, .next and more": what it is and which folders go, for the row's help and VoiceOver.
    static func summary(_ project: DeveloperFoundProject) -> String {
        let kinds = project.kinds.prefix(2).map(\.title).joined(separator: " and ")
        var names = project.buildFolders.sorted { $0.bytes > $1.bytes }.map { ($0.name as NSString).lastPathComponent }
        var seen = Set<String>()
        names = names.filter { seen.insert($0).inserted }
        let folders = names.count > 2 ? names.prefix(2).joined(separator: ", ") + " and more" : names.joined(separator: ", ")
        return [kinds, folders].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
