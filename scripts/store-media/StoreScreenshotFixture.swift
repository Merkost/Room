import AppKit
import CryptoKit
import Foundation
@testable import RoomApp
@testable import RoomCore
import SwiftUI

@main
struct StoreScreenshotEntry {
    @MainActor static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    @MainActor private static func run() throws {
        guard let output = ProcessInfo.processInfo.environment["ROOM_MAIN_MENU_TEST_OUTPUT"] else {
            FileHandle.standardError.write(Data("Launch the fixture with launch-fixture.zsh to isolate app state.\n".utf8))
            exit(2)
        }
        let directory = URL(fileURLWithPath: output).deletingLastPathComponent()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        _ = RoomDisplayFont.register()
        let fixture = try StoreScreenshotFixture(directory: directory)
        let frame = NSRect(origin: .zero, size: fixture.windowSize)
        let window = NSWindow(contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Room Screenshot Fixture"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: fixture)
        window.setContentSize(fixture.windowSize)
        window.center()
        if CommandLine.arguments.contains("--interactive") {
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                app.activate()
            }
        } else {
            window.orderBack(nil)
        }
        try String(ProcessInfo.processInfo.processIdentifier).write(
            to: directory.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
        withExtendedLifetime(window) { app.run() }
    }
}

struct StoreScreenshotFixture: View {
    private enum Screen: String {
        case overview, diskMap = "disk-map", cachesReview = "caches-review", developer, aiTools = "ai-tools", memory, monitor
        case caches, history, settings
    }
    /// `--light` captures the light appearance (the nav-v3 mockup frames are light).
    private static var light: Bool { CommandLine.arguments.contains("--light") }

    private let screen: Screen
    private let navigation: RoomWindowNavigation
    private let insights: RoomInsightsModel
    private let caches: RoomViewModel
    private let activity: RoomActivityCenter
    private let rooms: RoomRoomsModel
    private let developer: RoomDeveloperModel
    private let workspace: URL
    private let approvalID: String?
    private let treeStore: RoomTreeStore
    private let memoryActions = MemoryActionsModel()
    @State private var ready = false
    @State private var showReview = false

    init(directory: URL) throws {
        let scene = CommandLine.arguments.dropFirst().first ?? "overview"
        screen = Screen(rawValue: scene) ?? .overview
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: RoomOverviewPreferences.roomsChapterKey)
        defaults.set(RoomOnboardingFlow.version, forKey: "RoomOnboardingVersion")
        defaults.set(Self.light ? "light" : "dark", forKey: "RoomAppearance")
        defaults.set("teal", forKey: "RoomAccent")

        let sampleHome = directory.appendingPathComponent("Sample Home", isDirectory: true)
        workspace = sampleHome.appendingPathComponent("Studio Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Mobile Studio", isDirectory: true),
            withIntermediateDirectories: true)
        let sampleDefaults = UserDefaults(suiteName: "dev.merkost.room.screenshot-fixture.\(UUID())")!
        sampleDefaults.set(RoomOnboardingFlow.version, forKey: "RoomOnboardingVersion")
        let access = RoomFileAccess(defaults: sampleDefaults)
        _ = try? access.remember(workspace)
        approvalID = access.folders.first?.id
        if let approvalID,
           let role = try? JSONSerialization.data(withJSONObject: [["role": "project", "folderID": approvalID]]) {
            sampleDefaults.set(role, forKey: "RoomDeveloperFolderRoles")
        }

        let state = RoomStateStore(directory: directory)
        treeStore = RoomTreeStore(state: state)
        activity = RoomActivityCenter()
        let pressureStore = RoomPressureHistoryStore(directory: directory)
        pressureStore.save(Self.pressureHistory())
        insights = RoomInsightsModel(access: access, treeStore: treeStore,
            capacityReader: { RoomVolumeCapacity(capacityBytes: 500_000_000_000, freeBytes: 120_000_000_000,
                volumeID: "sample-volume", volumeName: "Macintosh HD") },
            pressureStore: pressureStore, activityCenter: activity, readMemory: { Self.memoryReport() })
        rooms = RoomRoomsModel(store: RoomRoomsStore(directory: directory), access: access)

