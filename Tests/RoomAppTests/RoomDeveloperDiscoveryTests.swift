import Foundation
import Synchronization
import Testing
@testable import RoomApp
@testable import RoomCore

#if !ROOM_APP_STORE
@Suite("Developer: found without being told") @MainActor
struct RoomDeveloperDiscoveryTests {
    @Test func oneScanReadsFoundProjectsAndKnownToolFoldersWithNothingChosen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let requests = Mutex<[DeveloperResourcesRequest]>([])
        let model = fixture.model { request in requests.withLock { $0.append(request) } }
        #expect(model.canScan && model.manualLocations.isEmpty)
        // Simulator runtimes live outside any home, so a Mac with Xcode lists them too.
        #expect(Set(model.automaticLocations.map(\.role)).subtracting([.simulatorRuntimes]) == [.gradle, .codex])

        model.scan()
        try await fixture.wait { !model.isScanning }

        let seen = requests.withLock { $0 }
        #expect(seen.map(\.scope) == [.review, .toolStorage, .aiTools])
        #expect(seen.first?.projectRoots.map(\.lastPathComponent) == ["alpha"])
        #expect(seen.first?.gradleHomes.map(\.lastPathComponent) == [".gradle"])
        #expect(model.progress == "Review complete" && !model.accessRevision.contains { $0.contains("auto:") })
        // Nothing was approved or stored for what Room found.
        model.accessChanged()
        #expect(model.report != nil, "found folders are not approvals that can be lost")
    }

    @Test func aSkippedFolderStaysOutAfterRelaunchAndCanComeBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model { _ in }
        let gradle = try #require(model.automaticLocations.first { $0.role == .gradle })
        model.skip(gradle)
        #expect(!model.locations.contains { $0.role == .gradle })
        let relaunched = fixture.model { _ in }
        #expect(!relaunched.locations.contains { $0.role == .gradle })
        #expect(relaunched.skippedPaths == [gradle.folder.url.standardizedFileURL.path])
        relaunched.include(relaunched.skippedPaths[0])
        #expect(relaunched.locations.contains { $0.role == .gradle })
    }

    @MainActor private struct Fixture {
        let name = "RoomDeveloperDiscovery-" + UUID().uuidString
        let home: URL
        let defaults: UserDefaults

        init() throws {
            home = URL(fileURLWithPath: "/private/tmp/" + name, isDirectory: true)
            defaults = try #require(UserDefaults(suiteName: name))
            for folder in [".gradle", ".codex", "code/alpha"] {
                try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            try Data("x".utf8).write(to: home.appendingPathComponent("code/alpha/settings.gradle"))
        }

        func model(_ seen: @escaping @Sendable (DeveloperResourcesRequest) -> Void) -> RoomDeveloperModel {
            RoomDeveloperModel(access: RoomFileAccess(defaults: defaults), defaults: defaults,
                unreferencedStore: .init(directory: home), home: home,
                discovery: RoomDeveloperDiscovery { home, skipped in DeveloperProjectFinder.find(home: home, excluding: skipped) },
                scanner: { request, _ in
                    seen(request)
                    return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
                        projectWrappers: [], issues: [], cancelled: false, isPartial: false)
                })
        }

        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            try #require(condition())
        }

        func remove() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: home)
        }
    }
}
#endif
