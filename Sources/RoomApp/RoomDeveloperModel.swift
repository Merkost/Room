import Foundation
import Observation
import RoomCore

/// Roles reference shared read-only bookmarks; no second set of permissions is stored.
enum RoomDeveloperFolderRole: String, CaseIterable, Codable, Identifiable {
    case android, gradle, project, sdk, xcode, konan, simulators
    case codex, claudeCode, chatGPT, cursor, gemini, copilot, ollama
    var id: String { rawValue }
    var supportsToolStorage: Bool { self == .gradle || self == .sdk || self == .simulators }
    static let deviceRoles: [Self] = [.android, .simulators]
    var title: String {
        switch self {
        case .android: "Android devices"
        case .gradle: "Gradle home"
        case .project: "Projects folder"
        case .sdk: "Android SDK"
        case .xcode: "Xcode DerivedData"
        case .konan: "Kotlin/Native home"
        case .simulators: "Simulator Devices"
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .chatGPT: "ChatGPT"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .copilot: "GitHub Copilot CLI"
        case .ollama: "Ollama"
        }
    }
    var symbol: String {
        switch self {
        case .android: "iphone.gen3"
        case .gradle: "shippingbox"
        case .project: "folder"
        case .sdk: "hammer"
        case .xcode: "hammer.fill"
        case .konan: "terminal"
        case .simulators: "iphone.gen3"
        case .codex: "terminal"
        case .claudeCode, .gemini: "sparkle"
        case .chatGPT: "bubble.left.and.bubble.right"
        case .cursor: "cursorarrow.rays"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .ollama: "shippingbox"
        }
    }

    var aiTool: DeveloperAITool? { DeveloperAITool(rawValue: rawValue) }

    static var aiRoles: [Self] { allCases.filter { $0.aiTool != nil } }

    func suggestedURL(in home: URL?) -> URL? {
        guard let home else { return nil }
        let path: String
        switch self {
        case .android: path = ".android/avd"
        case .gradle: path = ".gradle"
        case .project: return home
        case .sdk: path = "Library/Android/sdk"
        case .xcode: path = "Library/Developer/Xcode/DerivedData"
        case .konan: path = ".konan"
        case .simulators: path = "Library/Developer/CoreSimulator/Devices"
        case .codex: path = ".codex"
        case .claudeCode: path = ".claude"
        case .chatGPT: path = "Library/Caches/com.openai.chat"
        case .cursor: path = "Library/Application Support/Cursor"
        case .gemini: path = ".gemini"
        case .copilot: path = ".copilot"
        case .ollama: path = ".ollama"
        }
        return home.appendingPathComponent(path, isDirectory: true)
    }
}

struct RoomDeveloperLocation: Identifiable {
    let role: RoomDeveloperFolderRole
    let folder: RoomAccessFolder
    var id: String { role.rawValue + ":" + folder.id }
}

struct RoomDeveloperFolderSuggestion: Identifiable {
    let role: RoomDeveloperFolderRole
    let url: URL?
    var id: String { role.rawValue }
}

@Observable @MainActor
final class RoomDeveloperModel {
    private struct RoleRecord: Codable, Equatable { let role: RoomDeveloperFolderRole; let folderID: String }
    private let access: RoomFileAccess
    private let defaults: UserDefaults
    @ObservationIgnored private let scanResources: @Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport
    private let key = "RoomDeveloperFolderRoles"
    private var records: [RoleRecord]
    private var stagedRemovals: Set<String> = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var section = RoomDeveloperSection.rooms
    private(set) var report: DeveloperResourcesReport?
    private(set) var devicesReport: DeveloperResourcesReport?
    private(set) var storageReport: DeveloperResourcesReport?
    private(set) var aiToolsReport: DeveloperResourcesReport?
    private(set) var summary: RoomDevSummary?
    private(set) var unreferenced: RoomDevUnreferenced
    @ObservationIgnored private let unreferencedStore: RoomDeveloperUnreferencedStore
    @ObservationIgnored private var unreferencedLoad: Task<Void, Never>?
    @ObservationIgnored private var unreferencedReadOnly = false
    @ObservationIgnored private let home: URL?
    @ObservationIgnored private let activityCenter: RoomActivityCenter?
    private(set) var isScanning = false
    private(set) var isChoosingFolder = false
    private(set) var progress = ""
    var errorMessage: String?

