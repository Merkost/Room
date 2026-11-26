import Foundation
import Observation
import RoomCore

/// Roles reference shared read-only bookmarks; no second set of permissions is stored.
enum RoomDeveloperFolderRole: String, CaseIterable, Codable, Identifiable {
    case android, gradle, project, sdk, xcode, konan, simulators, simulatorRuntimes
    case codex, claudeCode, chatGPT, cursor, gemini, copilot, ollama
    var id: String { rawValue }
    var requiresFolderPicker: Bool { self == .simulators || self == .simulatorRuntimes || aiTool != nil }
    static let storageRoles: [Self] = [.gradle, .sdk, .simulators, .simulatorRuntimes]
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
        case .simulatorRuntimes: "Simulator Runtimes"
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
        case .simulatorRuntimes: "opticaldiscdrive"
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
        let path: String
        switch self {
        case .android: path = ".android/avd"
        case .gradle: path = ".gradle"
        case .project: return home
        case .sdk: path = "Library/Android/sdk"
        case .xcode: path = "Library/Developer/Xcode/DerivedData"
        case .konan: path = ".konan"
        case .simulators: path = "Library/Developer/CoreSimulator/Devices"
        case .simulatorRuntimes:
            return URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", isDirectory: true)
        case .codex: path = ".codex"
        case .claudeCode: path = ".claude"
        case .chatGPT: path = "Library/Caches/com.openai.chat"
        case .cursor: path = "Library/Application Support/Cursor"
        case .gemini: path = ".gemini"
        case .copilot: path = ".copilot"
        case .ollama: path = ".ollama"
        }
        return home?.appendingPathComponent(path, isDirectory: true)
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

nonisolated struct RoomDeveloperScanPart: Equatable, Sendable {
    enum State: Equatable, Sendable { case waiting, reading, done, stopped }
    let scope: DeveloperResourcesScope
    var state: State
}

/// Agent worktrees are read by their own engine (Direct edition); Developer's one scan starts and stops them too.
@MainActor
protocol RoomDeveloperWorktreeScanning: AnyObject {
    var isScanning: Bool { get }
    /// A remote check or a move is running, so a scan would be refused.
    var isBusy: Bool { get }
    /// What the last read found the worktrees to hold; nil before one.
    var measuredBytes: Int64? { get }
    func scan()
    func stop()
    func waitForScan() async
}

@Observable @MainActor
final class RoomDeveloperModel {
    private struct RoleRecord: Codable, Equatable { let role: RoomDeveloperFolderRole; let folderID: String }
    private let access: RoomFileAccess
    private let defaults: UserDefaults
    @ObservationIgnored private let sampleActivity: @Sendable () async -> DeveloperActivitySnapshot
    @ObservationIgnored private let scanResources: @Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport
    private let key = "RoomDeveloperFolderRoles"
    private var records: [RoleRecord]
    private var stagedRemovals: Set<String> = []
    /// The approvals the current results were read through, as `accessRevision` entries.
    @ObservationIgnored private var scannedAccess: Set<String> = []
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
    var worktrees: (any RoomDeveloperWorktreeScanning)?
    /// True while the one scan runs: the folder parts, then any worktrees still being read.
    private var isScanningResources = false
    private(set) var isChoosingFolder = false
    private var resourceProgress = ""
    /// The parts of the running (or last) scan, for the scan animation.
    private(set) var scanParts: [RoomDeveloperScanPart] = []
    private(set) var scanIncludedWorktrees = false
    var isScanning: Bool { isScanningResources || worktrees?.isScanning == true }
    var progress: String {
        !isScanningResources && worktrees?.isScanning == true ? Self.worktreesProgress : resourceProgress
    }
    private static let worktreesProgress = "Reading agent worktrees…"
    var errorMessage: String?

