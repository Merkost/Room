import Foundation
import Observation
import RoomCore

/// Roles reference shared read-only bookmarks; no second set of permissions is stored.
enum RoomDeveloperFolderRole: String, CaseIterable, Codable, Identifiable {
    case android, gradle, project
    var id: String { rawValue }
    var title: String {
        switch self { case .android: "Android devices"; case .gradle: "Gradle home"; case .project: "Project folder" }
    }
    var symbol: String {
        switch self { case .android: "iphone.gen3"; case .gradle: "shippingbox"; case .project: "folder" }
    }
    var pickerMessage: String {
        switch self {
        case .android: "Choose an AVD directory, usually .android/avd. Room reads device sizes and available activity evidence."
        case .gradle: "Choose a Gradle user home, usually .gradle. Room measures distributions and version caches."
        case .project: "Choose a project or projects folder. Room reads Gradle wrapper versions to link selected projects to resources."
        }
    }
}

struct RoomDeveloperLocation: Identifiable {
    let role: RoomDeveloperFolderRole
    let folder: RoomAccessFolder
    var id: String { role.rawValue + ":" + folder.id }
}

@Observable @MainActor
final class RoomDeveloperModel {
    private struct RoleRecord: Codable, Equatable { let role: RoomDeveloperFolderRole; let folderID: String }
    private let access: RoomFileAccess
    private let defaults: UserDefaults
    @ObservationIgnored private let scanResources: @Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport
    private let key = "RoomDeveloperFolderRoles"
    private var records: [RoleRecord]
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private(set) var report: DeveloperResourcesReport?
    private(set) var isScanning = false
    private(set) var isChoosingFolder = false
    private(set) var progress = ""
    var errorMessage: String?

    init(access: RoomFileAccess = .shared, defaults: UserDefaults = .standard,
         scanner: (@Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport)? = nil) {
        self.access = access; self.defaults = defaults
        let engine = DeveloperResourcesEngine()
        self.scanResources = scanner ?? { request, progress in await engine.scan(request: request, progress: progress) }
        records = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RoleRecord].self, from: $0) } ?? []
    }

    var locations: [RoomDeveloperLocation] {
        records.compactMap { record in
            access.folders.first(where: { $0.id == record.folderID }).map { RoomDeveloperLocation(role: record.role, folder: $0) }
        }
    }
    var canScan: Bool { !locations.isEmpty && !isChoosingFolder }
    var accessRevision: [String] { access.folders.map(\.id).sorted() }
    var totalBytes: Int64 {
        guard let report else { return 0 }
        return RoomDeveloperPresentation.sum(report.androidDevices.map(\.allocatedBytes) + report.gradleResources.map(\.allocatedBytes))
    }

    func addFolder(role: RoomDeveloperFolderRole) {
        guard !isChoosingFolder, !isScanning else { return }
        isChoosingFolder = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingFolder = false }
            #if ROOM_APP_STORE
            let home = RoomStoreEnvironment.userHome
            #else
            let home: URL? = FileManager.default.homeDirectoryForCurrentUser
            #endif
            let initial: URL?
            switch role {
            case .android: initial = home?.appendingPathComponent(".android/avd", isDirectory: true)
            case .gradle: initial = home?.appendingPathComponent(".gradle", isDirectory: true)
            case .project: initial = home
            }
            guard let selected = await RoomNativeFolderPicker.shared.choose(title: role.title,
                message: role.pickerMessage, prompt: "Allow Read Access", initialURL: initial) else { return }
            do {
                let url = try self.access.remember(selected)
                guard let folder = self.access.folders.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
                self.attach(role: role, to: folder.id)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    /// Reuses only an already-approved shared bookmark; this never grants access.
    func attach(role: RoomDeveloperFolderRole, to folderID: String) {
        guard !isScanning, access.folders.contains(where: { $0.id == folderID }) else { return }
        let record = RoleRecord(role: role, folderID: folderID)
        if !records.contains(record) { records.append(record); persist() }
        report = nil
    }

    func remove(_ location: RoomDeveloperLocation) {
        guard !isScanning else { return }
        records.removeAll { $0.role == location.role && $0.folderID == location.folder.id }
        persist(); report = nil
    }

    func accessChanged() {
        generation = UUID()
        task?.cancel(); task = nil; isScanning = false
        report = nil; progress = ""
    }

    func scan() {
        guard canScan, !isScanning else { return }
        let current = locations
        let approved = Dictionary(grouping: current.map(\.folder.url), by: \.path).compactMap { $0.value.first }
        let request = DeveloperResourcesRequest(approvedFolders: approved,
            avdRoots: current.filter { $0.role == .android }.map(\.folder.url),
            gradleHomes: current.filter { $0.role == .gradle }.map(\.folder.url),
            projectRoots: current.filter { $0.role == .project }.map(\.folder.url))
        let token = UUID(); generation = token
        isScanning = true; errorMessage = nil; progress = "Preparing review…"
        let scanner = scanResources
        task = Task { [weak self] in
            let scopes = approved.filter { $0.startAccessingSecurityScopedResource() }
            defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
            let result = await scanner(request) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.progress = "\(update.phase) · \(update.inspectedCount.formatted()) items"
                }
            }
            guard let self, self.generation == token else { return }
            self.report = result; self.isScanning = false; self.task = nil
            self.progress = result.cancelled ? "Stopped · partial review" : (result.isPartial ? "Partial review" : "Review complete")
        }
    }

    func stop() { task?.cancel(); progress = "Stopping…" }
    private func persist() { if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) } }
}

struct RoomGradleVersionGroup: Identifiable {
    let version: String?
    let resources: [GradleDeveloperResource]
    let projects: [GradleProjectWrapper]
    var id: String { version ?? "shared" }
    var title: String { version.map { "Gradle \($0)" } ?? "Shared resources" }
    var bytes: Int64 { RoomDeveloperPresentation.sum(resources.map(\.allocatedBytes)) }
}

enum RoomDeveloperPresentation {
    static func sum(_ bytes: [Int64]) -> Int64 {
        bytes.reduce(0) { result, value in
            let addition = result.addingReportingOverflow(max(0, value))
            return addition.overflow ? Int64.max : addition.partialValue
        }
    }
    static func groups(_ resources: [GradleDeveloperResource]) -> [RoomGradleVersionGroup] {
        Dictionary(grouping: resources, by: { $0.version ?? "" }).map { key, values in
            let uses = values.flatMap(\.projectUses)
            let projects = Dictionary(grouping: uses, by: \.id).compactMap { $0.value.first }.sorted { $0.projectURL.path < $1.projectURL.path }
            return RoomGradleVersionGroup(version: key.isEmpty ? nil : key, resources: values.sorted { $0.allocatedBytes > $1.allocatedBytes }, projects: projects)
        }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
    }
    static func activityTitle(_ state: DeveloperResourceActivityState) -> String {
        switch state {
        case .observedUse: "Use observed"
        case .possibleUse: "Possible use"
        case .notObserved: "No use in sample"
        case .unknown: "Activity unknown"
        }
    }
    static func referenceTitle(_ count: Int) -> String {
        count == 0 ? "No selected project reference" : "\(count) selected \(count == 1 ? "project" : "projects")"
    }
}
