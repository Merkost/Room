import Darwin
import Foundation
import Testing
@testable import RoomCore

@Suite("Caches found by their shape", .serialized)
struct SmartCatalogueTests {
    @Test func anElectronAppGivesUpOnlyItsRenderingCaches() throws {
        let home = try SmartHome()
        defer { home.remove() }
        let app = "Library/Application Support/Linear/"
        for name in ["Preferences", "Network Persistent State"] { try home.file(app + name) }
        for name in ["Cache/data_0", "Code Cache/js/x", "GPUCache/data_1", "IndexedDB/db", "Local Storage/leveldb/x",
                     "Service Worker/CacheStorage/x", "Partitions/work/Preferences", "Partitions/work/Code Cache/x",
                     "Partitions/work/Network Persistent State"] {
            try home.file(app + name)
        }
        try home.file("Library/Application Support/Notes/Preferences")   // no network state or cache: not Chromium
        try home.file("Library/Application Support/Notes/Cache/x")
        let roots = home.smart().roots.filter { $0.id.hasPrefix("app:") }
        #expect(Set(roots.map(\.subtitle)) == [app + "Cache", app + "Code Cache", app + "GPUCache", app + "Partitions/work/Code Cache"])
        #expect(roots.allSatisfy { $0.title == "Linear" && $0.guardedProcesses == ["linear"] })
        #expect(roots.allSatisfy { $0.runningLock?.path == home.url.appendingPathComponent(app + "SingletonLock").path })
    }

    @Test func anInstalledAppLendsItsRealName() throws {
        let home = try SmartHome()
        defer { home.remove() }
        for name in ["Preferences", "Network Persistent State", "Cache/x"] {
            try home.file("Library/Application Support/YandexMusic/" + name)
        }
        let root = try #require(home.smart(apps: ["Yandex Music", "Safari"]).roots.first { $0.id.hasPrefix("app:") })
        #expect(root.title == "Yandex Music")
        #expect(root.guardedProcesses.contains("yandex music") && root.guardedProcesses.contains("yandexmusic"))
    }

    @Test func appsTheCatalogueAlreadyNamesKeepTheirRows() throws {
        let home = try SmartHome()
        defer { home.remove() }
        for name in ["Preferences", "Network Persistent State", "Cache/x", "GPUCache/x"] {
            try home.file("Library/Application Support/Slack/" + name)
        }
        let known = CacheRoot(id: "slack-http-render-cache", title: "Slack", subtitle: "", symbol: "app", category: "apps",
            url: home.url.appendingPathComponent("Library/Application Support/Slack/Cache"), consequence: "")
        let roots = home.smart(roots: [known]).roots
        #expect(!roots.contains { $0.id.hasPrefix("app:") })
    }

    @Test func downloadedUpdatesAreFoundAndNamedForTheirApp() throws {
        let home = try SmartHome()
        defer { home.remove() }
        try home.file("Library/Caches/com.linear.ShipIt/update.zip")
        try home.file("Library/Caches/@lineardesktop-updater/pending/Linear.zip")
        try home.file("Library/Caches/com.anthropic.claudefordesktop.ShipIt/update.zip")
        try home.file("Library/Caches/com.example.Notes/data")
        let roots = home.smart().roots.filter { $0.id.hasPrefix("update-") }
        #expect(Set(roots.map(\.title)) == ["Linear update", "Claude update"])
        #expect(roots.count == 3)
        #expect(roots.first { $0.subtitle.hasSuffix("claudefordesktop.ShipIt") }?.guardedProcesses.contains("claude") == true)
    }

    @Test func xcodeDeviceSupportKeepsAMonthOfVersions() throws {
        let home = try SmartHome()
        defer { home.remove() }
        try home.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone 17.0 (21A329)/Symbols/x")
        let root = try #require(home.smart().roots.first { $0.id == "xcode-device-support-ios" })
        #expect(root.minimumAge == 30 * 86_400)
        #expect(root.guardedProcesses.contains("xcode"))
    }

    @Test func aHeldLockMeansTheAppIsOpenAndACrashedOneDoesNot() throws {
        let home = try SmartHome()
        defer { home.remove() }
        let held = home.url.appendingPathComponent("held")
        try FileManager.default.createSymbolicLink(atPath: held.path, withDestinationPath: "My-Mac.local-\(getpid())")
        let stale = home.url.appendingPathComponent("stale")
        try FileManager.default.createSymbolicLink(atPath: stale.path, withDestinationPath: "My-Mac.local-999999")
        #expect(CacheEngine.lockIsHeld(held))
        #expect(!CacheEngine.lockIsHeld(stale))
        #expect(!CacheEngine.lockIsHeld(home.url.appendingPathComponent("missing")))
    }

    @Test func anOpenAppsCacheCannotBeTicked() async throws {
        let home = try SmartHome()
        defer { home.remove() }
        try home.file("cache/old")
        let old = Date(timeIntervalSinceNow: -30 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home.url.appendingPathComponent("cache/old").path)
        let lock = home.url.appendingPathComponent("SingletonLock")
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "My-Mac.local-\(getpid())")
        let root = CacheRoot(id: "app:x:y", title: "Linear", subtitle: "", symbol: "app", category: "apps",
            url: home.url.appendingPathComponent("cache"), consequence: "Test", guardedProcesses: ["linear"], runningLock: lock)
        let engine = CacheEngine(configuration: CacheConfiguration(roots: [root], homeDirectory: home.url),
                                 activityDirectory: home.url.appendingPathComponent("activity"), processProvider: { [] })
        let open = try #require(await engine.scan().groups.first?.entries.first)
        #expect(open.eligibility.isInUse)
        try FileManager.default.removeItem(at: lock)
        let closed = try #require(await engine.scan().groups.first?.entries.first)
        #expect(closed.eligibility.isEligible)
    }

    @Test func folderNamesReadAsWords() {
        #expect(CacheConfiguration.readable("YandexMusic") == "Yandex Music")
        #expect(CacheConfiguration.readable("appium-inspector") == "Appium Inspector")
        #expect(CacheConfiguration.readable("1Password") == "1Password")
        #expect(CacheConfiguration.readable("Linear") == "Linear")
    }

    @Test func updateOwnersReadAsAppNames() {
        #expect(CacheConfiguration.updateOwner("com.linear.ShipIt").title == "Linear update")
        #expect(CacheConfiguration.updateOwner("@lineardesktop-updater").title == "Linear update")
        #expect(CacheConfiguration.updateOwner("apidog-updater").title == "Apidog update")
        #expect(CacheConfiguration.updateOwner("com.anthropic.claudefordesktop.ShipIt").title == "Claude update")
    }

    private struct SmartHome {
        let url: URL
        init() throws {
            url = URL(fileURLWithPath: "/private/tmp/RoomSmart-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        func file(_ path: String) throws {
            let file = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: file)
        }
        func smart(roots: [CacheRoot] = [], apps: [String] = []) -> CacheConfiguration {
            CacheConfiguration.addingSmartSources(to: CacheConfiguration(roots: roots, homeDirectory: url), installedApps: apps)
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }
}