    init(access: RoomFileAccess = .shared, defaults: UserDefaults = .standard,
         unreferencedStore: RoomDeveloperUnreferencedStore = .init(),
         home: URL? = RoomDeveloperModel.standardHome,
         activityCenter: RoomActivityCenter? = nil,
         scanner: (@Sendable (DeveloperResourcesRequest, (@Sendable (DeveloperResourcesProgress) -> Void)?) async -> DeveloperResourcesReport)? = nil,
         activitySampler: (@Sendable () async -> DeveloperActivitySnapshot)? = nil) {
        self.access = access
        self.defaults = defaults
        self.home = home
        self.activityCenter = activityCenter
        self.unreferencedStore = unreferencedStore
        self.unreferenced = unreferencedStore.writer == nil ? unreferencedStore.load() : .init()
        if let activitySampler { self.sampleActivity = activitySampler }
        else if scanner != nil { self.sampleActivity = { .unknown } }
        else { self.sampleActivity = { await DeveloperResourcesEngine.activitySnapshot() } }
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
        return selectableFolderRoles.filter { !configured.contains($0) }.compactMap { role in
            let url = role.suggestedURL(in: home)
            #if ROOM_APP_STORE
            return RoomDeveloperFolderSuggestion(role: role, url: url)
            #else
            if role.requiresFolderPicker { return RoomDeveloperFolderSuggestion(role: role, url: url) }
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
        if suggestion.role.requiresFolderPicker {
            addFolder(role: suggestion.role)
            return
        }
        guard !isScanning, !isChoosingFolder,
              folderSuggestions.contains(where: { $0.role == suggestion.role && $0.url == suggestion.url }),
              let url = suggestion.url else { return }
        remember(url, role: suggestion.role)
        #endif
    }

    var selectableFolderRoles: [RoomDeveloperFolderRole] {
        switch section {
        case .devices: RoomDeveloperFolderRole.deviceRoles
        case .storage: RoomDeveloperFolderRole.storageRoles
        case .aiTools: RoomDeveloperFolderRole.aiRoles
        default: RoomDeveloperFolderRole.allCases.filter { $0 != .project && $0 != .simulatorRuntimes && $0.aiTool == nil }
        }
    }

    var locations: [RoomDeveloperLocation] {
        records.compactMap { record in
            access.folders.first(where: { $0.id == record.folderID }).map { RoomDeveloperLocation(role: record.role, folder: $0) }
        }.filter { !stagedRemovals.contains($0.id) }
    }

    func reusableFolders(for role: RoomDeveloperFolderRole) -> [RoomAccessFolder] {
        let attached = Set(records.filter { $0.role == role }.map(\.folderID))
        return access.folders.filter { !attached.contains($0.id) }.sorted {
            $0.url.path == $1.url.path ? $0.id < $1.id : $0.url.path < $1.url.path
        }
    }
    private func scanLocations(for scope: DeveloperResourcesScope) -> [RoomDeveloperLocation] {
        switch scope {
        case .devices: locations.filter { RoomDeveloperFolderRole.deviceRoles.contains($0.role) }
        case .toolStorage: locations.filter { RoomDeveloperFolderRole.storageRoles.contains($0.role) }
        case .aiTools: locations.filter { $0.role.aiTool != nil }
        case .review: locations.filter { $0.role != .simulators && $0.role != .simulatorRuntimes && $0.role.aiTool == nil }
        }
    }
    /// Everything one scan reads, in order; a part with no folder is left out.
    private var scanPlan: [(scope: DeveloperResourcesScope, locations: [RoomDeveloperLocation])] {
        [DeveloperResourcesScope.review, .devices, .toolStorage, .aiTools]
            .map { ($0, scanLocations(for: $0)) }.filter { !$0.1.isEmpty }
    }
    var sectionLocations: [RoomDeveloperLocation] {
        switch section {
        case .devices: scanLocations(for: .devices)
        case .storage: scanLocations(for: .toolStorage)
        case .aiTools: scanLocations(for: .aiTools)
        default: locations.filter { $0.role != .simulatorRuntimes && $0.role.aiTool == nil }
        }
    }
    var hasScannableFolders: Bool { !scanPlan.isEmpty }
    /// The same answer from every section: one scan reads them all.
    var canScan: Bool { !isChoosingFolder && worktrees?.isBusy != true && (hasScannableFolders || worktrees != nil) }
    /// Whether a scan has anything to read for the open section (Simulator folders do not feed Rooms or Matrix).
    var hasFoldersForSection: Bool {
        let scope: DeveloperResourcesScope = switch section {
        case .devices: .devices
        case .storage: .toolStorage
        case .aiTools: .aiTools
        default: .review
        }
        return !scanLocations(for: scope).isEmpty
    }
    var accessRevision: [String] { access.folders.map { $0.id + ":" + $0.url.path }.sorted() }
    var totalBytes: Int64 {
        guard let report else { return 0 }
        return RoomDeveloperPresentation.sum(report.androidDevices.map(\.allocatedBytes) + report.gradleResources.map(\.allocatedBytes))
    }

    func addFolder(role: RoomDeveloperFolderRole) {
        guard !isChoosingFolder, !isScanning else { return }
        isChoosingFolder = true
        let message = switch role {
        case .simulators: "Choose the Simulator Devices folder to measure each device’s installed apps and data."
        case .simulatorRuntimes: "Choose Simulator runtime bundles, Xcode runtime exports, or a folder containing their backing images."
        case _ where role.aiTool != nil: "Choose the tool’s data folder. Room measures known locations by file size alone."
        default: "Room reads sizes and version files here. It never changes anything in this folder."
        }
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChoosingFolder = false }
            guard let selected = await RoomNativeFolderPicker.shared.choose(title: role.title,
                message: message,
                prompt: "Allow", initialURL: role.suggestedURL(in: self.home),
                treatsFilePackagesAsDirectories: role == .simulatorRuntimes) else { return }
            self.remember(selected, role: role)
        }
    }

