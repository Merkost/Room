import Foundation

// MARK: - Model

public nonisolated enum RoomDevPinKind: String, CaseIterable, Codable, Sendable {
    // Bar order and legend order (spec 08 §2.1): Xcode DerivedData, NDK, Kotlin/Native, Gradle wrapper.
    case derivedData, ndk, kotlinNative, gradle
    public var title: String {
        switch self { case .derivedData: "Xcode DerivedData"; case .ndk: "NDK"; case .kotlinNative: "Kotlin/Native"; case .gradle: "Gradle" }
    }
}

public nonisolated struct DeveloperProject: Codable, Equatable, Sendable, Identifiable {
    public struct GradlePin: Codable, Equatable, Sendable {
        public let version: String
        public let type: String
    }

    public var id: String { root }
    public var root: String
    public var name: String
    public var gradle: GradlePin?
    public var agp: String?
    public var kotlin: String?
    public var multiplatform: Bool
    public var appleNativeTargets: Bool
    public var ndk: String?
    public var hasXcodeProject: Bool

    init(root: String, name: String, gradle: (version: String, type: String)? = nil,
         agp: String? = nil, kotlin: String? = nil, multiplatform: Bool = false,
         appleNativeTargets: Bool = false, ndk: String? = nil, hasXcodeProject: Bool = false) {
        self.root = root
        self.name = name
        self.gradle = gradle.map { GradlePin(version: $0.version, type: $0.type) }
        self.agp = agp
        self.kotlin = kotlin
        self.multiplatform = multiplatform
        self.appleNativeTargets = appleNativeTargets
        self.ndk = ndk
        self.hasXcodeProject = hasXcodeProject
    }

    /// Kotlin/Native is pinned only by multiplatform projects declaring Apple targets.
    public var pinsKonan: Bool { multiplatform && appleNativeTargets && kotlin != nil }
}

typealias RoomDevProject = DeveloperProject

/// One measured folder found in an APPROVED role root. bytes are allocated bytes from the existing bounded measure.
public nonisolated struct DeveloperToolchainResource: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var kind: RoomDevPinKind
    public var version: String              // Gradle "8.9-bin", NDK / konan version, DerivedData folder name
    public var gradleType: String? = nil
    public var workspacePath: String? = nil
    // A checked absence is distinct from an outside-scope or unreadable workspace.
    public var workspacePresent: Bool? = nil
    public var bytes: Int64
    public var partial: Bool
    /// Stable, path-free key for the "first unreferenced" record (spec 04: no absolute paths in summaries).
    public var key: String { "\(kind.rawValue):\(version)" }
}

typealias RoomDevArtifact = DeveloperToolchainResource

public nonisolated enum RoomDevOrphanReason: Equatable, Sendable {
    case pinnedByNone
    case projectFolderGone
    case unknownWorkspace
    public var text: String {
        switch self {
        case .pinnedByNone: "Pinned by none of your projects"
        case .projectFolderGone: "Its project folder is gone"
        case .unknownWorkspace: "Room couldn't read which project made this"
        }
    }
}

public nonisolated struct RoomDevSegment: Equatable, Sendable {
    public let kind: RoomDevPinKind
    public let version: String
    public let bytes: Int64
    public let partial: Bool
    public let countedEarlier: Bool     // hatched outline: a project higher in the list already counts these bytes
    public let sharedBy: Int
}

public nonisolated struct RoomDevProjectRow: Equatable, Sendable {
    public let project: DeveloperProject
    public let segments: [RoomDevSegment]
    public var totalBytes: Int64 { segments.reduce(0) { RoomDeveloperRooms.add($0, $1.bytes) } }
    public var partial: Bool { segments.contains(where: \.partial) }
    public var kindLine: String {
        var parts: [String] = []
        if project.agp != nil { parts.append("Android") }
        if project.hasXcodeProject || project.appleNativeTargets || segments.contains(where: { $0.kind == .derivedData }) { parts.append("iOS") }
        if project.multiplatform { parts.append("shared Kotlin") }
        else if project.kotlin != nil { parts.append("Kotlin JVM") }
        return parts.joined(separator: ", ")
    }
}

