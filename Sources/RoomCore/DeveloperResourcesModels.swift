import Foundation

public struct DeveloperResourcesLimits: Sendable {
    public let maximumNodes: Int
    public let maximumDepth: Int
    public let maximumResources: Int
    public let maximumFileBytes: Int
    public let maximumProjectFileBytes: Int
    public let timeLimit: TimeInterval

    public init(maximumNodes: Int = 100_000, maximumDepth: Int = 18, maximumResources: Int = 256,
                maximumFileBytes: Int? = nil, timeLimit: TimeInterval = 12) {
        self.maximumNodes = min(500_000, max(1, maximumNodes))
        self.maximumDepth = min(64, max(1, maximumDepth))
        self.maximumResources = min(1_024, max(1, maximumResources))
        self.maximumFileBytes = min(262_144, max(64, maximumFileBytes ?? 65_536))
        self.maximumProjectFileBytes = min(262_144, max(64, maximumFileBytes ?? 262_144))
        self.timeLimit = min(60, max(0, timeLimit))
    }
}

/// Evidence supplied by the caller is observational. An empty or incomplete
/// sample never establishes that a device or Gradle version is unused.
public struct DeveloperResourceProcess: Codable, Equatable, Sendable {
    public let processID: Int32
    public let name: String
    public let paths: [URL]
    public let avdNames: [String]
    public init(processID: Int32, name: String, paths: [URL] = [], avdNames: [String] = []) {
        self.processID = processID; self.name = String(name.prefix(160))
        self.paths = Array(paths.prefix(256)); self.avdNames = Array(avdNames.prefix(32)).map { String($0.prefix(160)) }
    }
}

public struct DeveloperActivitySnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let processes: [DeveloperResourceProcess]
    public let isComplete: Bool
    public init(sampledAt: Date = Date(), processes: [DeveloperResourceProcess] = [], isComplete: Bool = false) {
        self.sampledAt = sampledAt; self.processes = Array(processes.prefix(4_096)); self.isComplete = isComplete
    }
    public static var unknown: Self { Self() }
}

public enum DeveloperResourcesScope: Sendable {
    case review, devices, toolStorage, aiTools
}

public enum DeveloperAITool: String, CaseIterable, Codable, Sendable {
    case codex, claudeCode, chatGPT, cursor, gemini, copilot, ollama
}

public struct DeveloperAIToolRoot: Sendable {
    public let tool: DeveloperAITool
    public let url: URL

    public init(tool: DeveloperAITool, url: URL) {
        self.tool = tool
        self.url = url
    }
}

public struct DeveloperResourcesRequest: Sendable {
    public let approvedFolders: [URL]
    public let avdRoots: [URL]
    public let gradleHomes: [URL]
    public let projectRoots: [URL]
    public let sdkRoots: [URL]
    public let derivedDataRoots: [URL]
    public let konanRoots: [URL]
    public let simulatorDeviceRoots: [URL]
    public let aiToolRoots: [DeveloperAIToolRoot]
    public let scope: DeveloperResourcesScope
    public let activity: DeveloperActivitySnapshot
    public let limits: DeveloperResourcesLimits

    public init(approvedFolders: [URL], avdRoots: [URL] = [], gradleHomes: [URL] = [], projectRoots: [URL] = [],
                sdkRoots: [URL] = [], derivedDataRoots: [URL] = [], konanRoots: [URL] = [], simulatorDeviceRoots: [URL] = [],
                aiToolRoots: [DeveloperAIToolRoot] = [], scope: DeveloperResourcesScope = .review,
                activity: DeveloperActivitySnapshot = .unknown,
                limits: DeveloperResourcesLimits = .init()) {
        self.approvedFolders = approvedFolders; self.avdRoots = avdRoots
        self.gradleHomes = gradleHomes; self.projectRoots = projectRoots
        self.sdkRoots = sdkRoots; self.derivedDataRoots = derivedDataRoots; self.konanRoots = konanRoots
        self.simulatorDeviceRoots = simulatorDeviceRoots
        self.aiToolRoots = aiToolRoots
        self.scope = scope
        self.activity = activity; self.limits = limits
    }
}

public enum DeveloperResourceEvidenceKind: String, Codable, Sendable {
    case configurationChanged, launchRecordChanged, logChanged, snapshotChanged, lockPresent, filesystemChanged
}

public struct DeveloperResourceEvidence: Identifiable, Codable, Equatable, Sendable {
    public var id: String { kind.rawValue + ":" + url.path }
    public let kind: DeveloperResourceEvidenceKind
    public let label: String
    public let url: URL
    public let date: Date?
    public let uncertainty: String
}

public enum DeveloperResourceActivityState: String, Codable, Sendable {
    case observedUse, possibleUse, notObserved, unknown
}

public struct DeveloperResourceActivity: Codable, Equatable, Sendable {
    public let state: DeveloperResourceActivityState
    public let processIDs: [Int32]
    public let indicators: [String]
    public let sampledAt: Date
}

public struct AndroidVirtualDeviceResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let displayName: String
    public let apiLevel: String?
    public let abi: String?
    public let device: String?
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let isPartial: Bool
    /// Standard AVD file metadata does not provide verified launch history.
    public let lastUsedAt: Date?
    public let lastUseNote: String
    public let evidence: [DeveloperResourceEvidence]
    public let activity: DeveloperResourceActivity
}

public struct SimulatorDeviceResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let displayName: String
    public let runtimeIdentifier: String?
    public let deviceTypeIdentifier: String?
    public let allocatedBytes: Int64
    public let isPartial: Bool
}

public enum GradleDeveloperResourceKind: String, Codable, Sendable {
    case distribution, versionCache, sharedCache
}

public struct GradleProjectWrapper: Identifiable, Codable, Equatable, Sendable {
    public var id: String { propertiesURL.path }
    public let projectURL: URL
    public let propertiesURL: URL
    public let version: String?
    public let distributionType: String?
    public let note: String
    public let isPartial: Bool
}

public struct GradleDeveloperResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: GradleDeveloperResourceKind
    public let version: String?
    public let distributionType: String?
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let isPartial: Bool
    public let projectUses: [GradleProjectWrapper]
    public let usageNote: String
    public let evidence: [DeveloperResourceEvidence]
    public let activity: DeveloperResourceActivity
}

public struct DeveloperResourcesProgress: Sendable {
    public let phase: String
    public let inspectedCount: Int
    public let currentPath: String
}

public enum DeveloperStorageKind: String, Codable, Sendable {
    case gradleDaemon, gradleJDKs, androidSystemImages, simulatorDevices
}

public struct DeveloperStorageResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { kind.rawValue + ":" + url.path }
    public let kind: DeveloperStorageKind
    public let url: URL
    public let allocatedBytes: Int64
    public let isPartial: Bool
}

public enum DeveloperAIStorageCategory: String, Codable, Sendable {
    case cache, history, diagnostics, runtime, worktrees
}

public struct DeveloperAIStorageResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { tool.rawValue + ":" + url.path }
    public let tool: DeveloperAITool
    public let title: String
    public let url: URL
    public let allocatedBytes: Int64
    public let isPartial: Bool
    public let category: DeveloperAIStorageCategory
}

public struct DeveloperResourcesReport: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let scannedAt: Date
    public let androidDevices: [AndroidVirtualDeviceResource]
    public let gradleResources: [GradleDeveloperResource]
    public let projectWrappers: [GradleProjectWrapper]
    private let recordedProjects: [DeveloperProject]?
    private let recordedToolchains: [DeveloperToolchainResource]?
    private let recordedStorageResources: [DeveloperStorageResource]?
    private let recordedAIStorageResources: [DeveloperAIStorageResource]?
    private let recordedSimulatorDevices: [SimulatorDeviceResource]?
    public var projects: [DeveloperProject] { recordedProjects ?? [] }
    public var toolchains: [DeveloperToolchainResource] { recordedToolchains ?? [] }
    public var storageResources: [DeveloperStorageResource] { recordedStorageResources ?? [] }
    public var aiStorageResources: [DeveloperAIStorageResource] { recordedAIStorageResources ?? [] }
    public var simulatorDevices: [SimulatorDeviceResource] { recordedSimulatorDevices ?? [] }
    public let issues: [ScanIssue]
    public let cancelled: Bool
    public let isPartial: Bool

    enum CodingKeys: String, CodingKey {
        case id, scannedAt, androidDevices, gradleResources, projectWrappers, issues, cancelled, isPartial
        case recordedProjects = "projects", recordedToolchains = "toolchains"
        case recordedStorageResources = "storageResources"
        case recordedAIStorageResources = "aiStorageResources"
        case recordedSimulatorDevices = "simulatorDevices"
    }

    init(id: UUID, scannedAt: Date, androidDevices: [AndroidVirtualDeviceResource],
         gradleResources: [GradleDeveloperResource], projectWrappers: [GradleProjectWrapper],
         projects: [DeveloperProject] = [], toolchains: [DeveloperToolchainResource] = [],
         storageResources: [DeveloperStorageResource] = [], aiStorageResources: [DeveloperAIStorageResource] = [],
         simulatorDevices: [SimulatorDeviceResource] = [],
         issues: [ScanIssue], cancelled: Bool, isPartial: Bool) {
        self.id = id
        self.scannedAt = scannedAt
        self.androidDevices = androidDevices
        self.gradleResources = gradleResources
        self.projectWrappers = projectWrappers
        self.recordedProjects = projects
        self.recordedToolchains = toolchains
        self.recordedStorageResources = storageResources
        self.recordedAIStorageResources = aiStorageResources
        self.recordedSimulatorDevices = simulatorDevices
        self.issues = issues
        self.cancelled = cancelled
        self.isPartial = isPartial
    }
}
