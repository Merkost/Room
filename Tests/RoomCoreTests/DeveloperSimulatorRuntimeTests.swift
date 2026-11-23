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

    @Test func exportedBundleMeasuresItsBackingImageFromAnApprovedFolderOrPackage() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let name = "Exports/iphonesimulator_27.2_24B8117.exportedBundle"
        let bundle = try fixture.directory(name)
        let root = bundle.deletingLastPathComponent()
        _ = try fixture.exportMetadata(in: name)
        let image = try fixture.write(name + "/Restore/141-80522-035.dmg", byteCount: 32_768)
        _ = try fixture.write(name + "/Restore/Firmware/unrelated.dmg", byteCount: 16_384)
        let engine = DeveloperResourcesEngine()
        let direct = await engine.scan(request: .init(
            approvedFolders: [bundle], simulatorRuntimeRoots: [bundle], scope: .toolStorage))
        let listed = await engine.scan(request: .init(
            approvedFolders: [root, bundle], simulatorRuntimeRoots: [root, bundle], scope: .toolStorage))

        #expect(direct.storageResources == listed.storageResources)
        let resource = try #require(direct.storageResources.first)
        #expect(direct.storageResources.count == 1 && !direct.isPartial && !listed.isPartial)
        #expect(resource.url.path == image.path)
        #expect(resource.kind == .simulatorRuntimeImage)
        #expect(resource.runtime?.name == "iOS 27.2" && resource.runtime?.build == "24B8117")
        #expect(resource.allocatedBytes == (try fixture.allocatedBytes(of: image)))
    }

    @Test func exportedBundleRejectsLinkedMetadataAndLinkedRestoreFolders() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let externalMetadata = try fixture.exportMetadata(in: "Outside")
        let externalImage = try fixture.write("Outside/Restore/other.dmg", byteCount: 32_768)
        let linkedMetadata = try fixture.directory("Exports/Metadata.exportedBundle")
        try FileManager.default.createSymbolicLink(at: linkedMetadata.appendingPathComponent("ExportedMetadata.plist"),
                                                    withDestinationURL: externalMetadata)
        _ = try fixture.write("Exports/Metadata.exportedBundle/Restore/available.dmg", byteCount: 16_384)
        let linkedPayload = try fixture.directory("Exports/Payload.exportedBundle")
        _ = try fixture.exportMetadata(in: "Exports/Payload.exportedBundle")
        try FileManager.default.createSymbolicLink(at: linkedPayload.appendingPathComponent("Restore"),
                                                    withDestinationURL: externalImage.deletingLastPathComponent())
        let root = linkedMetadata.deletingLastPathComponent()
        let report = await DeveloperResourcesEngine().scan(request: .init(
            approvedFolders: [root], simulatorRuntimeRoots: [root], scope: .toolStorage))

        #expect(report.storageResources.isEmpty && report.isPartial)
        #expect(Set(report.issues.map(\.url.path)) == [linkedMetadata.path, linkedPayload.path])
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

    func exportMetadata(in name: String) throws -> URL {
        try plist(["CFBundleIdentifier": "com.apple.MobileAsset.iOSSimulatorRuntime",
                   "MobileAssetProperties": ["SimulatorVersion": "27.2", "Build": "24B8117"]],
                  at: name + "/ExportedMetadata.plist")
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