public nonisolated struct RoomDevSummary: Equatable, Sendable {
    public let rows: [RoomDevProjectRow]
    public let pinnedBytes: Int64           // unique artifacts referenced by ≥ 1 project, counted once
    public let sharedBytes: Int64           // unique artifacts referenced by ≥ 2 projects, counted once
    public let orphans: [(artifact: DeveloperToolchainResource, reason: RoomDevOrphanReason)]
    public let orphanBytes: Int64
    public let partial: Bool                // any byte figure is a lower bound: shown with "≥"
    public var pinnedProjectCount: Int { rows.filter { $0.totalBytes > 0 }.count }
    public static func == (a: Self, b: Self) -> Bool {
        a.rows == b.rows && a.pinnedBytes == b.pinnedBytes && a.sharedBytes == b.sharedBytes
            && a.orphans.map(\.artifact) == b.orphans.map(\.artifact) && a.orphans.map(\.reason) == b.orphans.map(\.reason)
            && a.orphanBytes == b.orphanBytes && a.partial == b.partial
    }
}

public nonisolated enum RoomDeveloperRooms {
    public static func contains(_ path: String, in root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

    public static func references(_ a: DeveloperToolchainResource, _ p: DeveloperProject) -> Bool {
        switch a.kind {
        case .gradle: p.gradle.map { $0.version + "-" + $0.type == a.version } ?? false
        case .kotlinNative: p.pinsKonan && p.kotlin == a.version
        case .ndk: p.ndk == a.version
        case .derivedData: a.workspacePath.map { contains($0, in: p.root) } ?? false
        }
    }

    static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let r = a.addingReportingOverflow(max(0, b)); return r.overflow ? .max : r.partialValue
    }

    /// `exists` answers whether a DerivedData WorkspacePath still exists on disk (injected; the engine checks it inside
    /// approved scope only, otherwise passes nil-workspace artifacts as unknownWorkspace).
    public static func summarize(projects: [DeveloperProject], artifacts: [DeveloperToolchainResource], scanPartial: Bool,
                          exists: (String) -> Bool = { _ in true }) -> RoomDevSummary {
        let projectsByRoot = Dictionary(grouping: projects, by: \.root).compactMap { $0.value.first }
        var refs: [String: [String]] = [:]          // artifact path → project roots
        for a in artifacts { refs[a.path] = projectsByRoot.filter { references(a, $0) }.map(\.root) }
        let draft = projectsByRoot.map { p -> (RoomDevProject, [DeveloperToolchainResource]) in
            (p, artifacts.filter { refs[$0.path]?.contains(p.root) == true })
        }
        let ordered = draft.sorted { l, r in
            let lt = l.1.reduce(Int64(0)) { add($0, $1.bytes) }, rt = r.1.reduce(Int64(0)) { add($0, $1.bytes) }
            return lt == rt ? l.0.name.localizedStandardCompare(r.0.name) == .orderedAscending : lt > rt
        }
        var counted: Set<String> = []
        let rows = ordered.map { p, owned -> RoomDevProjectRow in
            let segs = RoomDevPinKind.allCases.flatMap { kind in
                owned.filter { $0.kind == kind }.sorted { $0.bytes > $1.bytes }.map { a in
                    RoomDevSegment(kind: kind, version: a.version, bytes: a.bytes, partial: a.partial,
                                   countedEarlier: !counted.insert(a.path).inserted, sharedBy: refs[a.path]?.count ?? 0)
                }
            }
            return RoomDevProjectRow(project: p, segments: segs)
        }
        var pinned: Int64 = 0, shared: Int64 = 0, orphanTotal: Int64 = 0
        var orphans: [(DeveloperToolchainResource, RoomDevOrphanReason)] = []
        for a in artifacts {
            let n = refs[a.path]?.count ?? 0
            if n >= 1 { pinned = add(pinned, a.bytes) }
            if n >= 2 { shared = add(shared, a.bytes) }
            if n == 0 {
                orphanTotal = add(orphanTotal, a.bytes)
                let reason: RoomDevOrphanReason
                if a.kind == .derivedData {
                    if let w = a.workspacePath { reason = a.workspacePresent == false || !exists(w) ? .projectFolderGone : .pinnedByNone } else { reason = .unknownWorkspace }
                } else { reason = .pinnedByNone }
                orphans.append((a, reason))
            }
        }
        orphans.sort { $0.0.bytes == $1.0.bytes ? $0.0.version < $1.0.version : $0.0.bytes > $1.0.bytes }
        return RoomDevSummary(rows: rows, pinnedBytes: pinned, sharedBytes: shared, orphans: orphans, orphanBytes: orphanTotal,
                              partial: scanPartial || artifacts.contains(where: \.partial))
    }
}

