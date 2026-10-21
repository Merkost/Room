import Foundation
@testable import RoomCore
import Testing
@testable import RoomApp

@Suite("Truthful resource and monitor presentation") @MainActor
struct RoomPresentationTests {
    @Test func occupancyNeverInventsPressure() {
        let unknown = RoomMonitorPresentation.memory(total: 100, used: 99, available: 1,
            pressure: .unknown, swap: 0, showPressure: true, showSwap: true)
        #expect(unknown.tone == .neutral)
        #expect(unknown.detail.contains("Pressure unavailable"))
        let critical = RoomMonitorPresentation.memory(total: 100, used: 2, available: 98,
            pressure: .critical, swap: 20, showPressure: true, showSwap: false)
        #expect(critical.tone == .critical)
        #expect(critical.detail.contains("High pressure"))
        #expect(!critical.detail.contains("swap"))
        let hidden = RoomMonitorPresentation.memory(total: 100, used: 99, available: 1,
            pressure: .critical, swap: 20, showPressure: false, showSwap: true)
        let missingSwap = RoomMonitorPresentation.memory(total: 100, used: 20, available: 80,
            pressure: .normal, swap: nil, showPressure: true, showSwap: true)
        #expect(missingSwap.detail.contains("Swap unavailable"))
        #expect(hidden.tone == .neutral)
        #expect(!hidden.detail.contains("High pressure"))
    }

    @Test func unavailableCountersAndOutOfRangeCapacityStayHonest() {
        let unavailable = RoomMonitorPresentation.memory(total: 100, used: 0, available: 0,
            pressure: .normal, swap: 0, showPressure: true, showSwap: true)
        #expect(unavailable.value == "—")
        #expect(unavailable.fraction == nil)
        #expect(unavailable.tone == .neutral)
        #expect(RoomMonitorPresentation.storage(total: 100, available: 200).fraction == 1)
        #expect(RoomMonitorPresentation.storage(total: 100, available: -10).fraction == 0)
        #expect(RoomMonitorPresentation.storage(total: 0, available: 100).fraction == nil)
        #expect(RoomMonitorPresentation.storage(total: 100, available: 20).tone == .neutral)
    }

    @Test func aboutUsesActualBundleMetadataAndRejectsUnresolvedBuildValues() {
        let release = RoomAboutInformation(info: ["CFBundleDisplayName": "Room", "CFBundleShortVersionString": "2.4", "CFBundleVersion": "91"])
        #expect(release.versionLabel == "Version 2.4 (91)")
        let unresolved = RoomAboutInformation(info: ["CFBundleShortVersionString": "$(MARKETING_VERSION)"])
        #expect(unresolved.version == nil)
        #expect(unresolved.versionLabel == "Development build")
    }

    @Test func gradleVersionLanesDeduplicateSelectedProjectReferencesAndKeepSharedStorageSeparate() throws {
        let date = Date()
        let project = GradleProjectWrapper(projectURL: URL(fileURLWithPath: "/chosen/app"),
            propertiesURL: URL(fileURLWithPath: "/chosen/app/gradle/wrapper/gradle-wrapper.properties"),
            version: "9.1", distributionType: "bin", note: "Configured wrapper", isPartial: false)
        let activity = DeveloperResourceActivity(state: .unknown, processIDs: [], indicators: [], sampledAt: date)
        func resource(_ name: String, version: String?, bytes: Int64, uses: [GradleProjectWrapper]) -> GradleDeveloperResource {
            GradleDeveloperResource(url: URL(fileURLWithPath: "/chosen/.gradle/\(name)"), name: name,
                kind: version == nil ? .sharedCache : .versionCache, version: version, distributionType: nil,
                allocatedBytes: bytes, logicalBytes: bytes, isPartial: false, projectUses: uses,
                usageNote: "Selected wrappers only", evidence: [], activity: activity)
        }
        let groups = RoomDeveloperPresentation.groups([
            resource("caches/9.1", version: "9.1", bytes: 10, uses: [project]),
            resource("wrapper/dists/gradle-9.1-bin", version: "9.1", bytes: 15, uses: [project]),
            resource("caches/modules-2", version: nil, bytes: 5, uses: [])
        ])
        #expect(groups.count == 2)
        let version = try #require(groups.first(where: { $0.version == "9.1" }))
        #expect(version.bytes == 25)
        #expect(version.resources.count == 2)
        #expect(version.projects.count == 1)
        #expect(groups.last?.title == "Shared resources")
        #expect(RoomDeveloperPresentation.referenceTitle(0) == "No selected project reference")
        #expect(RoomDeveloperPresentation.activityTitle(.unknown) == "Activity unknown")
        #expect(RoomDeveloperPresentation.activityTitle(.notObserved) == "No use in sample")
        #expect(RoomDeveloperPresentation.sum([Int64.max, 1, -10]) == Int64.max)
    }

    @Test func developerReviewRequiresExplicitRoleSelections() {
        let suite = "RoomDeveloperPresentation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = RoomDeveloperModel(access: RoomFileAccess(defaults: defaults), defaults: defaults)
        #expect(model.locations.isEmpty)
        #expect(!model.canScan)
        model.scan()
        #expect(!model.isScanning)
        #expect(model.report == nil)
    }
    @Test func revokedFolderCannotRepublishALateDeveloperReport() async throws {
        let suite = "RoomDeveloperRevocation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(folder)
        let approved = try #require(access.folders.first)
        let gate = DeferredDeveloperScan()
        let model = RoomDeveloperModel(access: access, defaults: defaults, scanner: { request, _ in
            await gate.scan(request)
        })
        model.attach(role: .project, to: approved.id)
        model.scan()
        for _ in 0..<1_000 {
            if await gate.started { break }
            await Task.yield()
        }
        #expect(await gate.started)
        access.forget(id: approved.id)
        model.accessChanged() // persistent root observes shared bookmark revisions on every tab
        #expect(!model.isScanning)
        #expect(!model.canScan)
        await gate.complete()
        for _ in 0..<30 { await Task.yield() }
        #expect(model.report == nil)
        #expect(model.progress.isEmpty)
    }

}


private actor DeferredDeveloperScan {
    private var continuation: CheckedContinuation<DeveloperResourcesReport, Never>?
    private(set) var started = false
    func scan(_ request: DeveloperResourcesRequest) async -> DeveloperResourcesReport {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete() {
        continuation?.resume(returning: DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [],
            gradleResources: [], projectWrappers: [], issues: [], cancelled: false, isPartial: false))
        continuation = nil
    }
}
