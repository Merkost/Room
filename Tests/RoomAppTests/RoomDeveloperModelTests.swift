import Foundation
import Testing
@testable import RoomApp

@Suite("Developer folder roles and unreferenced dates") @MainActor
struct RoomDeveloperModelTests {
    @Test func editionSpecificFolderSuggestions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let gradle = home.appendingPathComponent(".gradle", isDirectory: true)
        try FileManager.default.createDirectory(at: gradle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "RoomDeveloperModel-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = RoomFileAccess(defaults: defaults)
        let model = RoomDeveloperModel(access: access, defaults: defaults,
            unreferencedStore: RoomDeveloperUnreferencedStore(directory: home), home: home)
        #if ROOM_APP_STORE
        #expect(model.folderSuggestions.map(\.role) == [.android, .gradle, .sdk, .xcode, .konan, .simulators])
        #expect(RoomDeveloperSection.allCases.map(\.rawValue) == ["Rooms", "Matrix", "Devices", "Storage", "AI Tools"])
        #expect(RoomDeveloperView.suggestionAction == "Choose…")
        #else
        #expect(model.folderSuggestions.map(\.role) == [.gradle, .simulators])
        #expect(RoomDeveloperSection.allCases.map(\.rawValue) == ["Rooms", "Matrix", "Devices", "Storage", "AI Tools", "Worktrees"])
        #expect(RoomDeveloperView.suggestionAction == "Use")
        let gradleSuggestion = try #require(model.folderSuggestions.first)
        model.useSuggestion(gradleSuggestion)
        #expect(model.locations.map(\.role) == [.gradle])
        #expect(access.folders.count == 1)
        #endif
        let simulatorSuggestion = try #require(model.folderSuggestions.first { $0.role == .simulators })
        #expect(simulatorSuggestion.url == home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true))
        #expect(RoomDeveloperView.suggestionAction(for: .simulators) == "Choose…")
        #expect(!model.locations.contains { $0.role == .simulators })
        model.section = .aiTools
        #expect(model.folderSuggestions.map(\.role) == RoomDeveloperFolderRole.aiRoles)
        #expect(!model.canScan)
    }

    @Test func unreferencedDatesPersistAndOnlyCompleteScansChangeThem() throws {
        let key = "gradle:7.6.4-bin"
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        let now = first + 140 * 86_400
        let record = RoomDevUnreferenced().updated(orphanKeys: [key], referencedKeys: [], scanComplete: true, now: first)
        // DMR-C93 through DMR-C96.
        #expect(record.updated(orphanKeys: [], referencedKeys: [], scanComplete: false, now: now) == record)
        #expect(record.updated(orphanKeys: [key], referencedKeys: [], scanComplete: true, now: now).since[key] == first)
        #expect(record.updated(orphanKeys: [], referencedKeys: [key], scanComplete: true, now: now).since.isEmpty)
        #expect(RoomDevUnreferenced.caption(since: first, now: now, thresholdDays: 90) == "Not referenced for 4 months")
        #expect(RoomDevUnreferenced.caption(since: first, now: first + 59 * 86_400, thresholdDays: 90) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoomDeveloperUnreferencedStore(directory: directory)
        store.save(record)
        #expect(store.load() == record)
        let contents = try String(contentsOf: directory.appendingPathComponent("developer-unreferenced.json"), encoding: .utf8)
        #expect(!contents.contains(directory.path))
    }
}
