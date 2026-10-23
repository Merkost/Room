import Foundation
import Synchronization
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Developer saved folder reuse") @MainActor
struct RoomDeveloperAccessReuseTests {
    @Test("Saved choices retain exact available IDs and exclude only the assigned role")
    func choicesAreExactAndRoleSpecific() throws {
        let fixture = try DeveloperReuseFixture(includeUnavailable: true)
        defer { fixture.remove() }
        let model = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults)

        // Both folders have the same basename; their exact paths distinguish them.
        #expect(model.reusableFolders(for: .android).map(\.id) == ["approved-a", "approved-z"])
        #expect(model.reusableFolders(for: .android).map(\.url) == [fixture.alpha, fixture.zeta])
        model.attach(role: .android, to: "approved-a")
        #expect(model.reusableFolders(for: .android).map(\.id) == ["approved-z"])
        #expect(model.reusableFolders(for: .gradle).map(\.id) == ["approved-a", "approved-z"])
        #expect(model.locations.count == 1)
        #expect(fixture.creations.value == 0)
    }

    @Test("Reusing one bookmark persists both roles and sends only that exact scope to real resource inspection")
    func reusePersistsWithoutAnotherApproval() async throws {
        let fixture = try DeveloperReuseFixture()
        defer { fixture.remove() }
        let before = fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks")
        let request = Mutex<DeveloperResourcesRequest?>(nil)
        let engine = DeveloperResourcesEngine()
        let model = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults, scanner: { value, progress in
            request.withLock { $0 = value }
            return await engine.scan(request: value, progress: progress)
        })

        model.attach(role: .android, to: "approved-a")
        model.attach(role: .gradle, to: "approved-a")
        model.scan()
        try await waitForScan(model)

        let actual = try #require(request.withLock { $0 })
        #expect(actual.approvedFolders == [fixture.alpha])
        #expect(actual.avdRoots == [fixture.alpha])
        #expect(actual.gradleHomes == [fixture.alpha])
        #expect(actual.projectRoots.isEmpty)
        #expect(model.report?.androidDevices.map(\.name) == ["Review_Device"])
        #expect(model.report?.gradleResources.contains { $0.version == "8.9" } == true)
        #expect(fixture.creations.value == 0)
        #expect(fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks") == before)

        let reopened = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults)
        #expect(Set(reopened.locations.map(\.id)) == ["android:approved-a", "gradle:approved-a"])
        #expect(reopened.reusableFolders(for: .android).map(\.id) == ["approved-z"])
        #expect(reopened.reusableFolders(for: .gradle).map(\.id) == ["approved-z"])
    }

    @Test("Removing a developer role keeps shared access and makes that role reusable again")
    func removingRolePreservesBookmark() throws {
        let fixture = try DeveloperReuseFixture()
        defer { fixture.remove() }
        let model = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults)
        model.attach(role: .android, to: "approved-a")
        model.attach(role: .gradle, to: "approved-a")
        let before = fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks")
        let android = try #require(model.locations.first { $0.role == .android })

        model.remove(android)

        #expect(model.locations.map(\.id) == ["gradle:approved-a"])
        #expect(model.reusableFolders(for: .android).map(\.id) == ["approved-a", "approved-z"])
        #expect(model.reusableFolders(for: .gradle).map(\.id) == ["approved-z"])
        #expect(fixture.access.folders.map(\.id) == ["approved-z", "approved-a"])
        #expect(fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks") == before)
        #expect(fixture.creations.value == 0)
        let reopened = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults)
        #expect(reopened.locations.map(\.id) == ["gradle:approved-a"])
    }

    @Test("Unavailable and forgotten menu IDs cannot attach or transfer to a replacement bookmark")
    func staleChoicesNeverGainAuthority() throws {
        let fixture = try DeveloperReuseFixture(includeUnavailable: true)
        defer { fixture.remove() }
        let model = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults)
        let staleChoice = try #require(model.reusableFolders(for: .project).first { $0.id == "approved-a" })
        let before = fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks")

        for id in ["stale", "unavailable", "unknown", fixture.alpha.appendingPathComponent("Review_Device.avd").path] {
            model.attach(role: .project, to: id)
        }
        #expect(model.locations.isEmpty)
        #expect(fixture.defaults.data(forKey: "RoomDeveloperFolderRoles") == nil)
        #expect(fixture.defaults.data(forKey: "RoomApprovedFolderBookmarks") == before)

        // Simulate access forgotten while a native menu still holds its old ID.
        fixture.access.forget(id: staleChoice.id)
        model.attach(role: .project, to: staleChoice.id)
        #expect(model.locations.isEmpty)
        #expect(fixture.defaults.data(forKey: "RoomDeveloperFolderRoles") == nil)

        // Explicit new approval of the same path has a NEW identity, never an alias.
        _ = try fixture.access.remember(fixture.alpha)
        let replacement = try #require(fixture.access.folders.first { $0.url == fixture.alpha })
        #expect(replacement.id != staleChoice.id)
        model.attach(role: .project, to: staleChoice.id)
        #expect(model.locations.isEmpty)
        model.attach(role: .project, to: replacement.id)
        #expect(model.locations.map(\.folder.id) == [replacement.id])
        #expect(fixture.creations.value == 1)
    }

    @Test("Duplicate or in-flight attachment preserves measured results and the frozen scan scope")
    func noOpAndScanGuardKeepResults() async throws {
        let fixture = try DeveloperReuseFixture()
        defer { fixture.remove() }
        let first = DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], issues: [], cancelled: false, isPartial: false)
        let second = DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
            projectWrappers: [], issues: [], cancelled: false, isPartial: false)
        let requests = Mutex<[DeveloperResourcesRequest]>([])
        let gate = DeferredDeveloperReuseScan()
        let model = RoomDeveloperModel(access: fixture.access, defaults: fixture.defaults, scanner: { request, _ in
            let call = requests.withLock { values in values.append(request); return values.count }
            if call > 1 { await gate.wait() }
            return call == 1 ? first : second
        })
        defer { model.stop(); Task { await gate.finish() } }
        model.attach(role: .project, to: "approved-a")
        model.scan()
        try await waitForScan(model)
        #expect(model.report?.id == first.id)
        let roles = fixture.defaults.data(forKey: "RoomDeveloperFolderRoles")

        model.attach(role: .project, to: "approved-a")
        #expect(model.report?.id == first.id)
        #expect(fixture.defaults.data(forKey: "RoomDeveloperFolderRoles") == roles)

        model.scan()
        #expect(model.isScanning)
        model.attach(role: .gradle, to: "approved-z")
        #expect(model.report?.id == first.id)
        #expect(model.locations.map(\.id) == ["project:approved-a"])
        #expect(fixture.defaults.data(forKey: "RoomDeveloperFolderRoles") == roles)
        await gate.finish()
        try await waitForScan(model)
        #expect(model.report?.id == second.id)
        let actual = requests.withLock { $0 }
        #expect(actual.count == 2)
        #expect(actual.last?.approvedFolders == [fixture.alpha])
        #expect(actual.last?.projectRoots == [fixture.alpha])
        #expect(actual.last?.gradleHomes.isEmpty == true)
        #expect(fixture.creations.value == 0)
    }

    private func waitForScan(_ model: RoomDeveloperModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.isScanning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!model.isScanning)
    }
}