        navigation = RoomWindowNavigation(defaults: sampleDefaults)
        switch screen {
        case .overview, .monitor: navigation.select(.overview)
        case .diskMap: navigation.select(.disk)
        case .cachesReview: navigation.select(.clean)
        case .developer, .aiTools: navigation.select(.developer)
        case .memory: navigation.select(.memory)
        case .caches: navigation.select(.clean)
        case .history: navigation.select(.history)
        case .settings: navigation.select(.settings)
        }
        let approvedCaches: [URL]
        if screen == .cachesReview || screen == .caches {
            let npm = try Self.sampleNPM(in: sampleHome)
            approvedCaches = [npm]
        } else {
            approvedCaches = []
        }
        let engine = CacheEngine(
            configuration: .store(approvedFolders: approvedCaches, userHome: sampleHome),
            activityDirectory: directory.appendingPathComponent("Activity"),
            processProvider: { [] }, fixtureTrashDirectory: sampleHome.appendingPathComponent(".Trash"),
            trashProvider: { _ in throw CocoaError(.fileWriteNoPermission) })
        caches = RoomViewModel(engine: engine, cachesCheckStore: RoomCachesCheckStore(defaults: sampleDefaults), activityCenter: activity)
        let developerEngine = DeveloperResourcesEngine()
        developer = RoomDeveloperModel(access: access, defaults: sampleDefaults,
            unreferencedStore: .init(directory: directory), home: sampleHome,
            scanner: { request, progress in
                if request.scope == .aiTools { return await developerEngine.scan(request: request, progress: progress) }
                return Self.developerReport(workspace: sampleHome.appendingPathComponent("Studio Projects"))
            })
        if screen == .aiTools {
            for (role, path, samples): (RoomDeveloperFolderRole, String, [(String, Int)]) in [
                (.codex, ".codex", [("cache/download.bin", 18), ("sessions/sample.jsonl", 12), ("worktrees/Example/.build/output.bin", 48)]),
                (.claudeCode, ".claude", [("cache/model-catalog/sample.bin", 3), ("projects/Example/history.jsonl", 20)]),
                (.ollama, ".ollama", [("models/blobs/sample.bin", 80)]),
            ] {
                let root = sampleHome.appendingPathComponent(path, isDirectory: true)
                for (name, megabytes) in samples {
                    let file = root.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(repeating: 0x45, count: megabytes * 1_048_576).write(to: file)
                }
                let approved = try access.remember(root)
                if let record = access.folders.first(where: { $0.url == approved }) {
                    developer.attach(role: role, to: record.id)
                }
            }
            developer.section = .aiTools
        }
    }

    var windowSize: CGSize {
        screen == .monitor ? CGSize(width: 340, height: 440) : CGSize(width: 1_280, height: 710)
    }

    var body: some View {
        fixtureContent
            .modifier(RoomMotionRoot())
            .modifier(RoomAccentRoot())
            .modifier(RoomHideRoot())
            .environment(\.roomActivityCenter, activity)
            .preferredColorScheme(Self.light ? .light : .dark)
            .task { await prepare() }
            .sheet(isPresented: $showReview) {
                RoomCleanupReviewSheet(model: caches)
            }
    }

    @ViewBuilder private var fixtureContent: some View {
        if screen == .monitor {
            RoomMenuBarView(insights: insights, cacheModel: caches, rooms: rooms, openRoom: {}, showSettings: {})
        } else if screen == .developer || screen == .aiTools {
            RoomShellView(navigation: navigation, rooms: rooms, insights: insights, selectRoom: { _ in },
                          sidebarValues: .init(freeBytes: 120_000_000_000, mappedFolders: 7, developerBytes: developer.totalBytes),
                          developerSection: developer.section, selectDeveloperSection: { developer.section = $0 }) {
                RoomScreenScaffold(title: "Developer", subtitle: nil, scrolls: false) {
                    RoomDeveloperView(model: developer)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { RoomActivityPill() }.sharedBackgroundVisibility(.hidden)
            }
        } else {
            RoomRootView(model: caches, insights: insights, memoryActions: memoryActions, rooms: rooms, navigation: navigation)
        }
    }

    private func prepare() async {
        guard !ready else { return }
        ready = true
        insights.refreshDiskCapacity()
        activity.setIdle(freeBytes: 120_000_000_000)
        let map = Self.storageMap()
        switch screen {
        case .overview:
            if let approvalID {
                await treeStore.setApprovals([approvalID: workspace])
                await treeStore.record(map, location: RoomTreeLocation(approvalID: approvalID, relativePath: ""), isHome: true)
                await insights.refreshHomeMap()
            }
            insights.diskMap.install(map, url: workspace)
        case .diskMap:
            if let approvalID {
                await treeStore.setApprovals([approvalID: workspace])
                await treeStore.record(map, location: RoomTreeLocation(approvalID: approvalID, relativePath: ""), isHome: false)
                await insights.restoreDiskMap()
            }
            if insights.diskMap.current == nil { insights.diskMap.install(map, url: workspace) }
            insights.diskMap.select("Mobile Studio")
        case .cachesReview:
            caches.scan()
            while caches.isScanning, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
            caches.selectRecommended()
            if caches.canReviewCleanup {
                showReview = true
                await caches.prepareStoreCleanupReview()
            }
        case .developer, .aiTools:
            developer.scan()
        case .caches:
            caches.scan()
            while caches.isScanning, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
            caches.selectRecommended()
        case .history, .settings:
            break
        case .memory, .monitor:
            if screen == .monitor {
                caches.cachesCheckStore.save(.init(at: Date().addingTimeInterval(-2_400), bytes: 156_000_000, partial: false))
            }
            insights.scanMemory()
        }
    }

    private static func sampleNPM(in home: URL) throws -> URL {
        let npm = home.appendingPathComponent(".npm", isDirectory: true)
        let objectDirectory = npm.appendingPathComponent("_cacache/content-v2/sha512", isDirectory: true)
        for index in 1...4 {
            let data = Data(repeating: UInt8(40 + index), count: (29 + 4 * index) * 1_048_576)
            let digest = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let parent = objectDirectory.appendingPathComponent(String(digest.prefix(2)), isDirectory: true)
                .appendingPathComponent(String(digest.dropFirst(2).prefix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let object = parent.appendingPathComponent(String(digest.dropFirst(4)))
            try data.write(to: object)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-45 * 86_400)], ofItemAtPath: object.path)
        }
        return npm
    }

    private static func pressureHistory() -> RoomPressureHistory {
        var history = RoomPressureHistory()
        let now = Date()
        for index in 0..<96 where !(22...28).contains(index) {
            let elevated = (53...57).contains(index) || (73...79).contains(index)
            let baseline = Int64((8.5 + 1.3 * sin(Double(index) / 7.0)) * 1e9)
            history.record(pressureRaw: elevated ? "elevated" : "normal",
                usedBytes: baseline + (elevated ? 2_100_000_000 : 0),
                swapBytes: elevated ? 384_000_000 : 0, at: now.addingTimeInterval(Double(index - 95) * 900))
        }
        return history
    }

    private static func memoryReport() -> MemoryReport {
        MemoryReport(id: UUID(), scannedAt: .now, totalBytes: 16_000_000_000, usedBytes: 10_800_000_000,
            availableBytes: 5_200_000_000, compressedBytes: 1_220_000_000, swapUsedBytes: 391_000_000,
            pressure: .normal, processes: [
                .init(id: 101, name: "Safari", residentBytes: 1_260_000_000),
                .init(id: 102, name: "Preview", residentBytes: 880_000_000),
                .init(id: 103, name: "Notes", residentBytes: 588_000_000),
                .init(id: 104, name: "Finder", residentBytes: 350_000_000)
            ], recommendations: [], issues: [], wiredBytes: 2_570_000_000)
    }

    private nonisolated static func developerReport(workspace: URL) -> DeveloperResourcesReport {
        let atlas = workspace.appendingPathComponent("Atlas").path
        let sketchbook = workspace.appendingPathComponent("Sketchbook").path
        let fieldNotes = workspace.appendingPathComponent("Field Notes").path
        let projects = [
            DeveloperProject(root: atlas, name: "Atlas",
                gradle: ("8.10", "bin"), agp: "8.6.1", kotlin: "2.0.21",
                multiplatform: true, appleNativeTargets: true, ndk: "27.1.12297006", hasXcodeProject: true),
            DeveloperProject(root: sketchbook, name: "Sketchbook", hasXcodeProject: true),
            DeveloperProject(root: fieldNotes, name: "Field Notes",
                gradle: ("8.10", "bin"), agp: "8.6.1", kotlin: "2.0.21")
        ]
        return DeveloperResourcesReport(id: UUID(), scannedAt: .now, androidDevices: [], gradleResources: [],
            projectWrappers: [], projects: projects, toolchains: [
                .init(path: atlas + "/Builds", kind: .derivedData, version: "Atlas-Release",
                    workspacePath: atlas, workspacePresent: true, bytes: 13_900_000_000, partial: false),
                .init(path: sketchbook + "/Builds", kind: .derivedData, version: "Sketchbook-Release",
                    workspacePath: sketchbook, workspacePresent: true, bytes: 8_300_000_000, partial: false),
                .init(path: workspace.path + "/Tools/27", kind: .ndk, version: "27.1.12297006",
                    bytes: 9_500_000_000, partial: false),
                .init(path: workspace.path + "/Tools/konan", kind: .kotlinNative, version: "2.0.21",
                    bytes: 4_200_000_000, partial: false),
                .init(path: workspace.path + "/Tools/8.10", kind: .gradle, version: "8.10-bin", gradleType: "bin",
                    bytes: 1_900_000_000, partial: false)
            ], issues: [], cancelled: false, isPartial: false)
    }

    private static func storageMap() -> RoomStoredTree {
        let tree = directory("Studio Projects", path: "", children: [
            directory("Mobile Studio", path: "Mobile Studio", children: [
                leaf("Atlas", path: "Mobile Studio/Atlas", size: 48, kind: .developer, directory: true),
                leaf("Sketchbook", path: "Mobile Studio/Sketchbook", size: 31, kind: .developer, directory: true),
                leaf("Field Notes", path: "Mobile Studio/Field Notes", size: 21, kind: .developer, directory: true),
                leaf("Resources", path: "Mobile Studio/Resources", size: 13, kind: .documents, directory: true)
            ]),
            directory("Image Library", path: "Image Library", children: [
                leaf("Raw photos", path: "Image Library/Raw photos", size: 49, kind: .media, directory: true),
                leaf("Film scans", path: "Image Library/Film scans", size: 26, kind: .media, directory: true),
                leaf("Exports", path: "Image Library/Exports", size: 12, kind: .media, directory: true)
            ]),
            directory("Archive", path: "Archive", children: [
                leaf("Project backups", path: "Archive/Project backups", size: 37, kind: .archives, directory: true),
                leaf("Assets.zip", path: "Archive/Assets.zip", size: 13, kind: .archives),
                leaf("References", path: "Archive/References", size: 6, kind: .documents, directory: true)
            ]),
            leaf("Films", path: "Films", size: 49, kind: .media, directory: true),
            leaf("Reference", path: "Reference", size: 40, kind: .documents, directory: true),
            leaf("Build caches", path: "Build caches", size: 24, kind: .developer, directory: true),
            leaf(".local", path: ".local", size: 11, kind: .hidden, directory: true)
        ])
        return RoomStoredTree(rootID: "sample-studio", displayPath: "~/Studio Projects", scannedAt: .now,
            cancelled: false, volumeUUID: "sample-volume", issueCount: 0, tree: tree)
    }

    private static func leaf(_ name: String, path: String, size: Int64, kind: StorageKind,
                             directory: Bool = false) -> RoomTreeNode {
        let bytes = size * 1_000_000_000
        return RoomTreeNode(name: name, relativePath: path, allocatedBytes: bytes, fileCount: directory ? 43 : 1,
            kindBytes: [kind.rawValue: bytes], isPartial: false, isDirectory: directory, children: [], other: nil)
    }

    private static func directory(_ name: String, path: String, children: [RoomTreeNode]) -> RoomTreeNode {
        let sorted = children.sorted { $0.allocatedBytes > $1.allocatedBytes }
        let kinds = sorted.reduce(into: [String: Int64]()) { total, item in
            total.merge(item.kindBytes, uniquingKeysWith: +)
        }
        return RoomTreeNode(name: name, relativePath: path, allocatedBytes: sorted.reduce(0) { $0 + $1.allocatedBytes },
            fileCount: sorted.reduce(0) { $0 + $1.fileCount }, kindBytes: kinds,
            isPartial: false, isDirectory: true, children: sorted, other: nil)
    }
}
