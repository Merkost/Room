import Darwin
import Foundation
import Testing
@testable import RoomCore

@Suite("Approved Simulator runtime storage")
struct DeveloperSimulatorRuntimeTests {
    @Test func runtimeBundlesAndSimulatorDeviceDataHaveDistinctRows() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let runtimes = try fixture.directory("Runtimes")
        let standalone = try fixture.runtime("Runtimes/iOS 26.0.simruntime", withRuntimeRoot: true)
        let alias = try fixture.runtime("Runtimes/Mounted iOS.simruntime", withRuntimeRoot: false)
        let devices = try fixture.directory("Devices")
        _ = try fixture.plist([:], at: "Devices/device_set.plist")
        _ = try fixture.write("Devices/synthetic-device/data/build.bin", byteCount: 16_384)

        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [runtimes, devices], simulatorDeviceRoots: [devices],
            simulatorRuntimeRoots: [runtimes], scope: .toolStorage))

        #expect(Set(report.storageResources.map(\.kind)) == [.simulatorDevices, .simulatorRuntimeBundle])
        let bundle = try #require(report.storageResources.first { $0.kind == .simulatorRuntimeBundle })
        #expect(bundle.url.path == standalone.path)
        #expect(bundle.runtime?.name == "iOS 26.0")
        #expect(bundle.allocatedBytes > 0 && !bundle.isPartial)
        #expect(report.storageResources.allSatisfy { $0.url.path != alias.path })
    }

    @Test func mobileAssetCountsBackingImageOnceAndRejectsLinkedOrUnrelatedPayloads() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let asset = try fixture.directory("Runtime Assets/one.asset")
        let root = asset.deletingLastPathComponent()
        _ = try fixture.plist([
            "CFBundleIdentifier": "com.apple.MobileAsset.iOSSimulatorRuntime",
            "MobileAssetProperties": ["SimulatorVersion": "27.2", "Build": "24B8117"],
        ], at: "Runtime Assets/one.asset/Info.plist")
        let image = try fixture.write("Runtime Assets/one.asset/AssetData/Restore/141-00000-001.dmg", byteCount: 49_152)
        let outside = try fixture.write("Outside/Other.dmg", byteCount: 65_536)
        try FileManager.default.createSymbolicLink(at: image.deletingLastPathComponent().appendingPathComponent("outside.dmg"),
                                                    withDestinationURL: outside)
        _ = try fixture.write("Runtime Assets/unrelated.asset/AssetData/Restore/unrelated.dmg", byteCount: 16_384)
        _ = try fixture.plist(["CFBundleIdentifier": "com.example.OtherAsset"], at: "Runtime Assets/unrelated.asset/Info.plist")

        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [root, asset], simulatorRuntimeRoots: [root, asset], scope: .toolStorage))

        let payload = try #require(report.storageResources.first)
        #expect(report.storageResources.count == 1)
        #expect(payload.kind == .simulatorRuntimeImage)
        #expect(payload.url.path == image.path)
        #expect(payload.runtime?.name == "iOS 27.2")
        #expect(payload.runtime?.build == "24B8117")
        #expect(payload.allocatedBytes == (try fixture.allocatedBytes(of: image)))
    }

    @Test func catalogueOnlyLabelsImagesInsideAnExactlyApprovedRoot() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let root = try fixture.directory("Images")
        let image = try fixture.write("Images/ABCDE.dmg", byteCount: 16_384)
        let loose = try fixture.write("Images/visionOS 3.0 Simulator Runtime.dmg", byteCount: 16_384)
        let handle = try FileHandle(forWritingTo: loose)
        try handle.seek(toOffset: 16_384 - 512)
        try handle.write(contentsOf: Data("koly".utf8))
        try handle.close()
        _ = try fixture.write("Images/iOS 26.0 Simulator Runtime.dmg", byteCount: 16_384)
        _ = try fixture.write("Images/Unrelated installer.dmg", byteCount: 16_384)
        let outside = try fixture.write("Outside/Unapproved.dmg", byteCount: 65_536)
        let files = [image, outside]
        _ = try fixture.plist(["images": files.map { [
            "path": ["relative": $0.absoluteString],
            "runtimeInfo": ["bundleIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "build": "23A100"],
        ] }], at: "Images/images.plist")
        let engine = DeveloperResourcesEngine()
        let denied = await engine.scan(request: .init(
            approvedFolders: [fixture.url], simulatorRuntimeRoots: [root], scope: .toolStorage))
        #expect(denied.storageResources.isEmpty && denied.isPartial)

        let report = await engine.scan(request: .init(
            approvedFolders: [root], simulatorRuntimeRoots: [root], scope: .toolStorage))
        #expect(Set(report.storageResources.map(\.url.path)) == [image.path, loose.path])
        let tracked = try #require(report.storageResources.first { $0.url.path == image.path })
        #expect(tracked.runtime?.name == "iOS 26.0")
        #expect(tracked.runtime?.build == "23A100")
        let devices = await engine.scan(request: .init(
            approvedFolders: [root], simulatorRuntimeRoots: [root], scope: .devices))
        #expect(devices.storageResources.isEmpty && devices.simulatorDevices.isEmpty)
    }

    @Test func malformedBundleMetadataIsPartialAndDoesNotMeasureTheDirectory() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let root = try fixture.directory("Runtimes")
        _ = try fixture.directory("Runtimes/Broken.simruntime/Contents/RuntimeRoot")
        _ = try fixture.write("Runtimes/Broken.simruntime/Contents/Info.plist", byteCount: 70_000)
        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [root], simulatorRuntimeRoots: [root], scope: .toolStorage))
        #expect(report.storageResources.isEmpty && report.isPartial)
    }
}

private struct RuntimeFixture {
    let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("RoomRuntime-" + UUID().uuidString, isDirectory: true)

    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }

    func directory(_ name: String) throws -> URL {
        let directory = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func write(_ name: String, byteCount: Int) throws -> URL {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: byteCount).write(to: file)
        return file
    }

    func plist(_ fields: [String: Any], at name: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0).write(to: file)
        return file
    }

    func runtime(_ name: String, withRuntimeRoot: Bool) throws -> URL {
        _ = try plist(["CFBundleIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                       "CFBundleName": "iOS 26.0", "CFBundleShortVersionString": "400"], at: name + "/Contents/Info.plist")
        if withRuntimeRoot { _ = try write(name + "/Contents/Resources/RuntimeRoot/System/sample.bin", byteCount: 65_536) }
        return url.appendingPathComponent(name, isDirectory: true)
    }

    func allocatedBytes(of url: URL) throws -> Int64 {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else { throw CocoaError(.fileNoSuchFile) }
        return Int64(metadata.st_blocks) * 512
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