// MARK: - Version matrix (spec 08 §2.2)

public nonisolated struct RoomDevMatrixCell: Equatable, Sendable {
    public let text: String       // "—" when not pinned
    public let shaded: Bool       // shared by more than one project, counted once
    public let tooltip: String?
}

public nonisolated enum RoomDevMatrix {
    public static let columns = ["Gradle", "AGP", "Kotlin", "NDK", "Xcode DerivedData"]

    public static func rows(_ s: RoomDevSummary) -> [(title: String, cells: [RoomDevMatrixCell])] {
        func cell(_ seg: [RoomDevSegment]) -> RoomDevMatrixCell {
            guard let first = seg.first else { return .init(text: "—", shaded: false, tooltip: nil) }
            let text = seg.count > 1 ? "\(first.version) +\(seg.count - 1)" : first.version
            return .init(text: text, shaded: seg.contains { $0.sharedBy > 1 }, tooltip: nil)
        }
        var out = s.rows.map { row -> (String, [RoomDevMatrixCell]) in
            let p = row.project
            let kotlin: RoomDevMatrixCell
            if let k = p.kotlin, !p.pinsKonan {
                kotlin = .init(text: "\(k) JVM", shaded: false, tooltip: "JVM only: no native toolchain on disk")
            } else { kotlin = cell(row.segments.filter { $0.kind == .kotlinNative }) }
            let gradle = p.gradle.map { g -> RoomDevMatrixCell in
                let seg = row.segments.filter { $0.kind == .gradle }
                return .init(text: g.version, shaded: seg.contains { $0.sharedBy > 1 }, tooltip: seg.isEmpty ? "Not on this Mac" : nil)
            } ?? .init(text: "—", shaded: false, tooltip: nil)
            return (p.name, [gradle, .init(text: p.agp ?? "—", shaded: false, tooltip: p.agp == nil ? nil : "Lives in the shared Gradle module cache"),
                             kotlin, cell(row.segments.filter { $0.kind == .ndk }), cell(row.segments.filter { $0.kind == .derivedData })])
        }
        func orphanCell(_ kind: RoomDevPinKind?) -> RoomDevMatrixCell {
            guard let kind else { return .init(text: "—", shaded: false, tooltip: nil) }
            let v = s.orphans.filter { $0.artifact.kind == kind }.map(\.artifact.version)
            guard let first = v.first else { return .init(text: "—", shaded: false, tooltip: nil) }
            return .init(text: v.count > 1 ? "\(first) +\(v.count - 1)" : first, shaded: false, tooltip: nil)
        }
        out.append(("Not in any room", [orphanCell(.gradle), orphanCell(nil), orphanCell(.kotlinNative), orphanCell(.ndk), orphanCell(.derivedData)]))
        return out
    }
}
