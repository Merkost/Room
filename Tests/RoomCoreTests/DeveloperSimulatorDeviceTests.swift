import Foundation
import Testing
@testable import RoomCore

@Suite("Approved Simulator device inventory")
struct DeveloperSimulatorDeviceTests {
    @Test func devicesIncludeAndroidAndOnlyMeasureApprovedSimulatorDevices() async throws {
        let fixture = try SimulatorFixture()
        defer { fixture.remove() }
        let device = try fixture.device(in: "Devices", name: "Sample iPhone")
        let other = try fixture.device(in: "OtherDevices", name: "Unapproved")
        let android = fixture.url.appendingPathComponent("AVDs", isDirectory: true)
        try FileManager.default.createDirectory(at: android.appendingPathComponent("sample.avd"), withIntermediateDirectories: true)
        let runtimes = fixture.url.appendingPathComponent("Runtimes", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimes, withIntermediateDirectories: true)

        let result = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [fixture.url, device.deletingLastPathComponent(), android, runtimes], avdRoots: [android],
            simulatorDeviceRoots: [device.deletingLastPathComponent(), device.deletingLastPathComponent(),
                                   other.deletingLastPathComponent(), runtimes], scope: .devices))

        let item = try #require(result.simulatorDevices.first)
        #expect(result.simulatorDevices.count == 1)
        #expect(item.url.path == device.path)
        #expect(item.displayName == "Sample iPhone")
        #expect(item.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
        #expect(item.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-17")
        #expect(item.allocatedBytes > 0 && !item.isPartial)
        #expect(result.androidDevices.count == 1)
        #expect(result.storageResources.isEmpty && result.toolchains.isEmpty && result.aiStorageResources.isEmpty)
        #expect(result.issues.contains { $0.url.path == other.deletingLastPathComponent().path })
        #expect(result.issues.contains { $0.url.path == runtimes.path })

        let storage = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [device.deletingLastPathComponent()], simulatorDeviceRoots: [device.deletingLastPathComponent()],
            scope: .toolStorage))
        #expect(storage.simulatorDevices.isEmpty && storage.androidDevices.isEmpty)
        #expect(storage.storageResources.map(\.kind) == [.simulatorDevices])
    }

    @Test func deviceSizesSkipExternalLinksAndInvalidMetadata() async throws {
        let fixture = try SimulatorFixture()
        defer { fixture.remove() }
        let device = try fixture.device(in: "Devices", name: "Sample iPhone")
        let devices = device.deletingLastPathComponent()
        let external = try fixture.device(in: "External", name: "External iPhone")
        let engine = DeveloperResourcesEngine()
        let request = DeveloperResourcesRequest(approvedFolders: [devices], simulatorDeviceRoots: [devices], scope: .devices)
        let original = await engine.scan(request: request)
        let size = try #require(original.simulatorDevices.first?.allocatedBytes)

        let invalid = devices.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: invalid.appendingPathComponent("device.plist"),
                                                    withDestinationURL: external.appendingPathComponent("device.plist"))
        try FileManager.default.createSymbolicLink(at: device.appendingPathComponent("linked-data"),
                                                    withDestinationURL: external)

        let result = await engine.scan(request: request)
        #expect(result.simulatorDevices.count == 1)
        #expect(result.simulatorDevices.first?.allocatedBytes == size)
        #expect(result.simulatorDevices.first?.isPartial == true)
        #expect(result.isPartial)
    }

    @Test func olderReportsDecodeWithoutDeviceInventory() async throws {
        let result = await DeveloperResourcesEngine().scan(request: .init(approvedFolders: []))
        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        stored.removeValue(forKey: "simulatorDevices")
        let decoded = try JSONDecoder().decode(DeveloperResourcesReport.self,
            from: JSONSerialization.data(withJSONObject: stored))
        #expect(decoded.simulatorDevices.isEmpty)
    }
}

private struct SimulatorFixture {
    let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("RoomSimulator-" + UUID().uuidString, isDirectory: true)

    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }

    func device(in deviceSet: String, name: String) throws -> URL {
        let id = UUID().uuidString
        let device = url.appendingPathComponent(deviceSet).appendingPathComponent(id, isDirectory: true)
        let data = device.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let fields = ["name": name, "UDID": id,
                      "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                      "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"]
        try PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)
            .write(to: device.appendingPathComponent("device.plist"))
        try Data(repeating: 1, count: 32_768).write(to: data.appendingPathComponent("sample.bin"))
        return device
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
