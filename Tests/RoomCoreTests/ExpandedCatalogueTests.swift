import Foundation
import Testing
@testable import RoomCore

@Suite("Deeper cache catalogue")
struct ExpandedCatalogueTests {
    @Test func deeperRulesNeverPromoteWholeAgentHomesOrRecoveryData() throws {
        let home = URL(fileURLWithPath: "/private/tmp/RoomCatalogue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let ide = home.appendingPathComponent("Library/Caches/Google/AndroidStudio2026.1.4", isDirectory: true)
        try FileManager.default.createDirectory(at: ide.appendingPathComponent("LocalHistory"), withIntermediateDirectories: true)
        let base = CacheConfiguration(roots: [], homeDirectory: home)
        let deeper = CacheConfiguration.addingDeepSources(to: base)
        let paths = deeper.roots.map { String($0.url.path.dropFirst(home.path.count + 1)) }
        #expect(paths.contains(".npm/_npx"))
        #expect(paths.contains(".claude/cache/model-catalog"))
        #expect(paths.contains("Library/Application Support/Cursor/Code Cache"))
        #expect(paths.contains("Library/Caches/Google/AndroidStudio2026.1.4/index"))
        #expect(!paths.contains("Library/Caches/Google/AndroidStudio2026.1.4"))
        #expect(!paths.contains(where: { $0.contains("LocalHistory") || $0.contains("IndexedDB") || $0.contains("Local Storage") }))
        #expect(!paths.contains(".codex/.tmp"))
        #expect(!paths.contains(".codex/packages"))
        #expect(!paths.contains(".codex/.chatgpt-projects"))
        #expect(!paths.contains(".cache/uv"))
        #expect(!paths.contains(".cursor"))
        #expect(!paths.contains(".gemini/tmp"))
        #expect(Set(deeper.roots.map(\.id)).count == deeper.roots.count)
        #expect(Set(deeper.roots.map { $0.url.path }).count == deeper.roots.count)
        #expect(deeper.protectedLocations.contains { $0.url.path.hasSuffix("/LocalHistory") })
        #expect(deeper.protectedLocations.contains { $0.url.path.hasSuffix("/.codex/packages") })
        #expect(deeper.roots.allSatisfy { !$0.guardedProcesses.isEmpty && $0.minimumAge >= 7 * 86_400 })
    }

    @Test func discoverySkipsLinkedIDEVersions() throws {
        let home = URL(fileURLWithPath: "/private/tmp/RoomCatalogue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)
        let outside = home.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("AndroidStudioLinked"), withDestinationURL: outside)
        let deeper = CacheConfiguration.addingDeepSources(to: CacheConfiguration(roots: [], homeDirectory: home))
        #expect(!deeper.roots.contains { $0.url.path.contains("AndroidStudioLinked") })
    }
}