    #if DEBUG
    func debugRemember(_ url: URL, role: RoomDeveloperFolderRole) { remember(url, role: role) }
    /// Screenshot fixture only: finished reports for every room without reading any folder.
    func debugInstall(review: DeveloperResourcesReport?, devices: DeveloperResourcesReport?,
                      storage: DeveloperResourcesReport?, aiTools: DeveloperResourcesReport?) {
        if let review { applyReview(review) }
        devicesReport = devices
        storageReport = storage
        aiToolsReport = aiTools
        resourceProgress = "Review complete"
    }
    #endif

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
        guard !records.contains(record) else { return }
        records.append(record)
        persist()
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

    /// An approval changed. Only losing one that was read through discards the work: adding another folder (Overview's
    /// scan approving Home, say) must not cancel it.
    func accessChanged() {
        guard !scannedAccess.isSubset(of: Set(accessRevision)) else { return }
        scannedAccess = []
        scanParts = []; scanIncludedWorktrees = false
        generation = UUID()
        task?.cancel(); task = nil; isScanningResources = false
        activityCenter?.clear(.developer)
        report = nil; devicesReport = nil; storageReport = nil; aiToolsReport = nil; summary = nil; resourceProgress = ""
    }

    /// Reads every part that has a folder, one after another; each section fills as its part finishes.
    func scan() {
        guard canScan, !isScanning else { return }
        let plan = scanPlan
        errorMessage = nil
        worktrees?.scan()
        let token = UUID(); generation = token
        scannedAccess.formUnion(plan.flatMap(\.locations).map { $0.folder.id + ":" + $0.folder.url.path })
        scanParts = plan.map { RoomDeveloperScanPart(scope: $0.scope, state: .waiting) }
        scanIncludedWorktrees = worktrees != nil
        isScanningResources = true; resourceProgress = plan.isEmpty ? Self.worktreesProgress : "Preparing review…"
        activityCenter?.reportScanLabel(.developer, label: "Developer", files: 0, bytes: 0)
        task = Task { [weak self] in
            var activity: DeveloperActivitySnapshot?
            var cancelled = false
            var partial = false
            for part in plan {
                self?.mark(part.scope, .reading, token: token)
                guard let result = await self?.read(part.scope, in: part.locations, activity: &activity, token: token) else { return }
                cancelled = result.cancelled || Task.isCancelled
                self?.mark(part.scope, cancelled ? .stopped : .done, token: token)
                partial = partial || result.isPartial
                if cancelled { break }
            }
            // Worktrees are read alongside; the scan (and its activity pill) ends when they do.
            if let worktrees = self?.worktrees, worktrees.isScanning {
                self?.showWorktreesProgress(token: token)
                await worktrees.waitForScan()
            }
            cancelled = cancelled || Task.isCancelled
            self?.finishScan(token: token, progress: cancelled ? "Stopped · partial review" : (partial ? "Partial review" : "Review complete"))
        }
    }

