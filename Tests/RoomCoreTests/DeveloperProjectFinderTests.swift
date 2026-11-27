import Foundation
import Testing
@testable import RoomCore

@Suite("Developer project discovery")
struct DeveloperProjectFinderTests {
    @Test func findsGradleAndXcodeProjectsWithoutDescendingIntoThem() throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/alpha/settings.gradle.kts")
        try home.file("code/alpha/app/build.gradle.kts")
        try home.folder("Documents/work/beta/Beta.xcodeproj")
        try home.file("Desktop/gamma/gradle/wrapper/gradle-wrapper.properties")
        try home.file("code/notes/readme.md")
        let result = DeveloperProjectFinder.find(home: home.url)
        #expect(home.names(result.projects) == ["Desktop/gamma", "Documents/work/beta", "code/alpha"])
        #expect(!result.partial)
    }

    @Test func staysOutOfLibraryHiddenGeneratedAndLinkedFolders() throws {
        let home = try Home()
        defer { home.remove() }
        for path in ["Library/x/settings.gradle", ".hidden/x/settings.gradle", "code/node_modules/x/settings.gradle",
                     "code/build/x/settings.gradle", "Pictures/x/settings.gradle", "Thing.app/x/settings.gradle"] {
            try home.file(path)
        }
        try home.file("outside/real/settings.gradle")
        try FileManager.default.createSymbolicLink(at: home.url.appendingPathComponent("code/linked"),
            withDestinationURL: home.url.appendingPathComponent("outside"))
        #expect(home.names(DeveloperProjectFinder.find(home: home.url).projects) == ["outside/real"])
    }

    @Test func skippedFoldersAreNotRead() throws {
        let home = try Home()
        defer { home.remove() }
        try home.file("code/alpha/settings.gradle")
        try home.file("old/beta/settings.gradle")
        let result = DeveloperProjectFinder.find(home: home.url,
            excluding: [home.url.appendingPathComponent("old").path])
        #expect(home.names(result.projects) == ["code/alpha"])
    }

    @Test func manyProjectsCollapseToTheirParentFolders() throws {
        let home = try Home()
        defer { home.remove() }
        for index in 0..<6 { try home.file("code/p\(index)/settings.gradle") }
        try home.file("other/solo/settings.gradle")
        let result = DeveloperProjectFinder.find(home: home.url, limit: 3)
        #expect(home.names(result.projects) == ["code", "other/solo"])
    }

    @Test func collapsingNeverReopensASkippedFolder() throws {
        let home = try Home()
        defer { home.remove() }
        for index in 0..<6 { try home.file("code/p\(index)/settings.gradle") }
        try home.file("code/huge/settings.gradle")
        let result = DeveloperProjectFinder.find(home: home.url,
            excluding: [home.url.appendingPathComponent("code/huge").path], limit: 3)
        #expect(!home.names(result.projects).contains("code"))
        #expect(result.projects.count == 3 && result.partial)
    }

    @Test func aLimitedWalkSaysSo() throws {
        let home = try Home()
        defer { home.remove() }
        for index in 0..<10 { try home.file("code/p\(index)/settings.gradle") }
        #expect(DeveloperProjectFinder.find(home: home.url, maximumDirectories: 3).partial)
    }

    private struct Home {
        let url: URL
        init() throws {
            url = URL(fileURLWithPath: "/private/tmp/RoomFinder-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        func folder(_ path: String) throws {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        func file(_ path: String) throws {
            try folder((path as NSString).deletingLastPathComponent)
            try Data("x".utf8).write(to: url.appendingPathComponent(path))
        }
        func names(_ found: [URL]) -> [String] { found.map { String($0.path.dropFirst(url.path.count + 1)) } }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }
}
