import Darwin
import Foundation
import Testing
@testable import RoomCore

@Suite("Developer project build folders")
struct DeveloperProjectScannerTests {
    /// Fixture folders hold a few bytes, so the 1 MB floor is lowered.
    static let everything: DeveloperProjectScanner.Limits = { var limits = DeveloperProjectScanner.Limits(); limits.smallestFolder = 0; return limits }()

    @Test func findsProjectsOfEveryKindAndWhatTheirToolsRebuild() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/node_modules/left-pad/index.js")
        try home.file("code/web/.next/BUILD_ID")
        try home.file("code/engine/Cargo.toml")
        try home.file("code/engine/target/CACHEDIR.TAG")
        try home.file("code/engine/target/debug/engine")
        try home.file("code/kit/Package.swift")
        try home.file("code/kit/.build/workspace-state.json")
        try home.file("code/ml/pyproject.toml")
        try home.file("code/ml/.venv/pyvenv.cfg")
        try home.file("code/ml/.mypy_cache/CACHEDIR.TAG")
        try home.file("code/app/pubspec.yaml")
        try home.file("code/app/.dart_tool/package_config.json")
        try home.file("code/app/build/.last_build_id")
        try home.file("code/android/settings.gradle.kts")
        try home.file("code/android/.gradle/file-system.probe")
        try home.file("code/android/app/build.gradle.kts")
        try home.file("code/android/app/build/tmp/x")
        try home.file("code/service/Service.csproj")
        try home.file("code/service/obj/project.assets.json")
        try home.file("code/service/bin/Debug/service.dll")
        try home.file("code/native/CMakeLists.txt")
        try home.file("code/native/cmake-build-debug/CMakeCache.txt")
        let scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        let byName = Dictionary(uniqueKeysWithValues: scan.projects.map { ($0.name, Set($0.buildFolders.map(\.name))) })
        #expect(byName["web"] == ["node_modules", ".next"])
        #expect(byName["engine"] == ["target"])
        #expect(byName["kit"] == [".build"])
        #expect(byName["ml"] == [".venv", ".mypy_cache"])
        #expect(byName["app"] == [".dart_tool", "build"])
        #expect(byName["android"] == [".gradle", "app/build"])
        #expect(byName["service"] == ["obj", "bin"])
        #expect(byName["native"] == ["cmake-build-debug"])
        #expect(scan.projects.first { $0.name == "android" }?.kinds == [.gradle])
        #expect(!scan.partial)
    }

    @Test func aFolderIsOnlyBuildOutputWithProof() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/build/report.pdf")          // Node has no rule for build: it may be the only copy
        try home.file("code/engine/Cargo.toml")
        try home.file("code/engine/target/notes.txt")       // no CACHEDIR.TAG: not Cargo's
        try home.file("code/ml/requirements.txt")
        try home.file("code/ml/.venv/data.csv")             // no pyvenv.cfg: not a virtual environment
        try home.file("Documents/loose/node_modules/x.js")  // no package.json: not a project
        let scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.allSatisfy { $0.buildFolders.isEmpty })
        #expect(Set(scan.projects.map(\.name)) == ["web", "engine", "ml"])
    }

    @Test func aCommittedVendorFolderStays() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/site/composer.json")
        try home.file("code/site/vendor/autoload.php")
        try home.folder("code/site/.git")
        let before = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(before.projects.first?.buildFolders.isEmpty == true)
        try home.write("code/site/.gitignore", "/vendor/\n.env\n")
        let after = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(after.projects.first?.buildFolders.map(\.name) == ["vendor"])
    }

    @Test func committedPodsStayWhenTheRepositoryStartsAboveTheProject() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.folder("code/app/.git")
        try home.folder("code/app/ios/App.xcodeproj")
        try home.file("code/app/ios/Pods/Manifest.lock")
        var scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.map(\.name) == ["ios"])
        #expect(scan.projects.first?.buildFolders.isEmpty == true, "no .gitignore names Pods: it may be committed")
        try home.write("code/app/.gitignore", "/Pods\n")
        scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.first?.buildFolders.isEmpty == true, "/Pods at the root ignores only the root's Pods")
        try home.write("code/app/.gitignore", "ios/Pods/\n")
        scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.first?.buildFolders.map(\.name) == ["Pods"])
        try home.write("code/app/.gitignore", "Pods\n!ios/Pods\n")
        scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.first?.buildFolders.isEmpty == true, "a later negation wins")
    }

    @Test func aStrayMarkerNeverMakesDownloadsAProject() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("Downloads/package.json")
        try home.file("Downloads/node_modules/a.js")
        try home.file("Downloads/demo/Cargo.toml")
        try home.file("Downloads/demo/target/CACHEDIR.TAG")
        let scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.map(\.name) == ["demo"])
        #expect(scan.projects.first?.buildFolders.map(\.name) == ["target"])
    }

    @Test func aClonedFileCountsOnlyWhatItDoesNotShare() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.write("store/package.bin", String(repeating: "z", count: 400_000))
        try home.folder("code/web/node_modules")
        let source = home.url.appendingPathComponent("store/package.bin").path
        let clone = home.url.appendingPathComponent("code/web/node_modules/package.bin").path
        try #require(clonefile(source, clone, 0) == 0, "APFS clones are needed for this check")
        try home.write("code/web/node_modules/own.bin", String(repeating: "o", count: 50_000))
        let scanned = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        let folder = try #require(scanned.projects.first?.buildFolders.first)
        #expect(folder.bytes >= 50_000 && folder.bytes < 400_000, "\(folder.bytes)")
    }

    @Test func aProjectTheSearchDidNotFinishSaysSo() throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        for index in 0..<6 { try home.file("code/web/packages/part\(index)/index.js") }
        var limits = Self.everything
        limits.maximumDirectories = 4
        let (found, partial) = DeveloperProjectScanner.search(home: home.url, excluding: [], limits: limits)
        #expect(partial)
        #expect(found.first?.fullyRead == false)
    }

    @Test func aMonorepoIsOneProjectButANestedRepositoryIsItsOwn() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/mono/package.json")
        try home.folder("code/mono/.git")
        try home.file("code/mono/node_modules/a.js")
        try home.file("code/mono/packages/web/package.json")
        try home.file("code/mono/packages/web/node_modules/b.js")
        try home.file("code/mono/packages/web/.next/BUILD_ID")
        try home.file("code/mono/tools/lib/Cargo.toml")
        try home.folder("code/mono/tools/lib/.git")
        try home.file("code/mono/tools/lib/target/CACHEDIR.TAG")
        let scan = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        #expect(scan.projects.map(\.name) == ["mono", "lib"])
        let mono = try #require(scan.projects.first { $0.name == "mono" })
        #expect(Set(mono.buildFolders.map(\.name)) == ["node_modules", "packages/web/node_modules", "packages/web/.next"])
        #expect(scan.projects.first { $0.name == "lib" }?.buildFolders.map(\.name) == ["target"])
    }

    @Test func sizesCountAllocatedSpaceAndLeaveOutSharedFiles() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.write("code/web/node_modules/big.bin", String(repeating: "x", count: 20_000))
        try home.write("store/shared.bin", String(repeating: "y", count: 40_000))
        try FileManager.default.linkItem(at: home.url.appendingPathComponent("store/shared.bin"),
                                         to: home.url.appendingPathComponent("code/web/node_modules/linked.bin"))
        let scanned = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        let folder = try #require(scanned.projects.first?.buildFolders.first)
        #expect(folder.bytes >= 20_000 && folder.bytes < 40_000)
        #expect(folder.sharesFiles)
        #expect(!folder.partial)
    }

    @Test func lastChangedComesFromTheProjectNotItsBuildFolders() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/src/index.js")
        try home.file("code/web/node_modules/a.js")
        let old = Date(timeIntervalSinceNow: -90 * 86_400)
        for path in ["code/web/package.json", "code/web/src/index.js", "code/web/src", "code/web"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home.url.appendingPathComponent(path).path)
        }
        let scanned = await DeveloperProjectScanner.scan(home: home.url, limits: Self.everything)
        let project = try #require(scanned.projects.first)
        let changed = try #require(project.lastChanged)
        #expect(abs(changed.timeIntervalSince(old)) < 2)
    }

    @Test func cleanupChecksTheFolderAgainOnDisk() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/node_modules/a.js")
        try home.file("code/web/packages/ui/package.json")
        try home.file("code/web/packages/ui/node_modules/b.js")
        let project = home.url.appendingPathComponent("code/web")
        #expect(DeveloperProjectScanner.isBuildFolder(project.appendingPathComponent("node_modules"), project: project))
        #expect(DeveloperProjectScanner.isBuildFolder(project.appendingPathComponent("packages/ui/node_modules"), project: project))
        #expect(!DeveloperProjectScanner.isBuildFolder(project.appendingPathComponent("packages"), project: project))
        #expect(!DeveloperProjectScanner.isBuildFolder(home.url.appendingPathComponent("code/other/node_modules"), project: project))
        #expect(!DeveloperProjectScanner.isBuildFolder(project.appendingPathComponent("node_modules/../src"), project: project))
        try FileManager.default.removeItem(at: project.appendingPathComponent("package.json"))
        #expect(!DeveloperProjectScanner.isBuildFolder(project.appendingPathComponent("node_modules"), project: project))
    }

    @Test func linksAreNotFollowedAndSkippedFoldersAreNotRead() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("outside/real/package.json")
        try home.file("outside/real/node_modules/a.js")
        try home.folder("code")
        try FileManager.default.createSymbolicLink(at: home.url.appendingPathComponent("code/linked"),
            withDestinationURL: home.url.appendingPathComponent("outside"))
        try home.file("old/web/package.json")
        try FileManager.default.createSymbolicLink(at: home.url.appendingPathComponent("outside/real/node_modules/up"),
            withDestinationURL: home.url)
        let scan = await DeveloperProjectScanner.scan(home: home.url, excluding: [home.url.appendingPathComponent("old").path], limits: Self.everything)
        #expect(scan.projects.map(\.name) == ["real"])
    }

    @Test func foldersTooSmallToMatterAreLeftOut() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/node_modules/a.js")
        let scan = await DeveloperProjectScanner.scan(home: home.url)
        #expect(scan.projects.first?.buildFolders.isEmpty == true)
    }

    @Test func sourceFoldersInsideAProjectAreNotSearched() throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/web/package.json")
        try home.file("code/web/src/deep/package.json")
        try home.file("code/web/src/deep/node_modules/a.js")
        try home.file("code/web/apps/site/package.json")
        try home.file("code/web/apps/site/node_modules/b.js")
        let (found, _) = DeveloperProjectScanner.search(home: home.url, excluding: [], limits: Self.everything)
        #expect(found.first?.folders.map(\.name) == ["apps/site/node_modules"])
    }

    @Test func aWalkCutShortSaysSo() async throws {
        let home = try Home()
        defer { home.remove() }
        for index in 0..<10 { try home.file("code/p\(index)/package.json") }
        var limits = DeveloperProjectScanner.Limits()
        limits.maximumDirectories = 3
        let scan = await DeveloperProjectScanner.scan(home: home.url, limits: limits)
        #expect(scan.partial)
    }

    private struct Home {
        let url: URL
        init() throws {
            url = URL(fileURLWithPath: "/private/tmp/RoomScanner-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        func folder(_ path: String) throws {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        func file(_ path: String) throws { try write(path, "x") }
        func write(_ path: String, _ text: String) throws {
            try folder((path as NSString).deletingLastPathComponent)
            try Data(text.utf8).write(to: url.appendingPathComponent(path))
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }
}
