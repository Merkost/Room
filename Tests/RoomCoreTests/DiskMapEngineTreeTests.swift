import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Retained Disk Map scan")
struct DiskMapEngineTreeTests {
    @Test func scanTreeMatchesScanTotals() async throws {
        try await withTreeFixture { root in
            let engine = DiskMapEngine()
            let plain = await engine.scan(url: root)
            let retained = await engine.scanTree(url: root)
            #expect(retained.report.allocatedBytes == plain.allocatedBytes)
            #expect(retained.tree.allocatedBytes == plain.allocatedBytes)
            #expect(retained.tree.fileCount == plain.fileCount)
            #expect(retained.tree.descendant(at: "Projects/app/sources")?.isDirectory == true)
        }
    }

    @Test func kindTotalsAreExclusiveSums() async throws {
        try await withTreeFixture { root in
            let map = await DiskMapEngine().scanTree(url: root)
            #expect(map.report.kindAllocatedBytes.values.reduce(0, +) == map.report.allocatedBytes)
            #expect(map.tree.kindBytes == Dictionary(uniqueKeysWithValues: map.report.kindAllocatedBytes.map {
                ($0.key.rawValue, $0.value)
            }))
            #expect(map.tree.kindBytes[StorageKind.hidden.rawValue] ?? 0 > 0)
            #expect(map.tree.kindBytes[StorageKind.developer.rawValue] ?? 0 > 0)
        }
    }

    @Test func completedTopLevelOncePerChild() async throws {
        try await withTreeFixture { root in
            let progress = Mutex<[DiskScanProgress]>([])
            _ = await DiskMapEngine(progressInterval: 0).scanTree(url: root) { update in
                progress.withLock { $0.append(update) }
            }
            let events = progress.withLock { $0 }
            let completed = events.flatMap(\.completedTopLevel)
            #expect(completed.count == 3)
            #expect(Set(completed.map(\.name)) == ["Projects", ".git", ".gradle"])
            #expect(events.compactMap(\.topLevelTotal).last == 3)
        }
    }

    @Test func containersAreSkippedAndListed() async throws {
        try await withTreeFixture { root in
            let directory = root.appendingPathComponent("Library/Containers/private")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 4, count: 8192).write(to: directory.appendingPathComponent("data"))
            let skipped = await DiskMapEngine().scanTree(url: root)
            #expect(skipped.report.isPartial && skipped.tree.isPartial)
            #expect(skipped.report.issues.contains { $0.url.lastPathComponent == "Containers" })
            #expect(skipped.tree.descendant(at: "Library/Containers")?.allocatedBytes == 0)
            #expect(skipped.tree.descendant(at: "Library/Containers")?.isPartial == true)
            #expect(skipped.report.fileCount == 3)
        }
    }

    @Test func cancelledTreeIsPartial() async throws {
        try await withTreeFixture { root in
            let task = Task {
                while !Task.isCancelled { await Task.yield() }
                return await DiskMapEngine().scanTree(url: root)
            }
            task.cancel()
            let map = await task.value
            #expect(map.report.cancelled)
            #expect(map.tree.isPartial)
        }
    }

    private func withTreeFixture(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp/RoomTree-\(UUID().uuidString)", isDirectory: true)
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        for path in [".git/config", ".gradle/caches/artifact", "Projects/app/sources/file.swift"] {
            let url = root.appendingPathComponent(path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: 8192).write(to: url)
        }
        try await body(root)
    }
}
