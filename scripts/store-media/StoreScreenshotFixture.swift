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
    #if ROOM_APP_STORE
    private let memoryActions = MemoryActionsModel()
    #else
    private let memoryActions = StoreScreenshotFixture.sampleApps()
    #endif
    #if !ROOM_APP_STORE
    private let agentWork = AgentWorkModel()
    #endif
    /// nav-v3 media: rich sample data on every screen (Disk Map home, six caches, Developer rooms, receipts).
    /// `--sparse` keeps the old Store media set.
    static var rich: Bool { !CommandLine.arguments.contains("--sparse") }
    static func option(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
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
            capacityReader: { RoomVolumeCapacity(capacityBytes: Self.rich ? 494_000_000_000 : 500_000_000_000,
                freeBytes: Self.rich ? 64_000_000_000 : 120_000_000_000,
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
        if Self.rich {
            developer.debugInstall(review: Self.richReview(workspace: workspace), devices: Self.richDevices(home: sampleHome),
                                   storage: Self.richStorage(home: sampleHome), aiTools: Self.richAI(home: sampleHome))
            developer.debugRemember(workspace, role: .project)
            RoomDeveloperModel.debugInjected = developer
            caches.debugActivity = Self.richReceipts()
            insights.debugSeedMemory(Self.memoryCurve())
            #if !ROOM_APP_STORE
            agentWork.debugInstall(Self.richWorktrees(home: sampleHome))
            #endif
        }
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
        }
    }

    var windowSize: CGSize {
        if screen == .monitor { return CGSize(width: 340, height: 440) }
        if let raw = Self.option("--size"), case let parts = raw.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
            return CGSize(width: parts[0], height: parts[1])
        }
        return CGSize(width: 1_180, height: 720)
    }

    var body: some View {
        fixtureContent
            .modifier(RoomMotionRoot())
            .modifier(RoomAccentRoot())
            .modifier(RoomHideRoot())
            .environment(\.roomActivityCenter, activity)
            .preferredColorScheme(Self.light ? .light : .dark)
            .task { await prepare() }
            .roomSheetOverlay(isPresented: showReview, animated: CommandLine.arguments.contains("--tour")) {
                RoomCleanupReviewSheet(model: caches, close: { showReview = false })
            }
    }

    @ViewBuilder private var fixtureContent: some View {
        if screen == .monitor {
            RoomMenuBarView(insights: insights, cacheModel: caches, rooms: rooms, openRoom: {}, showSettings: {})
        } else if (screen == .developer || screen == .aiTools) && !Self.rich {
            RoomShellView(navigation: navigation, insights: insights,
                          dockValues: .init(freeBytes: 120_000_000_000, mappedBytes: 7_000_000_000,
                                            developerBytes: developer.totalBytes)) {
                RoomScreenScaffold(title: "Developer", subtitle: nil, scrolls: false) {
                    #if ROOM_APP_STORE
                    RoomDeveloperView(model: developer)
                    #else
                    RoomDeveloperView(model: developer, agentWork: agentWork)
                    #endif
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { RoomActivityPill() }.sharedBackgroundVisibility(.hidden)
            }
        } else {
            #if ROOM_APP_STORE
            RoomRootView(model: caches, insights: insights, memoryActions: memoryActions, rooms: rooms, navigation: navigation)
            #else
            RoomRootView(model: caches, insights: insights, memoryActions: memoryActions, rooms: rooms, navigation: navigation,
                         agentWork: agentWork)
            #endif
        }
    }

    private func prepare() async {
        guard !ready else { return }
        ready = true
        insights.refreshDiskCapacity()
        if Self.rich {
            await prepareRich()
            return
        }
        activity.setIdle(freeBytes: Self.rich ? 64_000_000_000 : 120_000_000_000)
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
                #if ROOM_APP_STORE
                await caches.prepareStoreCleanupReview()
                #endif
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

    private func prepareRich() async {
        // Hide persists in the fixture's defaults: set it to exactly what this scene asks for.
        if CommandLine.arguments.contains("--hide") != RoomHideControl.shared.state.isOn { RoomHideControl.shared.toggle() }
        activity.setIdle(freeBytes: 64_000_000_000)
        let map = Self.homeMap()
        if let approvalID {
            await treeStore.setApprovals([approvalID: workspace])
            await treeStore.record(map, location: RoomTreeLocation(approvalID: approvalID, relativePath: ""), isHome: true)
            await insights.refreshHomeMap()
        }
        insights.diskMap.install(map, url: workspace, isHome: true)
        caches.debugInstall(Self.richCaches(home: workspace))
        insights.scanMemory()
        await caches.refreshHistory()
        if CommandLine.arguments.contains("--tour") { await tour() }
        switch screen {
        case .diskMap:
            if let inside = Self.option("--inside") { _ = insights.diskMap.go(to: inside) }
        case .cachesReview:
            showReview = true
        default: break
        }
    }

    /// `--tour`: drives the window through the pointer motions on a fixed clock so a recording can be checked frame by
    /// frame (pill slide and arrival, Disk Map zoom in and out, the review card in and out).
    private func tour() async {
        let motion = RoomMotionPolicy(gentleMotion: true, reduceMotion: false)
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func go(_ place: RoomDestination) {
            withAnimation(RoomDock.selectionAnimation(origin: .pointer, motion: motion)) {
                navigation.select(.screen(place), origin: .pointer)
            }
        }
        Task { @MainActor in
            await wait(2); go(.clean)
            await wait(2); go(.disk)
            await wait(2); withAnimation(RoomTokens.Motion.zoom) { _ = insights.diskMap.go(to: "Developer") }
            await wait(2); withAnimation(RoomTokens.Motion.zoom) { _ = insights.diskMap.go(to: "") }
            await wait(2); go(.clean)
            await wait(1.5); withAnimation(motion.animation(RoomTokens.Motion.glass, fallback: RoomTokens.Motion.fade)) { showReview = true }
            await wait(2); withAnimation(motion.animation(RoomTokens.Motion.glass, fallback: RoomTokens.Motion.fade)) { showReview = false }
        }
    }

    private static func gb(_ value: Double) -> Int64 { Int64(value * 1e9) }

    /// Mockup `CA`: six places that can go, 22 GB, and 8 GB kept safe in three places.
    private static func richCaches(home: URL) -> ScanReport {
        let places: [(String, String, String, Double, String)] = [
            ("demo-xcode", "Xcode DerivedData", "builds again on next run", 9, "Library/Developer/Xcode/DerivedData"),
            ("demo-npm", "npm cache", "downloads again", 4, ".npm/_cacache"),
            ("demo-gradle", "Gradle caches", "downloads again", 3, ".gradle/caches"),
            ("demo-homebrew", "Homebrew downloads", "installers", 2, "Library/Caches/Homebrew"),
            ("demo-browsers", "Browser caches", "4 browsers", 2, "Library/Caches/Browsers"),
            ("demo-simulator", "Simulator caches", "rebuilds", 2, "Library/Developer/CoreSimulator/Caches")]
        let old = Date().addingTimeInterval(-40 * 86_400)
        let groups = places.map { id, title, subtitle, size, path in
            let root = home.appendingPathComponent(path, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return CacheGroup(id: id, title: title, subtitle: subtitle, symbol: "shippingbox", category: "developer",
                rootURL: root, consequence: "Rebuilds on next use.", entries: [
                    CacheEntry(id: UUID(), url: root.appendingPathComponent("a"), name: title, byteCount: gb(size * 0.7),
                               modifiedAt: old, eligibility: .eligible, fileCount: 1200),
                    CacheEntry(id: UUID(), url: root.appendingPathComponent("b"), name: title, byteCount: gb(size * 0.3),
                               modifiedAt: old, eligibility: .eligible, fileCount: 300)], issues: [])
        }
        let kept: [(String, Double)] = [("Photos caches", 4), ("Mail downloads", 3), ("iCloud Drive cache", 1)]
        return ScanReport(id: UUID(), scannedAt: Date(), groups: groups,
            protectedData: kept.map { ProtectedData(id: $0.0, title: $0.0, url: home.appendingPathComponent($0.0),
                byteCount: gb($0.1), reason: "Room never moves this", isPartial: false) },
            issues: [], volume: VolumeInfo(totalBytes: 494_000_000_000, availableBytes: 64_000_000_000), cancelled: false)
    }

    /// Mockup home: seven rooms and their insides.
    private static func homeMap() -> RoomStoredTree {
        func room(_ name: String, _ kind: StorageKind, _ parts: [(String, Double)], extra: [String: Double] = [:]) -> RoomTreeNode {
            let kids = parts.map { leaf($0.0, path: name + "/" + $0.0, size: Int64($0.1), kind: kind, directory: true) }
            var node = directory(name, path: name, children: kids)
            if !extra.isEmpty {
                node.kindBytes = extra.mapValues { gb($0) }
            }
            return node
        }
        let tree = directory("Home", path: "", children: [
            room("Developer", .developer, [("suby", 38), ("room", 21), ("luchik", 17), ("Other projects", 44)]),
            room("Library", .apps, [("Application Support", 41), ("Caches", 22), ("Containers", 19), ("Preferences", 14)]),
            room("Movies", .media, [("Final Cut", 52), ("Screen recordings", 24), ("Clips", 12)]),
            room("Documents", .documents, [("Work", 40), ("Scans", 20), ("Letters", 14)]),
            room("Pictures", .documents, [("Photos Library", 26), ("Exports", 4)]),
            room("Downloads", .archives, [("Installers", 9), ("Archives", 5)]),
            room("Desktop", .documents, [("Screenshots", 5)]),
            room("Music", .media, [("Logic", 3)])])
        return RoomStoredTree(rootID: "sample-home", displayPath: "~", scannedAt: Date().addingTimeInterval(-3 * 86_400),
            cancelled: false, volumeUUID: "sample-volume", issueCount: 0, tree: tree)
    }

    /// Thirteen minutes of memory between 9 and 12 GB, so the curve has a shape.
    private static func memoryCurve() -> [Int64] {
        let shape: [Double] = [9, 9, 10, 10, 9, 9, 10, 11, 11, 10, 10, 9, 10, 10, 11, 12, 12, 11, 10, 10, 9, 9, 10, 10, 11,
                               10, 10, 9, 10, 9, 11, 10, 10, 12, 11, 10, 9, 10, 11, 10]
        return shape.map { gb($0 + 0.2) }
    }

    /// Mockup History: Monday's Developer builds and two Caches receipts this month.
    private static func richReceipts() -> [RoomActivity] {
        let calendar = Calendar.current
        let now = Date()
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        func month(_ day: Int) -> Date {
            var parts = calendar.dateComponents([.year, .month], from: now)
            parts.day = day
            return calendar.date(from: parts) ?? now
        }
        let rows: [(Date, String, Double, String)] = [
            (monday.addingTimeInterval(10 * 3600), "Developer builds", 14, "caches"),
            (month(12), "Caches", 8, "caches"),
            (month(3), "Caches", 6, "caches"),
            (calendar.date(byAdding: .month, value: -1, to: month(21)) ?? now, "Movies", 18, "diskMap"),
            (calendar.date(byAdding: .month, value: -1, to: month(9)) ?? now, "Caches", 11, "caches")]
        return rows.map { date, title, size, source in
            RoomActivity(id: UUID(), date: date, bytes: gb(size), itemCount: 4, restoredCount: 0, errorCount: 0,
                canRestore: true, title: title, details: [RoomActivityItem(id: UUID(), name: title, path: "/", message: "",
                    isRestored: false, canRestore: true, bytes: gb(size), source: source)])
        }
    }

    private static func richReview(workspace: URL) -> DeveloperResourcesReport {
        let names: [(String, Double, Bool)] = [("suby", 31, true), ("room", 16, false), ("luchik", 12, false),
                                                ("merkost-site", 6, false), ("standup-bot", 5, true)]
        let projects = names.map { name, _, android in
            DeveloperProject(root: workspace.appendingPathComponent(name).path, name: name,
                gradle: android ? ("8.10", "bin") : nil, agp: android ? "8.6.1" : nil, kotlin: android ? "2.0.21" : nil,
                multiplatform: android, appleNativeTargets: true, ndk: android ? "27.1.12297006" : nil, hasXcodeProject: true)
        }
        var toolchains = names.map { name, size, _ in
            DeveloperToolchainResource(path: workspace.appendingPathComponent(name).path + "/Builds", kind: .derivedData,
                version: name + "-Release", workspacePath: workspace.appendingPathComponent(name).path,
                workspacePresent: true, bytes: gb(size), partial: false)
        }
        toolchains += [
            .init(path: workspace.path + "/Tools/ndk/27", kind: .ndk, version: "27.1.12297006", bytes: gb(9.5), partial: false),
            .init(path: workspace.path + "/Tools/ndk/26", kind: .ndk, version: "26.3.11579264", bytes: gb(8.2), partial: false),
            .init(path: workspace.path + "/Tools/konan/2.0", kind: .kotlinNative, version: "2.0.21", bytes: gb(4.2), partial: false),
            .init(path: workspace.path + "/Tools/konan/1.9", kind: .kotlinNative, version: "1.9.24", bytes: gb(3.8), partial: false),
            .init(path: workspace.path + "/Tools/gradle/8.10", kind: .gradle, version: "8.10-bin", gradleType: "bin",
                  bytes: gb(1.9), partial: false),
            .init(path: workspace.path + "/Tools/gradle/8.7", kind: .gradle, version: "8.7-bin", gradleType: "bin",
                  bytes: gb(1.6), partial: false)]
        return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], projects: projects, toolchains: toolchains, issues: [], cancelled: false, isPartial: false)
    }

    private static func richDevices(home: URL) -> DeveloperResourcesReport {
        let quiet = DeveloperResourceActivity(state: .notObserved, processIDs: [], indicators: [], sampledAt: Date())
        let android = [("Pixel 9", "36", 5.2), ("Pixel Tablet", "35", 3.9)].map { name, api, size in
            AndroidVirtualDeviceResource(url: home.appendingPathComponent(".android/avd/\(name).avd"), name: name,
                displayName: name, apiLevel: api, abi: "arm64-v8a", device: name, allocatedBytes: gb(size),
                logicalBytes: gb(size), isPartial: false, lastUsedAt: nil, lastUseNote: "", evidence: [], activity: quiet)
        }
        let simulators = [("iPhone 17 Pro", "iOS 26.1", 9.1), ("iPad Air", "iPadOS 26.1", 6.3), ("Apple Watch Ultra 3", "watchOS 26.1", 2.4)]
            .map { name, runtime, size in
                SimulatorDeviceResource(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(name)"),
                    displayName: name, runtimeIdentifier: runtime, deviceTypeIdentifier: name, allocatedBytes: gb(size), isPartial: false)
            }
        return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: android, gradleResources: [],
            projectWrappers: [], simulatorDevices: simulators, issues: [], cancelled: false, isPartial: false)
    }

    private static func richStorage(home: URL) -> DeveloperResourcesReport {
        let base = home.appendingPathComponent("Library/Developer")
        let resources: [DeveloperStorageResource] = [
            .init(kind: .simulatorRuntimeImage, url: base.appendingPathComponent("Runtimes/iOS 26.1"), allocatedBytes: gb(31),
                  isPartial: false, runtime: .init(name: "iOS 26.1", build: "23B80")),
            .init(kind: .androidSystemImages, url: home.appendingPathComponent("Library/Android/sdk/system-images"),
                  allocatedBytes: gb(22), isPartial: false),
            .init(kind: .simulatorRuntimeImage, url: base.appendingPathComponent("Runtimes/iOS 18.6"), allocatedBytes: gb(14),
                  isPartial: false, runtime: .init(name: "iOS 18.6", build: "22G84")),
            .init(kind: .gradleJDKs, url: home.appendingPathComponent(".gradle/jdks"), allocatedBytes: gb(3.1), isPartial: false),
            .init(kind: .gradleDaemon, url: home.appendingPathComponent(".gradle/daemon"), allocatedBytes: gb(1.2), isPartial: false)]
        return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], storageResources: resources, issues: [], cancelled: false, isPartial: false)
    }

    private static func richAI(home: URL) -> DeveloperResourcesReport {
        let rows: [(DeveloperAITool, String, String, Double, DeveloperAIStorageCategory)] = [
            (.ollama, "Local models", ".ollama/models", 18, .runtime),
            (.claudeCode, "Sessions", ".claude/projects", 4.1, .history),
            (.claudeCode, "Caches", ".claude/cache", 1.9, .cache),
            (.codex, "Worktrees", ".codex/worktrees", 2.2, .worktrees),
            (.codex, "Sessions", ".codex/sessions", 0.9, .history),
            (.cursor, "Caches", "Library/Application Support/Cursor/Cache", 1.4, .cache)]
        let resources = rows.map { tool, title, path, size, category in
            DeveloperAIStorageResource(tool: tool, title: title, url: home.appendingPathComponent(path),
                                       allocatedBytes: gb(size), isPartial: false, category: category)
        }
        return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], aiStorageResources: resources, issues: [], cancelled: false, isPartial: false)
    }

    #if !ROOM_APP_STORE
    private static func richWorktrees(home: URL) -> AgentWorkReport {
        let rows: [(String, String, AgentWorkOwner, Double, Int)] = [
            ("suby-home-2", "release/2.0.0", .claude, 4.2, 3), ("room-rest-app", "release/room-redesign-merge", .codex, 1.3, 0),
            ("room-uiux", "merged", .codex, 0.8, 0)]
        let items = rows.map { name, branch, owner, size, changed in
            AgentWorkItem(id: name, url: home.appendingPathComponent(".codex/worktrees/" + name), title: name, owner: owner,
                repositoryURL: nil, gitAdminURL: nil, gitCommonURL: nil, branch: branch, head: nil,
                lastActivityAt: Date().addingTimeInterval(-86_400 * 3), allocatedBytes: gb(size), isPartial: false,
                changedCount: changed, untrackedCount: 0, ignoredCount: 0, processIDs: [], isLinkedWorktree: true,
                isLocked: false, isPrunable: false, heldReasons: [], pushVerification: .notChecked)
        }
        return AgentWorkReport(id: UUID(), scannedAt: Date(), items: items, processAssociations: [], issues: [],
                               cancelled: false, isPartial: false)
    }
    #endif

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

    #if !ROOM_APP_STORE
    /// Sample apps, so a render never lists what is really running on this Mac.
    private static func sampleApps() -> MemoryActionsModel {
        let apps = [(101, "Xcode"), (102, "Safari"), (103, "Simulator")].map { pid, name in
            MemoryRunningApplication(pid: Int32(pid), name: name, bundleIdentifier: "sample.\(name)",
                bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"), launchDate: .distantPast,
                bundleIdentity: MemoryBundleIdentity(device: 1, inode: UInt64(pid), modifiedSeconds: 0,
                    modifiedNanoseconds: 0, changedSeconds: 0, changedNanoseconds: 0),
                isRegular: true, isTerminated: false, icon: nil)
        }
        return MemoryActionsModel(applicationProvider: { apps }, quitRequester: { _ in .refused })
    }
    #endif

    private static func memoryReport() -> MemoryReport {
        MemoryReport(id: UUID(), scannedAt: .now, totalBytes: 17_179_869_184, usedBytes: 9_400_000_000,
            availableBytes: 5_200_000_000, compressedBytes: 1_220_000_000, swapUsedBytes: 391_000_000,
            pressure: .normal, processes: [
                .init(id: 101, name: "Xcode", residentBytes: 3_100_000_000),
                .init(id: 102, name: "Safari", residentBytes: 2_200_000_000),
                .init(id: 103, name: "Simulator", residentBytes: 1_300_000_000),
                .init(id: 201, name: "java", residentBytes: 1_100_000_000),
                .init(id: 202, name: "WindowServer", residentBytes: 600_000_000),
                .init(id: 104, name: "Finder", residentBytes: 350_000_000),
                .init(id: 203, name: "node", residentBytes: 300_000_000)
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
