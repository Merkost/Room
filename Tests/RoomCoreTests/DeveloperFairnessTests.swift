import Foundation
import Testing
@testable import RoomCore

@Suite("Fair developer role coverage")
struct DeveloperFairnessTests {
    @Test("A large selected projects tree cannot spend the Android and Gradle budgets")
    func projectSearchDoesNotStarveResources() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Room-DeveloperFairness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        func file(_ path: String, _ content: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        for index in 0..<200 { try file("projects/project-\(index)/source.kt", "owned fixture") }
        try file("avds/Pixel.avd/config.ini", "target=android-35\nabi.type=arm64-v8a\n")
        try file("avds/Pixel.avd/userdata.img", "owned device")
        try file("gradle/caches/8.9/generated.bin", "owned cache")
        try file("gradle/wrapper/dists/gradle-8.9-bin/hash/gradle-8.9/readme.txt", "owned distribution")
        let result = await DeveloperResourcesEngine().scan(request: DeveloperResourcesRequest(approvedFolders: [root],
            avdRoots: [root.appendingPathComponent("avds")], gradleHomes: [root.appendingPathComponent("gradle")],
            projectRoots: [root.appendingPathComponent("projects")], limits: DeveloperResourcesLimits(maximumNodes: 90)))
        #expect(result.isPartial)
        #expect(result.androidDevices.map(\.name) == ["Pixel"])
        #expect(result.gradleResources.contains { $0.version == "8.9" })
        #expect(result.issues.contains { $0.message.contains("bounded scan") })
        #expect(result.androidDevices.first?.activity.state == .unknown)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("projects/project-199/source.kt").path))
    }

    #if ROOM_APP_STORE
    @Test("Store production activity remains unknown without executing cross-process tools")
    func storeObservationIsExplicitlyUnknown() async {
        let sample = await DeveloperResourcesEngine.activitySnapshot()
        #expect(sample.processes.isEmpty)
        #expect(!sample.isComplete)
    }
    #endif
}
