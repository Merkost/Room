import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Read-only Android and Gradle resource review")
struct DeveloperResourcesEngineTests {
    @Test("AVD metadata and sparse allocations are useful without inventing a last-launch date")
    func androidEvidence() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let avds = try f.directory("android/avd")
        let device = try f.directory("android/avd/Pixel_35.avd")
        _ = try f.write("android/avd/Pixel_35.avd/config.ini", """
            AvdId=Pixel_35
            avd.ini.displayname=Pixel 8 · API 35
            abi.type=arm64-v8a
            hw.device.manufacturer=Google
            hw.device.name=pixel_8
            image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/
            """)
        _ = try f.write("android/avd/Pixel_35.avd/emu-launch-params.txt", "not parsed")
        _ = try f.write("android/avd/Pixel_35.avd/snapshots/default_boot/snapshot.pb", "private snapshot content is never parsed")
        _ = try f.write("android/avd/Pixel_35.avd/hardware-qemu.ini.lock", "stale lock is not a running PID")
        let image = device.appendingPathComponent("userdata-qemu.img")
        #expect(FileManager.default.createFile(atPath: image.path, contents: nil))
        let file = try FileHandle(forWritingTo: image)
        try file.seek(toOffset: 64 * 1_024 * 1_024)
        try file.write(contentsOf: Data(repeating: 1, count: 4_096)); try file.close()
        let report = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds]))
        let item = try #require(report.androidDevices.first)
        #expect(item.name == "Pixel_35" && item.displayName == "Pixel 8 · API 35")
        #expect(item.apiLevel == "35" && item.abi == "arm64-v8a")
        #expect(item.device == "Google pixel_8")
        #expect(item.logicalBytes > 64 * 1_024 * 1_024 && item.allocatedBytes < 64 * 1_024 * 1_024)
        #expect(item.lastUsedAt == nil)
        #expect(item.lastUseNote.contains("not recorded reliably"))
        #expect(item.evidence.contains { $0.kind == .snapshotChanged })
        #expect(item.evidence.contains { $0.kind == .launchRecordChanged })
        #expect(item.evidence.contains { $0.kind == .lockPresent })
        #expect(item.activity.state == .possibleUse)
        #expect(item.activity.processIDs.isEmpty)
    }

    @Test("Installed distributions and version caches map only to wrappers in selected nested projects")
    func gradleProjectMappingAndSecrets() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let gradle = try f.directory("gradle-home")
        _ = try f.write("gradle-home/wrapper/dists/gradle-8.9-bin/hash/gradle-8.9/lib/runtime.jar", "runtime")
        _ = try f.write("gradle-home/wrapper/dists/gradle-8.9-all/hash/gradle-8.9/lib/runtime.jar", "runtime")
        _ = try f.write("gradle-home/wrapper/dists/gradle-9.1-rc-1-all/hash/gradle-9.1/lib/runtime.jar", "runtime")
        _ = try f.write("gradle-home/caches/8.9/transforms/archive", "version cache")
        _ = try f.write("gradle-home/caches/modules-2/files/artifact", "shared cache")
        let projects = try f.directory("projects")
        _ = try f.write("projects/First/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://username:private-password@example.com/gradle-8.9-bin.zip?token=private-token\n")
        _ = try f.write("projects/Nested/Second/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.1-rc-1-all.zip\n")
        _ = try f.write("projects/node_modules/External/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https://example.com/gradle-7.0-bin.zip\n")
        let secret = f.url("projects/First/local.properties")
        #expect(mkfifo(secret.path, 0o600) == 0)
        _ = try f.write("projects/First/gradle.properties", "credentials=must-not-be-read\n")
        _ = try f.write("projects/.claude/projects/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https://example.com/gradle-6.0-bin.zip\n")
        let report = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [gradle, projects],
            gradleHomes: [gradle], projectRoots: [projects, projects.appendingPathComponent("First")]))
        #expect(report.projectWrappers.count == 2)
        let installed = try #require(report.gradleResources.first { $0.kind == .distribution && $0.version == "8.9" && $0.distributionType == "bin" })
        #expect(installed.distributionType == "bin")
        #expect(installed.projectUses.count == 1)
        #expect(installed.projectUses.first?.projectURL.lastPathComponent == "First")
        let otherType = try #require(report.gradleResources.first { $0.kind == .distribution && $0.version == "8.9" && $0.distributionType == "all" })
        #expect(otherType.projectUses.isEmpty)
        #expect(otherType.usageNote.contains("No discovered wrapper"))
        #expect(report.gradleResources.first { $0.kind == .versionCache && $0.version == "8.9" }?.projectUses.count == 1)
        #expect(report.gradleResources.first { $0.kind == .sharedCache }?.version == nil)
        #expect(report.gradleResources.first { $0.version == "9.1-rc-1" }?.projectUses.first?.projectURL.lastPathComponent == "Second")
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains("private-password") && !json.contains("private-token") && !json.contains("must-not-be-read"))
    }

    @Test("Unapproved roots and symbolic links cannot expose outside device configuration or project wrappers")
    func permissionAndSymlinkBoundaries() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let approved = try f.directory("approved")
        let outside = try f.directory("outside")
        _ = try f.write("outside/Secret.avd/config.ini", "target=android-99\n")
        _ = try f.write("outside/Project/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https://example.com/gradle-99.0-bin.zip\n")
        try FileManager.default.createSymbolicLink(at: f.url("approved/Linked.avd"), withDestinationURL: f.url("outside/Secret.avd"))
        try FileManager.default.createSymbolicLink(at: f.url("approved/Project"), withDestinationURL: f.url("outside/Project"))
        let own = try f.directory("approved/Own.avd")
        try FileManager.default.createSymbolicLink(at: own.appendingPathComponent("config.ini"), withDestinationURL: f.url("outside/Secret.avd/config.ini"))
        let report = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [approved],
            avdRoots: [approved, outside], projectRoots: [approved, outside]))
        #expect(report.androidDevices.count == 1)
        #expect(report.androidDevices.first?.name == "Own")
        #expect(report.androidDevices.first?.apiLevel == nil)
        #expect(report.androidDevices.first?.isPartial == true)
        #expect(report.projectWrappers.isEmpty)
        #expect(report.isPartial)
        #expect(report.issues.contains { $0.message.contains("explicit folder approval") })
        #expect(report.androidDevices.allSatisfy { $0.url.path.hasPrefix(approved.path + "/") })
    }

    @Test("Truncated and malformed evidence stays unknown rather than parsing a plausible prefix")
    func boundedMetadata() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let avds = try f.directory("avds")
        _ = try f.write("avds/TooLarge.avd/config.ini", "target=android-35\n" + String(repeating: "x", count: 2_048))
        let projects = try f.directory("projects")
        _ = try f.write("projects/Huge/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https://example.com/gradle-8.9-bin.zip\n" + String(repeating: "x", count: 2_048))
        _ = try f.write("projects/Duplicate/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https://example.com/gradle-8.9-bin.zip\ndistributionUrl=https://example.com/gradle-9.0-bin.zip\n")
        let request = DeveloperResourcesRequest(approvedFolders: [avds, projects], avdRoots: [avds], projectRoots: [projects],
            limits: DeveloperResourcesLimits(maximumFileBytes: 128))
        let report = await DeveloperResourcesEngine().scan(request: request)
        #expect(report.androidDevices.first?.apiLevel == nil)
        #expect(report.androidDevices.first?.isPartial == true)
        #expect(report.projectWrappers.count == 2)
        #expect(report.projectWrappers.allSatisfy { $0.version == nil && $0.isPartial })
        #expect(report.isPartial)
    }

    @Test("Process path evidence uses boundaries; absent samples stay unknown and locks stay possible")
    func activityEvidence() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let avds = try f.directory("avds")
        let device = try f.directory("avds/Pixel.avd")
        _ = try f.write("avds/Pixel.avd/config.ini", "target=android-35\n")
        let engine = DeveloperResourcesEngine()
        let exact = DeveloperActivitySnapshot(processes: [DeveloperResourceProcess(processID: 101, name: "qemu-system-aarch64", paths: [device.appendingPathComponent("userdata-qemu.img")])])
        let first = await engine.scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds], activity: exact))
        #expect(first.androidDevices.first?.activity.state == .observedUse)
        #expect(first.androidDevices.first?.activity.processIDs == [101])
        let boundary = DeveloperActivitySnapshot(processes: [DeveloperResourceProcess(processID: 102, name: "other", paths: [URL(fileURLWithPath: device.path + "-other/userdata.img")])])
        let second = await engine.scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds], activity: boundary))
        #expect(second.androidDevices.first?.activity.state == .unknown)
        #expect(second.androidDevices.first?.activity.processIDs.isEmpty == true)
        let named = DeveloperActivitySnapshot(processes: [DeveloperResourceProcess(processID: 103, name: "emulator", avdNames: ["Pixel"])])
        let third = await engine.scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds], activity: named))
        #expect(third.androidDevices.first?.activity.state == .possibleUse)
        #expect(third.androidDevices.first?.lastUsedAt == nil)
    }

    @Test("Cancellation, node caps and progress are bounded and leave all fixture files intact")
    func cancellationAndLimits() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let avds = try f.directory("avds")
        _ = try f.write("avds/Pixel.avd/config.ini", "target=android-35\n")
        for index in 0..<30 { _ = try f.write("avds/Pixel.avd/files/\(index)", "owned") }
        let progress = Mutex<[String]>([])
        let report = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds],
            limits: DeveloperResourcesLimits(maximumNodes: 12))) { update in progress.withLock { $0.append(update.phase) } }
        #expect(report.isPartial)
        #expect(!progress.withLock { $0 }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: f.url("avds/Pixel.avd/files/0").path))
        let task = Task { await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds])) }
        task.cancel()
        #expect(await task.value.cancelled)
        let noTime = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [avds], avdRoots: [avds],
            limits: DeveloperResourcesLimits(timeLimit: 0)))
        #expect(noTime.isPartial)
    }

    @Test func fixtureSubyKMPAndStandupbotJVM() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let projects = try f.directory("projects")
        let sdk = try f.directory("sdk")
        let konan = try f.directory("konan")
        let gradle = try f.directory("gradle")
        _ = try f.directory("gradle/caches")
        _ = try f.write("projects/Suby/settings.gradle.kts", "rootProject.name = \"Suby\"")
        _ = try f.write("projects/Suby/gradle/wrapper/gradle-wrapper.properties",
                        "distributionUrl=https://example.invalid/gradle-8.9-bin.zip")
        _ = try f.write("projects/Suby/gradle/libs.versions.toml", """
            [versions]
            k = "2.1.0"
            n = "27.1.12297006"
            [plugins]
            kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "k" }
            """)
        _ = try f.write("projects/Suby/shared/build.gradle.kts", """
            plugins { alias(libs.plugins.kotlin.multiplatform) }
            kotlin { iosArm64() }
            android { ndkVersion = libs.versions.n.get() }
            """)
        _ = try f.write("projects/Standup/build.gradle.kts", #"plugins { kotlin("jvm") version "2.0.21" }"#)
        _ = try f.write("sdk/ndk/27.1.12297006/tool", "NDK")
        _ = try f.write("konan/kotlin-native-prebuilt-macos-aarch64-2.1.0/tool", "native")
        _ = try f.write("konan/kotlin-native-prebuilt-macos-aarch64-2.0.21/tool", "native")
        _ = try f.write("gradle/wrapper/dists/gradle-8.9-bin/hash/archive", "Gradle")
        _ = try f.write("gradle/wrapper/dists/gradle-7.6.4-bin/hash/archive", "old Gradle")

        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [projects, sdk, konan, gradle], gradleHomes: [gradle],
            projectRoots: [projects], sdkRoots: [sdk], konanRoots: [konan]))
        #expect(report.projects.count == 2)
        let suby = try #require(report.projects.first { $0.name == "Suby" })
        let standup = try #require(report.projects.first { $0.name == "Standup" })
        #expect(suby.pinsKonan && suby.ndk == "27.1.12297006" && suby.gradle?.version == "8.9")
        #expect(!standup.pinsKonan && standup.kotlin == "2.0.21")
        let summary = RoomDeveloperRooms.summarize(projects: report.projects, artifacts: report.toolchains,
                                                    scanPartial: report.isPartial)
        let row = try #require(summary.rows.first { $0.project.name == "Suby" })
        #expect(row.segments.map(\.kind) == [.ndk, .kotlinNative, .gradle])
        #expect(summary.orphans.contains { $0.artifact.version == "7.6.4-bin" })
    }

    @Test func localPropertiesNeverRead() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let project = try f.directory("projects/Project")
        _ = try f.write("projects/Project/build.gradle.kts", "kotlin { iosArm64() }")
        for name in ["local.properties", "gradle.properties", ".env", ".env.production"] {
            #expect(mkfifo(project.appendingPathComponent(name).path, 0o600) == 0)
        }
        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [project], projectRoots: [project]))
        #expect(report.projects.count == 1)
        #expect(report.issues.isEmpty)
    }

    @Test func unapprovedRootNotInspected() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let approved = try f.directory("approved")
        let outside = try f.directory("other")
        _ = try f.write("other/ndk/99.0/tool", "not approved")
        _ = try f.write("other/build.gradle.kts", "kotlin { iosArm64() }")
        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [approved], projectRoots: [outside], sdkRoots: [outside]))
        #expect(report.projects.isEmpty && report.toolchains.isEmpty)
        #expect(report.issues.count == 2)
        #expect(report.issues.allSatisfy { $0.url.path == outside.path })
    }

    @Test func derivedDataOutsideApprovalNotStatted() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let projects = try f.directory("projects")
        let data = try f.directory("derived-data")
        for (folder, workspace) in [("Inside", "projects/Gone.xcodeproj"), ("Outside", "other/Gone.xcodeproj")] {
            let container = try f.directory("derived-data/" + folder)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": f.url(workspace).path],
                                                           format: .binary, options: 0)
            try plist.write(to: container.appendingPathComponent("info.plist"))
        }
        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [projects, data], derivedDataRoots: [data]))
        let summary = RoomDeveloperRooms.summarize(projects: report.projects, artifacts: report.toolchains,
                                                    scanPartial: report.isPartial)
        let reasons = Dictionary(uniqueKeysWithValues: summary.orphans.map { ($0.artifact.version, $0.reason) })
        #expect(reasons["Inside"] == .projectFolderGone)
        #expect(reasons["Outside"] == .pinnedByNone)
        #expect(report.toolchains.first { $0.version == "Outside" }?.workspacePresent == nil)
    }

    @Test func oversizeFileIsIssue() async throws {
        let f = try DeveloperFixture()
        defer { f.remove() }
        let projects = try f.directory("projects")
        let large = try f.write("projects/Project/build.gradle.kts",
                                "ndkVersion = \"27.1.12297006\"\n" + String(repeating: "x", count: 262_145))
        let report = await DeveloperResourcesEngine().scan(request: .init(approvedFolders: [projects],
                                                                          projectRoots: [projects]))
        #expect(report.isPartial)
        #expect(report.issues.contains { $0.url == large })
    }

    @Test("Version parsing handles release candidates and discards URL credentials and nonstandard filenames")
    func versions() {
        #expect(DRVersions.distribution("gradle-8.9-bin")?.version == "8.9")
        #expect(DRVersions.distribution("gradle-9.1-rc-1-all.zip")?.version == "9.1-rc-1")
        #expect(DRVersions.distribution("gradle-9.1-rc-1-all.zip")?.type == "all")
        #expect(DRVersions.distributionURL("https\\://user:password@example.com/gradle-9.2.0-bin.zip?token=secret")?.version == "9.2.0")
        for text in ["modules-2", "gradle-trash-bin", "gradle-8.9-bin.zip.part", "gradle-8..9-bin", "gradle-8.9-bin-other"] {
            #expect(DRVersions.distribution(text) == nil)
        }
        #expect(DRVersions.distributionURL("https://example.com/gradle-8.9-bin.zip\\") == nil)
    }
}

private struct DeveloperFixture: Sendable {
    let home: URL
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomDeveloper-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    }
    func url(_ path: String) -> URL { home.appendingPathComponent(path) }
    func directory(_ path: String) throws -> URL {
        let value = url(path)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    func write(_ path: String, _ text: String) throws -> URL {
        let value = url(path)
        try FileManager.default.createDirectory(at: value.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: value)
        return value
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
