import Foundation
import Testing
@testable import RoomCore

@Suite("Deterministic storage review")
struct StorageAnalysisTests {
    @Test("Organization labels use strict cache and agent path components")
    func categories() {
        let pairs: [(String, StorageCategory)] = [
            ("/Users/test/.codex/cache", .cachesBuilds),
            ("/Users/test/.codex/cache/model.bin", .cachesBuilds),
            ("/Users/test/.codex/cache-other/model.bin", .agents),
            ("/Users/test/.claude/projects/session.bin", .agents),
            ("/Users/test/Library/Caches", .cachesBuilds),
            ("/Users/test/project/build/output.bin", .cachesBuilds),
            ("/Users/test/project/rebuild/output.bin", .systemOther),
            ("/Applications/Editor.app/Contents/data.zip", .applications),
            ("/Users/test/archive.zip", .archives),
            ("/Users/test/photo.heic", .media),
            ("/Users/test/source.swift", .documents)
        ]
        for (path, category) in pairs { #expect(StorageClassification.category(for: URL(fileURLWithPath: path)) == category) }
        #expect(StorageClassification.isHiddenPath(URL(fileURLWithPath: "/Users/test/.codex/session.bin")))
        #expect(!StorageClassification.isHiddenPath(URL(fileURLWithPath: "/Users/test/codex/session.bin")))
    }

    @Test("Explicit protected locations outrank nested cache names")
    func protectedLocations() throws {
        let fixture = AnalysisFixture()
        let configuration = CacheConfiguration(roots: [fixture.root(".codex/cache")], protectedLocations: [
            ProtectedLocation(id: "sessions", title: "Sessions", url: fixture.url(".codex/sessions"), reason: "Conversation history stays protected.")
        ], homeDirectory: fixture.home)
        let report = StorageAnalyzer.analyze(report: fixture.report([
            fixture.item(".codex/sessions/build/cache.bin"), fixture.item(".codex/cache/model.bin"),
            fixture.item(".codex/cache-other/model.bin")
        ]), configuration: configuration)
        #expect(report.source == .ruleBased)
        #expect(report.findings.count == 3)
        let protected = try #require(report.findings.first { $0.item.url.path.contains("/sessions/") })
        #expect(protected.disposition == .protected)
        #expect(protected.reason == "Conversation history stays protected.")
        #expect(report.findings.first { $0.item.url.path.contains("/cache/") }?.disposition == .cache)
        #expect(report.findings.first { $0.item.url.path.contains("/cache-other/") }?.disposition == .protected)
    }

    @Test("Credentials, persistent app data, histories, databases, tools and work stay protected")
    func persistentAndSensitiveData() {
        let fixture = AnalysisFixture()
        let paths = [".ssh/private.bin", ".aws/config", ".codex/sessions/conversation.bin", ".claude/projects/history.bin",
                     "Library/Application Support/App/cache-looking.bin", "Library/Keychains/login.keychain-db",
                     "Documents/project/source.swift", "Downloads/report.pdf", "Downloads/database.sqlite",
                     "Downloads/.env.production", "Downloads/credentials.json", ".rustup/toolchains/compiler.bin",
                     "Downloads/Editor.app/Contents/cache.bin", "Photos.photoslibrary/database.bin", ".git/objects/abc"]
        let report = StorageAnalyzer.analyze(report: fixture.report(paths.map { fixture.item($0) }), configuration: fixture.configuration)
        #expect(report.findings.count == paths.count)
        #expect(report.findings.allSatisfy { $0.disposition == .protected && $0.source == .ruleBased })
        #expect(report.findings.allSatisfy { !$0.reason.isEmpty })
    }

    @Test("Name, extension, age, hidden state and cache-like categories never create cleanup eligibility")
    func namesAreNotEligibility() {
        let fixture = AnalysisFixture()
        let items = [fixture.item("Downloads/old.zip"), fixture.item("Downloads/.mystery.bin"),
                     fixture.item("project/build/generated.bin"), fixture.item("Downloads/cache.bin")]
        let report = StorageAnalyzer.analyze(report: fixture.report(items), configuration: fixture.configuration)
        #expect(report.findings.allSatisfy { $0.disposition == .review })
        #expect(report.findings.first { $0.item.name == "generated.bin" }?.category == .cachesBuilds)
        #expect(report.summary.contains("never establish"))
        #expect(!report.availability.isAvailable)
    }

    @Test("Cache labels require the exact single file or a strict child boundary")
    func cacheBoundaries() {
        let fixture = AnalysisFixture()
        let configuration = CacheConfiguration(roots: [fixture.root("Library/Caches/Tool"), fixture.root(".claude/cache/changelog.md", scope: .singleFile)], homeDirectory: fixture.home)
        let paths = ["Library/Caches/Tool/data.bin", "Library/Caches/Tool-other/data.bin",
                     ".claude/cache/changelog.md", ".claude/cache/changelog.md/child.bin", "Library/Caches/Tool/auth.json"]
        let report = StorageAnalyzer.analyze(report: fixture.report(paths.map { fixture.item($0) }), configuration: configuration)
        for finding in report.findings {
            let expected: StorageDisposition = finding.item.url.path == fixture.url(paths[0]).path || finding.item.url.path == fixture.url(paths[2]).path ? .cache : .protected
            #expect(finding.disposition == expected)
        }
    }
}

struct AnalysisFixture: Sendable {
    let home = URL(fileURLWithPath: "/private/tmp/RoomAnalysis-\(UUID().uuidString)", isDirectory: true)
    var configuration: CacheConfiguration { CacheConfiguration(roots: [], homeDirectory: home) }
    func url(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: false) }
    func item(_ path: String, allocated: Int64 = 4_096) -> DiskMapItem {
        DiskMapItem(url: url(path), name: url(path).lastPathComponent, isDirectory: false,
            allocatedBytes: allocated, logicalBytes: allocated, fileCount: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_000_000))
    }
    func root(_ path: String, scope: CacheScope = .children) -> CacheRoot {
        CacheRoot(id: path, title: "Fixture cache", subtitle: "", symbol: "folder", category: "developer",
            url: url(path), consequence: "Test", scope: scope)
    }
    func report(_ items: [DiskMapItem]) -> DiskMapReport {
        DiskMapReport(id: UUID(), url: home, scannedAt: Date(), children: [], largestFiles: items,
            allocatedBytes: items.reduce(0) { $0 + $1.allocatedBytes }, logicalBytes: items.reduce(0) { $0 + $1.logicalBytes },
            fileCount: items.count, issues: [], cancelled: false, isPartial: false)
    }
}