    init(access: RoomFileAccess = .shared, defaults: UserDefaults = .standard,
         unreferencedStore: RoomDeveloperUnreferencedStore = .init(),
         home: URL? = RoomDeveloperModel.standardHome,
         activityCenter: RoomActivityCenter? = nil,
         scanner: (@Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport)? = nil) {
        self.access = access
        self.defaults = defaults
        self.home = home
        self.activityCenter = activityCenter
        self.unreferencedStore = unreferencedStore
        self.unreferenced = unreferencedStore.writer == nil ? unreferencedStore.load() : .init()
        let engine = DeveloperResourcesEngine()
        self.scanResources = scanner ?? { request, progress in await engine.scan(request: request, progress: progress) }
        records = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RoleRecord].self, from: $0) } ?? []
        if unreferencedStore.writer != nil {
            unreferencedLoad = Task { [weak self] in
                let saved = await unreferencedStore.loadState()
                guard let self, !Task.isCancelled else { return }
                if let record = saved.value { self.unreferenced = record }
                self.unreferencedReadOnly = saved.isReadOnly
            }
        }
    }

    static var standardHome: URL? {
        #if ROOM_APP_STORE
        RoomStoreEnvironment.userHome
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    var projectRootLabel: String? {
        guard let root = locations.first(where: { $0.role == .project })?.folder.url else { return nil }
        let path = root.standardizedFileURL.path
        guard let home else { return path }
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    var folderSuggestions: [RoomDeveloperFolderSuggestion] {
        let configured = Set(locations.map(\.role))
        let roles = section == .devices ? RoomDeveloperFolderRole.deviceRoles : RoomDeveloperFolderRole.allCases
        return roles.filter {
            $0 != .project && !configured.contains($0) && ($0.aiTool != nil) == (section == .aiTools)
        }.compactMap { role in
            let url = role.suggestedURL(in: home)
            #if ROOM_APP_STORE
            return RoomDeveloperFolderSuggestion(role: role, url: url)
            #else
            if role == .simulators || role.aiTool != nil { return RoomDeveloperFolderSuggestion(role: role, url: url) }
            var directory: ObjCBool = false
            guard let url, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
                  directory.boolValue else { return nil }
            return RoomDeveloperFolderSuggestion(role: role, url: url)
            #endif
        }
    }

    func useSuggestion(_ suggestion: RoomDeveloperFolderSuggestion) {
        #if ROOM_APP_STORE
        addFolder(role: suggestion.role)
        #else
        if suggestion.role == .simulators || suggestion.role.aiTool != nil {
            addFolder(role: suggestion.role)
            return
        }
        guard !isScanning, !isChoosingFolder,
              folderSuggestions.contains(where: { $0.role == suggestion.role && $0.url == suggestion.url }),
              let url = suggestion.url else { return }
        remember(url, role: suggestion.role)
        #endif
    }

    var locations: [RoomDeveloperLocation] {
        records.compactMap { record in
            access.folders.first(where: { $0.id == record.folderID }).map { RoomDeveloperLocation(role: record.role, folder: $0) }
        }.filter { !stagedRemovals.contains($0.id) }
    }
    private var scanLocations: [RoomDeveloperLocation] {
        switch section {
        case .devices: locations.filter { RoomDeveloperFolderRole.deviceRoles.contains($0.role) }
        case .storage: locations.filter { $0.role.supportsToolStorage }
        case .aiTools: locations.filter { $0.role.aiTool != nil }
        default: locations.filter { $0.role != .simulators && $0.role.aiTool == nil }
        }
    }
    var sectionLocations: [RoomDeveloperLocation] {
        if section == .devices { return scanLocations }
        return locations.filter { ($0.role.aiTool != nil) == (section == .aiTools) }
    }
    var canScan: Bool { !isChoosingFolder && !scanLocations.isEmpty }
    var accessRevision: [String] { access.folders.map(\.id).sorted() }
    var totalBytes: Int64 {
        guard let report else { return 0 }
        return RoomDeveloperPresentation.sum(report.androidDevices.map(\.allocatedBytes) + report.gradleResources.map(\.allocatedBytes))
    }

    func addFolder(role: RoomDeveloperFolderRole) {
        guard !isChoosingFolder, !isScanning else { return }
        isChoosingFolder = true
        let message = role.aiTool != nil
            ? "Choose the tool’s data folder. Room measures known locations by file size alone."
            : role == .simulators
            ? "Choose the Simulator Devices folder to read device names and measure installed apps and device data."
            : "Room reads sizes and version files here. It never changes anything in this folder."
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingFolder = false }
            guard let selected = await RoomNativeFolderPicker.shared.choose(title: role.title,
                message: message,
                prompt: "Allow", initialURL: role.suggestedURL(in: self.home)) else { return }
            self.remember(selected, role: role)
        }
    }

    private func remember(_ selected: URL, role: RoomDeveloperFolderRole) {
        do {
            let url = try access.remember(selected)
            guard let folder = access.folders.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
            attach(role: role, to: folder.id)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Reuses only an already-approved shared bookmark; this never grants access.
    func attach(role: RoomDeveloperFolderRole, to folderID: String) {
        guard !isScanning, access.folders.contains(where: { $0.id == folderID }) else { return }
        let record = RoleRecord(role: role, folderID: folderID)
        if !records.contains(record) { records.append(record); persist() }
        report = nil; devicesReport = nil; storageReport = nil; aiToolsReport = nil; summary = nil
    }

    func stageRemoval(_ location: RoomDeveloperLocation) {
        guard !isScanning else { return }
        stagedRemovals.insert(location.id)
        report = nil
        devicesReport = nil
        storageReport = nil
        aiToolsReport = nil
        summary = nil
    }

    func undoRemoval(_ location: RoomDeveloperLocation) {
        guard stagedRemovals.remove(location.id) != nil else { return }
        accessChanged()
    }

    func commitRemoval(_ location: RoomDeveloperLocation) {
        guard stagedRemovals.remove(location.id) != nil else { return }
        records.removeAll { $0.role == location.role && $0.folderID == location.folder.id }
        persist()
    }

    func accessChanged() {
        generation = UUID()
        task?.cancel(); task = nil; isScanning = false
        activityCenter?.clear(.developer)
        report = nil; devicesReport = nil; storageReport = nil; aiToolsReport = nil; summary = nil; progress = ""
    }

    func scan() {
        guard canScan, !isScanning else { return }
        let scope: DeveloperResourcesScope = switch section {
        case .devices: .devices
        case .storage: .toolStorage
        case .aiTools: .aiTools
        default: .review
        }
        let current = scanLocations
        let approved = Dictionary(grouping: current.map(\.folder.url), by: \.path).compactMap { $0.value.first }
        let request = DeveloperResourcesRequest(approvedFolders: approved,
            avdRoots: current.filter { $0.role == .android }.map(\.folder.url),
            gradleHomes: current.filter { $0.role == .gradle }.map(\.folder.url),
            projectRoots: current.filter { $0.role == .project }.map(\.folder.url),
            sdkRoots: current.filter { $0.role == .sdk }.map(\.folder.url),
            derivedDataRoots: current.filter { $0.role == .xcode }.map(\.folder.url),
            konanRoots: current.filter { $0.role == .konan }.map(\.folder.url),
            simulatorDeviceRoots: current.filter { $0.role == .simulators }.map(\.folder.url),
            aiToolRoots: current.compactMap { location in
                location.role.aiTool.map { DeveloperAIToolRoot(tool: $0, url: location.folder.url) }
            }, scope: scope)
        let token = UUID(); generation = token
        isScanning = true; errorMessage = nil; progress = "Preparing review…"
        activityCenter?.reportScanLabel(.developer, label: section.rawValue, files: 0, bytes: 0)
        let scanner = scanResources
        task = Task { [weak self] in
            let scopes = approved.filter { $0.startAccessingSecurityScopedResource() }
            defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
            let result = await scanner(request) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.progress = "\(update.phase) · \(update.inspectedCount.formatted()) items"
                    self.activityCenter?.reportScanLabel(.developer, label: update.phase, files: update.inspectedCount, bytes: 0)
                }
            }
            if scope == .review { await self?.unreferencedLoad?.value }
            guard let self, self.generation == token else { return }
            switch scope {
            case .devices: self.devicesReport = result
            case .toolStorage: self.storageReport = result
            case .aiTools: self.aiToolsReport = result
            case .review: self.applyReview(result)
            }
            self.isScanning = false
            self.task = nil
            self.activityCenter?.clear(.developer)
            self.progress = result.cancelled ? "Stopped · partial review" : (result.isPartial ? "Partial review" : "Review complete")
        }
    }

    private func applyReview(_ result: DeveloperResourcesReport) {
        report = result
        let summary = RoomDeveloperRooms.summarize(projects: result.projects, artifacts: result.toolchains,
                                                   scanPartial: result.isPartial || result.cancelled)
        self.summary = summary
        let orphanKeys = Set(summary.orphans.map { $0.artifact.key })
        let referencedKeys = Set(result.toolchains.map(\.key)).subtracting(orphanKeys)
        let updated = unreferenced.updated(orphanKeys: orphanKeys, referencedKeys: referencedKeys,
                                          scanComplete: !summary.partial, now: result.scannedAt)
        if updated != unreferenced {
            unreferenced = updated
            if !unreferencedReadOnly { unreferencedStore.save(updated) }
        }
    }

    func clearUnreferencedHistory() {
        unreferencedLoad?.cancel()
        unreferencedLoad = nil
        unreferencedStore.writer?.discardPending(for: .developerUnreferenced)
        unreferenced = RoomDevUnreferenced()
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