@MainActor private final class DeveloperBookmarkCreations { var value = 0 }

@MainActor private struct DeveloperReuseFixture {
    let name: String
    let root: URL
    let defaults: UserDefaults
    let access: RoomFileAccess
    let creations: DeveloperBookmarkCreations
    var alpha: URL { root.appendingPathComponent("A/Shared", isDirectory: true) }
    var zeta: URL { root.appendingPathComponent("Z/Shared", isDirectory: true) }

    init(includeUnavailable: Bool = false) throws {
        let name = "RoomDeveloperReuse-" + UUID().uuidString
        let root = URL(fileURLWithPath: "/private/tmp/" + name, isDirectory: true)
        let defaults = try #require(UserDefaults(suiteName: name))
        let alpha = root.appendingPathComponent("A/Shared", isDirectory: true)
        let zeta = root.appendingPathComponent("Z/Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha.appendingPathComponent("Review_Device.avd"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alpha.appendingPathComponent("caches/8.9"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zeta, withIntermediateDirectories: true)
        try Data("AvdId=Review_Device\ntarget=android-35\n".utf8).write(to: alpha.appendingPathComponent("Review_Device.avd/config.ini"))
        try Data("owned version cache".utf8).write(to: alpha.appendingPathComponent("caches/8.9/generated.bin"))
        var records = [DeveloperSavedAccessRecord(id: "approved-z", url: zeta),
                       DeveloperSavedAccessRecord(id: "approved-a", url: alpha)]
        if includeUnavailable {
            records += [DeveloperSavedAccessRecord(id: "stale", url: root.appendingPathComponent("Stale"), prefix: "stale:"),
                        DeveloperSavedAccessRecord(id: "unavailable", url: root.appendingPathComponent("Unavailable"), prefix: "missing:")]
        }
        defaults.set(try JSONEncoder().encode(records), forKey: "RoomApprovedFolderBookmarks")
        let creations = DeveloperBookmarkCreations()
        let access = RoomFileAccess(defaults: defaults, bookmarkResolver: { data in
            let value = String(decoding: data, as: UTF8.self)
            if value.hasPrefix("missing:") { throw CocoaError(.fileReadNoSuchFile) }
            let stale = value.hasPrefix("stale:")
            let path = stale ? String(value.dropFirst(6)) : value
            return RoomBookmarkResolution(url: URL(fileURLWithPath: path, isDirectory: true), isStale: stale)
        }, bookmarkCreator: { url in
            creations.value += 1
            return Data(url.path.utf8)
        })
        self.name = name; self.root = root; self.defaults = defaults; self.access = access; self.creations = creations
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct DeveloperSavedAccessRecord: Encodable {
    let id: String
    let bookmark: Data
    let lastKnownPath: String
    let lastKnownName: String
    init(id: String, url: URL, prefix: String = "") {
        self.id = id; bookmark = Data((prefix + url.path).utf8)
        lastKnownPath = url.path; lastKnownName = url.lastPathComponent
    }
}

private actor DeferredDeveloperReuseScan {
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !finished else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        finished = true
        continuation?.resume(); continuation = nil
    }
}
