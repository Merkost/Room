import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Additional cache and managed-storage catalogue", .serialized)
struct AdditionalCatalogueTests {
    @Test("Automatic catalogues never request app-container metadata, including Docker and overrides")
    func automaticContainerAccessRequiresApproval() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let container = fixture.url("Library/Containers/com.example.app/Data/Library/Caches")
        let group = fixture.url("Library/Group Containers/group.example.app/Library/Caches")
        let base = CacheConfiguration(roots: [
            CacheRoot(id: "preexisting-container", title: "Container", subtitle: "", symbol: "folder", category: "apps",
                url: container, consequence: "Inspect", cleanupPolicy: .inspectOnly("Inspect")),
            CacheRoot(id: "preexisting-library", title: "Library", subtitle: "", symbol: "folder", category: "apps",
                url: fixture.url("Library"), consequence: "Inspect", cleanupPolicy: .inspectOnly("Inspect"))
        ], protectedLocations: [ProtectedLocation(id: "group-state", title: "State", url: group, reason: "Keep")],
            homeDirectory: fixture.home)
        let opened = Mutex<[String]>([])
        let opener: (URL) -> Int32 = { url in
            opened.withLock { $0.append(url.path) }
            return -1
        }
        let environment = ["UV_CACHE_DIR": container.path, "HF_HOME": group.path,
            "PIP_CACHE_DIR": fixture.url("Library").path,
            "GOCACHE": fixture.url("Library/containers/com.example.lowercase/cache").path]
        // Exercise the production default and the explicit zero bound. Neither
        // may enumerate even the container parent before applying that bound.
        let automatic = CacheConfiguration.addingAdditionalSources(to: base, environment: environment,
            metadataDirectoryOpener: opener)
        let zero = CacheConfiguration.addingAdditionalSources(to: base, environment: environment,
            maximumSandboxRoots: 0, metadataDirectoryOpener: opener)
        #expect(opened.withLock { !$0.isEmpty })
        #expect(opened.withLock { paths in !paths.contains { $0.contains("/Library/Containers") || $0.contains("/Library/Group Containers") || $0.contains("/Library/containers") } })
        for config in [automatic, zero] {
            #expect(!config.roots.contains { $0.id.hasPrefix("preexisting-") || $0.id.hasPrefix("docker-") || $0.id.hasPrefix("sandbox-cache-") || $0.id.hasPrefix("custom-") })
            #expect(config.protectedLocations.map(\.id) == ["group-state"])
            #expect(config.protectedMeasurementExclusions == [group])
            #expect(config.roots.contains { $0.id == "swiftpm-prebuilts" })
            #expect(config.roots.contains { $0.id == "cargo-index" })
            #expect(config.inspectionIssues.contains { $0.message.contains("folder approval") })
        }
    }

    @Test("Automatic cache scans defer app-container storage to an explicitly selected Disk Map folder")
    func selectedContainerDiskMapRemainsAvailable() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let cache = try fixture.write("Library/Containers/com.example.app/Data/Library/Caches/resource.bin", count: 8_000)
        _ = try fixture.write("Library/Containers/com.example.app/Data/Documents/work.txt", count: 12_000)
        _ = try fixture.write("Library/Group Containers/group.example.app/Library/Caches/resource.bin", count: 16_000)
        _ = try fixture.write("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", count: 20_000)
        let known = try fixture.write("cache/finished.bin", count: 4_000)
        let base = CacheConfiguration(roots: [
            CacheRoot(id: "known", title: "Known cache", subtitle: "", symbol: "folder", category: "developer",
                url: fixture.url("cache"), consequence: "Rebuild", minimumAge: 0)
        ], protectedLocations: [ProtectedLocation(id: "container-state", title: "State",
            url: fixture.url("Library/Containers/com.example.app/Data"), reason: "Keep")], homeDirectory: fixture.home)
        let additional = CacheConfiguration.addingAdditionalSources(to: base, environment: [:])
        let full = CacheConfiguration.addingDiscoveredSources(to: additional, temporaryDirectory: fixture.temporary)
        let report = await fixture.engine(full).scan()
        #expect(report.totalBytes == (try fixture.allocated(known)))
        #expect(report.protectedData.isEmpty)
        #expect(report.eligibleEntries.map(\.url) == [known])
        #expect(report.issues.contains { $0.message.contains("folder approval") })
        let selected = await DiskMapEngine().scan(url: cache.deletingLastPathComponent())
        #expect(selected.fileCount == 1)
        #expect(selected.allocatedBytes == (try fixture.allocated(cache)))
        #expect(selected.children.map(\.url) == [cache])
        #expect(selected.issues.isEmpty)
    }

    @Test("Deferred protected boundaries survive additional, deep and discovered catalogue composition")
    func broadProtectedAncestorRemainsHeld() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/finished.bin", count: 4_000)
        let generated = try fixture.write("temporary/_karma_webpack_123/data", count: 8_000)
        let old = Date().addingTimeInterval(-30 * 86_400)
        for url in [generated, generated.deletingLastPathComponent()] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        let base = CacheConfiguration(roots: [
            CacheRoot(id: "known", title: "Known cache", subtitle: "", symbol: "folder", category: "developer",
                url: fixture.url("cache"), consequence: "Rebuild", minimumAge: 0)
        ], protectedLocations: [ProtectedLocation(id: "all-work", title: "Work", url: fixture.home, reason: "Keep this work")],
            homeDirectory: fixture.home)
        let additional = CacheConfiguration.addingAdditionalSources(to: base, environment: [:])
        for intermediate in [additional, CacheConfiguration.addingDeepSources(to: additional)] {
            let config = CacheConfiguration.addingDiscoveredSources(to: intermediate, temporaryDirectory: fixture.temporary)
            #expect(config.protectedLocations.contains { $0.id == "all-work" && $0.url == fixture.home })
            #expect(config.protectedMeasurementExclusions == [fixture.home])
            let report = await fixture.engine(config).scan()
            #expect(report.protectedData.isEmpty)
            #expect(report.eligibleEntries.isEmpty)
            #expect(report.groups.first { $0.id == "known" }?.isInspectionOnly == true)
            let karma = try #require(report.groups.first { $0.id == "temporary-karma" })
            let expectedKarmaPath = generated.deletingLastPathComponent().path
            let entry = try #require(karma.entries.first { $0.url.path == expectedKarmaPath },
                "The generated fixture must be measured. Entry paths: \(karma.entries.map { $0.url.path })")
            if case .blocked(let reason) = entry.eligibility {
                #expect(reason.contains("protected"))
            } else { Issue.record("A later catalogue addition escaped a retained protection boundary") }
            let disk = await DiskMapEngine().scan(url: generated.deletingLastPathComponent())
            let analysis = StorageAnalyzer.analyze(report: disk, configuration: config)
            #expect(!analysis.findings.isEmpty)
            #expect(analysis.findings.allSatisfy { $0.disposition == .protected })
        }
    }

    @Test("Automatic profile discovery cannot follow an app-support alias into a protected container")
    func profileDiscoveryRejectsLinkedAncestors() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let support = try fixture.directory("Library/Containers/com.example.app/Data/Library/Application Support/Codex")
        _ = try fixture.directory("Library/Containers/com.example.app/Data/Library/Application Support/Codex/Partitions/UnapprovedProfile")
        _ = try fixture.directory("Library/Application Support")
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Application Support/Codex"), withDestinationURL: support)
        let config = CacheConfiguration.addingDeepSources(to: fixture.base)
        #expect(!config.roots.contains { $0.url.path.contains("/Partitions/UnapprovedProfile/") })
        let aliasCache = fixture.url("Library/Application Support/Codex/Cache")
        let base = CacheConfiguration(roots: [
            CacheRoot(id: "aliased-cache", title: "Aliased", subtitle: "", symbol: "folder", category: "apps",
                url: aliasCache, consequence: "Inspect", cleanupPolicy: .inspectOnly("Inspect"))
        ], protectedLocations: [ProtectedLocation(id: "aliased-history", title: "History",
            url: fixture.url("Library/Application Support/Codex/history"), reason: "Keep")], homeDirectory: fixture.home)
        let automatic = CacheConfiguration.addingAdditionalSources(to: base, environment: [:])
        #expect(!automatic.roots.contains { $0.id == "aliased-cache" })
        #expect(automatic.protectedLocations.map(\.id) == ["aliased-history"])
        #expect(automatic.protectedMeasurementExclusions == [fixture.url("Library/Application Support/Codex/history")])
    }

    @Test("Explicit cache additions preserve preferences, app state and source checkouts")
    func explicitCacheBoundaries() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        _ = try fixture.directory("Library/Application Support/Claude")
        _ = try fixture.directory("Library/Application Support/Notion")
        let config = fixture.additional()
        let allowed = config.roots.filter { if case .allowed = $0.cleanupPolicy { return true }; return false }
        let paths = allowed.map { fixture.relative($0.url) }
        #expect(paths.contains("Library/Application Support/Claude/Cache"))
        #expect(paths.contains("Library/Application Support/Notion/GPUCache"))
        #expect(paths.contains("Library/Caches/org.swift.swiftpm/prebuilts/swift-syntax"))
        #expect(!paths.contains("Library/Caches/org.swift.swiftpm/prebuilts"))
        #expect(paths.contains(".cargo/registry/index"))
        #expect(paths.contains(".cargo/git/db"))
        #expect(!paths.contains(".cargo/registry/src"))
        #expect(!paths.contains(".cargo/git/checkouts"))
        #expect(!paths.contains { $0.contains("IndexedDB") || $0.contains("Local Storage") || $0.contains("Service Worker") })
        #expect(allowed.allSatisfy { !$0.guardedProcesses.isEmpty && $0.minimumAge >= 7 * 86_400 })
    }

    @Test("Managed resources migrate exact informational roots and broad inventories count them once")
    func managedMigrationAndExclusions() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let uv = try fixture.write(".cache/uv/archive/data", count: 8_000)
        let browser = try fixture.write("Library/Caches/ms-playwright/chromium/browser", count: 12_000)
        let models = try fixture.write(".cache/lm-studio/models/vendor/weights.gguf", count: 16_000)
        let other = try fixture.write(".cache/unknown/state", count: 20_000)
        let base = CacheConfiguration(roots: [], protectedLocations: [
            ProtectedLocation(id: "uv-managed", title: "uv", url: fixture.url(".cache/uv"), reason: "Keep"),
            ProtectedLocation(id: "playwright-runtime", title: "Browser", url: fixture.url("Library/Caches/ms-playwright"), reason: "Keep")
        ], homeDirectory: fixture.home)
        let additional = fixture.additional(base)
        #expect(additional.protectedLocations.isEmpty)
        for id in ["uv-managed", "playwright-runtime", "lmstudio-models-legacy"] {
            let root = try #require(additional.roots.first { $0.id == id })
            guard case .inspectOnly = root.cleanupPolicy else { Issue.record("Managed root allowed cleanup: \(id)"); return }
        }
        let config = CacheConfiguration.addingDiscoveredSources(to: additional, temporaryDirectory: fixture.temporary,
            inspectionTimeLimit: 60)
        let report = await fixture.engine(config).scan()
        #expect(report.totalBytes == (try fixture.allocated(uv)) + (try fixture.allocated(browser))
            + (try fixture.allocated(models)) + (try fixture.allocated(other)))
        #expect(report.groups.filter { ["uv-managed", "playwright-runtime", "lmstudio-models-legacy"].contains($0.id) }.allSatisfy { $0.isInspectionOnly == true })
        #expect(report.eligibleEntries.isEmpty)
        #expect(Set(config.roots.map(\.id)).count == config.roots.count)
        #expect(Set(config.roots.filter { $0.childNameRule == nil }.map { $0.url.path }).count
            == config.roots.filter { $0.childNameRule == nil }.count)
    }

    @Test("Docker is one inspect-only sparse file measured by allocated blocks, never its sibling volumes")
    func dockerSparseFile() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let image = fixture.url("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        _ = try fixture.directory(fixture.relative(image.deletingLastPathComponent()))
        #expect(FileManager.default.createFile(atPath: image.path, contents: nil))
        let handle = try FileHandle(forWritingTo: image)
        try handle.seek(toOffset: 128 * 1_024 * 1_024)
        try handle.write(contentsOf: Data(repeating: 0x5a, count: 4_096))
        try handle.close()
        _ = try fixture.write("Library/Containers/com.docker.docker/Data/vms/0/data/persistent-volume", count: 24_000)
        let config = fixture.additional()
        let docker = try #require(config.roots.first { $0.id == "docker-disk" })
        #expect(docker.scope == .singleFile)
        let report = await fixture.engine(config).scan()
        let group = try #require(report.groups.first { $0.id == "docker-disk" })
        #expect(group.totalBytes == (try fixture.allocated(image)))
        #expect(group.totalBytes < 128 * 1_024 * 1_024)
        #expect(group.entries.count == 1)
        #expect(group.isInspectionOnly == true)
        #expect(group.eligibleEntries.isEmpty)
    }

    @Test("Sandbox discovery accepts only nonempty exact cache folders and refuses linked ancestors or lookalikes")
    func sandboxBoundaries() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        _ = try fixture.write("Library/Containers/com.example.real/Data/Library/Caches/resource", count: 4_000)
        _ = try fixture.write("Library/Group Containers/group.example.real/Library/Caches/resource", count: 4_000)
        _ = try fixture.write("Library/Containers/com.example.lookalike/Data/Library/CachesBackup/document", count: 4_000)
        _ = try fixture.directory("Library/Containers/com.example.empty/Data/Library/Caches")
        let external = try fixture.directory("outside/Data/Library/Caches")
        _ = try fixture.write("outside/Data/Library/Caches/private-work", count: 8_000)
        let linked = fixture.url("Library/Containers/com.example.linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        _ = try fixture.directory("Library/Containers/com.example.parent-link")
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Containers/com.example.parent-link/Data"),
            withDestinationURL: fixture.url("outside/Data"))
        let config = fixture.additional()
        let sandboxes = config.roots.filter { $0.id.hasPrefix("sandbox-cache-") }
        #expect(sandboxes.count == 2)
        #expect(sandboxes.allSatisfy { $0.url.path.hasSuffix("/Library/Caches") })
        #expect(sandboxes.allSatisfy { $0.inspectionNodeLimit == 4_000 && $0.inspectionTimeLimit == 0.5 })
        #expect(!sandboxes.contains { $0.url.path.contains("linked") || $0.url.path.contains("parent-link") || $0.url.path.contains("empty") || $0.url.path.contains("lookalike") })
        #expect(sandboxes.map(\.id) == fixture.additional().roots.filter { $0.id.hasPrefix("sandbox-cache-") }.map(\.id))
    }

    @Test("Sandbox count and parent discovery caps produce explicit coverage issues")
    func sandboxCaps() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        for index in 0..<5 { _ = try fixture.directory("Library/Containers/com.example.empty\(index)/Data/Library/Caches") }
        for index in 0..<4 { _ = try fixture.write("Library/Containers/com.example.app\(index)/Data/Library/Caches/resource", count: 4_000) }
        let config = fixture.additional(maximum: 2)
        #expect(config.roots.filter { $0.id.hasPrefix("sandbox-cache-") }.count == 2)
        #expect(config.inspectionIssues.count == 1)
        let discovered = CacheConfiguration.addingDiscoveredSources(to: config, temporaryDirectory: fixture.temporary)
        #expect(discovered.inspectionIssues == config.inspectionIssues)
        let capped = CacheConfiguration.addingAdditionalSources(to: fixture.base, environment: [:],
            maximumSandboxRoots: 32, sandboxParentLimit: 1, sandboxDiscoveryTimeLimit: 60)
        #expect(!capped.inspectionIssues.isEmpty)
    }

    @Test("Custom locations must be physical strict descendants of home and remain inspect-only")
    func environmentBoundaries() throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let cache = try fixture.directory("custom-uv")
        let linked = fixture.url("linked-cache")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: cache)
        let accepted = fixture.additional(environment: ["UV_CACHE_DIR": cache.path])
        let root = try #require(accepted.roots.first { $0.id == "custom-uv" })
        guard case .inspectOnly = root.cleanupPolicy else { Issue.record("Custom cache gained cleanup eligibility"); return }
        for value in [fixture.home.path, "/private/tmp", "https://example.com/cache", linked.path,
                      fixture.home.path + "/custom-uv/../custom-uv"] {
            #expect(!fixture.additional(environment: ["UV_CACHE_DIR": value]).roots.contains { $0.id == "custom-uv" })
        }
        #expect(!fixture.additional(environment: ["UNRECOGNIZED_CACHE_DIR": cache.path]).roots.contains { $0.id.hasPrefix("custom-") })
    }

    @Test("Inspection-only reporting is preserved in progress and legacy encoded groups decode")
    func inspectionReporting() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        _ = try fixture.write(".cache/uv/archive/data", count: 8_000)
        let events = Mutex<[Bool?]>([])
        let report = await fixture.engine(fixture.additional()).scan { update in
            if let group = update.partialReport.groups.first(where: { $0.id == "uv-managed" }) {
                events.withLock { $0.append(group.isInspectionOnly) }
            }
        }
        let group = try #require(report.groups.first { $0.id == "uv-managed" })
        #expect(group.isInspectionOnly == true)
        #expect(events.withLock { !$0.isEmpty && $0.allSatisfy { $0 == true } })
        let data = try JSONEncoder().encode(group)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isInspectionOnly")
        let legacy = try JSONDecoder().decode(CacheGroup.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.isInspectionOnly == nil)
    }

    @Test("Dynamic catalogue providers resolve once on the engine actor, after initialization")
    @MainActor func deferredProvider() async throws {
        let fixture = try AdditionalFixture()
        defer { fixture.remove() }
        let called = Mutex<(count: Int, mainThread: Bool)>((0, false))
        let config = fixture.base
        let engine = CacheEngine(configurationProvider: {
            called.withLock { $0.count += 1; $0.mainThread = Thread.isMainThread }
            return config
        }, activityDirectory: fixture.url("activity"))
        #expect(called.withLock { $0.count } == 0)
        _ = await engine.scan()
        _ = await engine.scan()
        #expect(called.withLock { $0.count } == 1)
        #expect(called.withLock { !$0.mainThread })
    }
}

private struct AdditionalFixture: Sendable {
    let home: URL
    let temporary: URL
    var base: CacheConfiguration { CacheConfiguration(roots: [], homeDirectory: home) }
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/RoomAdditional-" + UUID().uuidString, isDirectory: true)
        temporary = home.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    func url(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: false) }
    func relative(_ url: URL) -> String { String(url.path.dropFirst(home.path.count + 1)) }
    @discardableResult func directory(_ path: String) throws -> URL {
        let value = url(path)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    func write(_ path: String, count: Int) throws -> URL {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5a, count: count).write(to: file)
        return file
    }
    func allocated(_ file: URL) throws -> Int64 {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        return Int64(info.st_blocks) * 512
    }
    func additional(_ config: CacheConfiguration? = nil, environment: [String: String] = [:], maximum: Int = 32) -> CacheConfiguration {
        CacheConfiguration.addingAdditionalSources(to: config ?? base, environment: environment,
            maximumSandboxRoots: maximum, sandboxDiscoveryTimeLimit: 60)
    }
    func engine(_ config: CacheConfiguration) -> CacheEngine {
        CacheEngine(configuration: config, activityDirectory: url("activity"), processProvider: { [] })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
