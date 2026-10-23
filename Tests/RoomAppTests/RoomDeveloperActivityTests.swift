import Foundation
import Synchronization
import Testing
@testable import RoomApp
@testable import RoomCore

@Suite("Developer production activity wiring") @MainActor
struct RoomDeveloperActivityTests {
    @Test("The model passes the actual sampler evidence through the scanner boundary")
    func samplerEvidenceReachesResources() async throws {
        let suite = "Room-DeveloperActivity-" + UUID().uuidString
        let root = URL(fileURLWithPath: "/private/tmp/" + suite, isDirectory: true)
        let device = root.appendingPathComponent("Pixel.avd", isDirectory: true)
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        try Data("target=android-35\n".utf8).write(to: device.appendingPathComponent("config.ini"))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(root)
        let folder = try #require(access.folders.first)
        let evidence = DeveloperActivitySnapshot(processes: [DeveloperResourceProcess(processID: 901,
            name: "Owned emulator fixture", paths: [device.appendingPathComponent("userdata.img")])], isComplete: false)
        let calls = Mutex(0)
        let model = RoomDeveloperModel(access: access, defaults: defaults, activitySampler: {
            calls.withLock { $0 += 1 }; return evidence
        })
        model.attach(role: .android, to: folder.id)
        model.scan()
        for _ in 0..<1000 where model.isScanning { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isScanning)
        #expect(calls.withLock { $0 } == 1)
        #expect(model.report?.androidDevices.first?.activity.state == .observedUse)
        #expect(model.report?.androidDevices.first?.activity.processIDs == [901])
        #expect(model.report?.androidDevices.first?.lastUsedAt == nil)
    }

    @Test("Stop during activity preparation does not strand scanning or start a later resource scan")
    func stopDuringObservation() async throws {
        let suite = "Room-DeveloperStop-" + UUID().uuidString
        let root = URL(fileURLWithPath: "/private/tmp/" + suite, isDirectory: true)
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(root)
        let folder = try #require(access.folders.first)
        let gate = DeferredDeveloperObservation()
        let scans = Mutex(0)
        let model = RoomDeveloperModel(access: access, defaults: defaults, scanner: { _, _ in
            scans.withLock { $0 += 1 }
            return DeveloperResourcesReport(id: UUID(), scannedAt: Date(), androidDevices: [], gradleResources: [],
                projectWrappers: [], issues: [], cancelled: false, isPartial: false)
        }, activitySampler: { await gate.sample() })
        model.attach(role: .project, to: folder.id)
        model.scan()
        for _ in 0..<1000 { if await gate.started { break }; await Task.yield() }
        #expect(await gate.started)
        model.stop()
        await gate.finish()
        for _ in 0..<1000 where model.isScanning { await Task.yield() }
        #expect(!model.isScanning)
        #expect(scans.withLock { $0 } == 0)
        #expect(model.report == nil)
    }
}
private actor DeferredDeveloperObservation {
    private(set) var started = false
    private var continuation: CheckedContinuation<DeveloperActivitySnapshot, Never>?
    func sample() async -> DeveloperActivitySnapshot {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: .unknown); continuation = nil }
}