    /// One part of the scan. nil: the scan was replaced, or stopped before this part started reading.
    private func read(_ scope: DeveloperResourcesScope, in current: [RoomDeveloperLocation],
                      activity: inout DeveloperActivitySnapshot?, token: UUID) async -> DeveloperResourcesReport? {
        let approved = Dictionary(grouping: current.map(\.folder.url), by: \.path).compactMap { $0.value.first }
        let avdRoots = current.filter { $0.role == .android }.map(\.folder.url)
        let scopes = approved.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        // Processes are sampled once per scan, and only when Android devices are part of it.
        if !avdRoots.isEmpty, activity == nil { activity = await sampleActivity() }
        guard generation == token else { return nil }
        guard !Task.isCancelled else {
            finishScan(token: token, progress: report == nil && devicesReport == nil && storageReport == nil && aiToolsReport == nil
                ? "Stopped · no resource scan started" : "Stopped · partial review")
            return nil
        }
        let request = DeveloperResourcesRequest(approvedFolders: approved, avdRoots: avdRoots,
            gradleHomes: current.filter { $0.role == .gradle }.map(\.folder.url),
            projectRoots: current.filter { $0.role == .project }.map(\.folder.url),
            sdkRoots: current.filter { $0.role == .sdk }.map(\.folder.url),
            derivedDataRoots: current.filter { $0.role == .xcode }.map(\.folder.url),
            konanRoots: current.filter { $0.role == .konan }.map(\.folder.url),
            simulatorDeviceRoots: current.filter { $0.role == .simulators }.map(\.folder.url),
            simulatorRuntimeRoots: current.filter { $0.role == .simulatorRuntimes }.map(\.folder.url),
            aiToolRoots: current.compactMap { location in
                location.role.aiTool.map { DeveloperAIToolRoot(tool: $0, url: location.folder.url) }
            }, scope: scope, activity: activity ?? .unknown)
        let result = await scanResources(request) { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.isScanningResources else { return }
                self.resourceProgress = "\(update.phase) · \(update.inspectedCount.formatted()) items"
                self.activityCenter?.reportScanLabel(.developer, label: update.phase, files: update.inspectedCount, bytes: 0)
            }
        }
        if scope == .review { await unreferencedLoad?.value }
        guard generation == token else { return nil }
        switch scope {
        case .devices: devicesReport = result
        case .toolStorage: storageReport = result
        case .aiTools: aiToolsReport = result
        case .review: applyReview(result)
        }
        return result
    }

    private func mark(_ scope: DeveloperResourcesScope, _ state: RoomDeveloperScanPart.State, token: UUID) {
        guard generation == token, let index = scanParts.firstIndex(where: { $0.scope == scope }) else { return }
        scanParts[index].state = state
    }

    private func showWorktreesProgress(token: UUID) {
        guard generation == token else { return }
        resourceProgress = Self.worktreesProgress
        activityCenter?.reportScanLabel(.developer, label: "Agent worktrees", files: 0, bytes: 0)
    }

    private func finishScan(token: UUID, progress: String) {
        guard generation == token else { return }
        isScanningResources = false
        task = nil
        for index in scanParts.indices where scanParts[index].state != .done { scanParts[index].state = .stopped }
        activityCenter?.clear(.developer)
        resourceProgress = progress
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

    func stop() {
        if worktrees?.isScanning == true { worktrees?.stop() }
        guard isScanningResources else { return }
        task?.cancel()
        resourceProgress = "Stopping…"
    }
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
