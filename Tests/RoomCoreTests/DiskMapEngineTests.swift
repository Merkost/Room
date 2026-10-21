import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Read-only disk map", .serialized)
struct DiskMapEngineTests {
    @Test("Nested and hidden file totals match filesystem metadata")
    func nestedTotals() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        let first = try fixture.write("selected/folder/deep/a.bin", count: 11_000)
        let second = try fixture.write("selected/folder/b.bin", count: 5_000)
        let hidden = try fixture.write("selected/.hidden", count: 3_000)
        let top = try fixture.write("selected/top.bin", count: 8_000)
        _ = try fixture.directory("selected/empty")
        let files = [first, second, hidden, top]
        let expectedAllocation = try files.reduce(Int64(0)) { $0 + (try allocated($1)) }
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(!report.isPartial)
        #expect(!report.cancelled)
        #expect(report.issues.isEmpty)
        #expect(report.fileCount == 4)
        #expect(report.allocatedBytes == expectedAllocation)
        #expect(report.logicalBytes == 27_000)
        #expect(Set(report.children.map(\.name)) == ["folder", ".hidden", "top.bin", "empty"])
        let folder = try #require(report.children.first { $0.name == "folder" })
        #expect(folder.isDirectory)
        #expect(folder.fileCount == 2)
        #expect(folder.logicalBytes == 16_000)
        #expect(folder.allocatedBytes == (try allocated(first)) + (try allocated(second)))
        #expect(report.children.reduce(0) { $0 + $1.allocatedBytes } == report.allocatedBytes)
        #expect(report.children.reduce(0) { $0 + $1.logicalBytes } == report.logicalBytes)
        #expect(report.children.reduce(0) { $0 + $1.fileCount } == report.fileCount)
        #expect(Set(report.largestFiles.map(\.url)) == Set(files))
        #expect(try Data(contentsOf: first) == Data(repeating: 0x5A, count: 11_000))
    }

    @Test("An approved readable child can be scanned through an execute-only ancestor")
    func executeOnlyAncestor() async throws {
        let fixture = try DiskFixture()
        let parent = try fixture.directory("locked")
        let selected = try fixture.directory("locked/approved")
        let file = try fixture.write("locked/approved/visible.bin", count: 6_000)
        let expected = try allocated(file)
        defer { _ = chmod(parent.path, 0o700); fixture.remove() }
        #expect(chmod(parent.path, 0o111) == 0)
        let report = await DiskMapEngine().scan(url: selected)
        #expect(!report.isPartial)
        #expect(report.issues.isEmpty)
        #expect(report.fileCount == 1)
        #expect(report.logicalBytes == 6_000)
        #expect(report.allocatedBytes == expected)
        #expect(report.children.map(\.name) == ["visible.bin"])
    }

    @Test("Only the largest hundred file allocations are retained")
    func largestFilesAreBounded() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        var expected: [(url: URL, allocation: Int64, logical: Int64)] = []
        for index in 0..<120 {
            let count = (index + 1) * 128
            let file = try fixture.write("selected/folder/file-\(index).bin", count: count)
            expected.append((file, try allocated(file), Int64(count)))
        }
        expected.sort {
            if $0.allocation != $1.allocation { return $0.allocation > $1.allocation }
            if $0.logical != $1.logical { return $0.logical > $1.logical }
            return $0.url.path < $1.url.path
        }
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.fileCount == 120)
        #expect(report.children.count == 1)
        #expect(report.largestFiles.count == 100)
        #expect(report.largestFiles.map(\.url) == expected.prefix(100).map(\.url))
        #expect(report.largestFiles.allSatisfy { !$0.isDirectory })
    }

    @Test("Categories and hidden totals include every file beyond the retained top hundred")
    func completeClassification() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        for index in 0..<120 { _ = try fixture.write("selected/mixed/photo-\(index).jpg", count: 1_000) }
        let hidden = try fixture.write("selected/mixed/.nested/notes.md", count: 2_000)
        let archive = try fixture.write("selected/mixed/package.zip", count: 3_000)
        let build = try fixture.write("selected/build/output.bin", count: 4_000)
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.largestFiles.count == 100)
        #expect(report.categories.reduce(0) { $0 + $1.fileCount } == 123)
        #expect(report.categories.reduce(0) { $0 + $1.allocatedBytes } == report.allocatedBytes)
        #expect(report.categories.reduce(0) { $0 + $1.logicalBytes } == report.logicalBytes)
        #expect(report.categories.first { $0.category == .media }?.fileCount == 120)
        #expect(report.categories.first { $0.category == .documents }?.logicalBytes == 2_000)
        #expect(report.categories.first { $0.category == .archives }?.allocatedBytes == (try allocated(archive)))
        #expect(report.categories.first { $0.category == .cachesBuilds }?.allocatedBytes == (try allocated(build)))
        #expect(report.hiddenFileCount == 1)
        #expect(report.hiddenLogicalBytes == 2_000)
        #expect(report.hiddenAllocatedBytes == (try allocated(hidden)))
        let mixed = try #require(report.children.first { $0.name == "mixed" })
        #expect(mixed.categoryAllocatedBytes[.documents] == (try allocated(hidden)))
        #expect(mixed.categoryAllocatedBytes[.archives] == (try allocated(archive)))
        #expect(mixed.categoryAllocatedBytes.values.reduce(0, +) == mixed.allocatedBytes)
        #expect(mixed.hiddenAllocatedBytes == (try allocated(hidden)))
    }

    @Test("Hidden ancestors, macOS hidden flags and modification dates are preserved")
    func hiddenMetadata() async throws {
        let fixture = try DiskFixture()
        let flagged = try fixture.directory("selected/flagged")
        defer {
            _ = chflags(flagged.path, 0)
            fixture.remove()
        }
        let file = try fixture.write("selected/flagged/file.bin", count: 2_000)
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        #expect(chflags(flagged.path, UInt32(UF_HIDDEN)) == 0)
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.hiddenFileCount == 1)
        #expect(report.hiddenLogicalBytes == 2_000)
        #expect(report.largestFiles.first?.isHidden == true)
        #expect(report.largestFiles.first?.modifiedAt == date)
        #expect(report.children.first?.isHidden == true)
        let dotRoot = try fixture.directory(".codex")
        _ = try fixture.write(".codex/session.bin", count: 3_000)
        let hiddenRootReport = await DiskMapEngine().scan(url: dotRoot)
        #expect(hiddenRootReport.hiddenFileCount == hiddenRootReport.fileCount)
        #expect(hiddenRootReport.hiddenAllocatedBytes == hiddenRootReport.allocatedBytes)
        #expect(hiddenRootReport.largestFiles.first?.category == .agents)
    }

    @Test("Hardlink category accounting attributes allocations once across categories")
    func hardlinkCategoryTotals() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        let file = try fixture.write("selected/photo.jpg", count: 5_000)
        let link = fixture.selected.appendingPathComponent(".copy.zip", isDirectory: false)
        try FileManager.default.linkItem(at: file, to: link)
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.categories.reduce(0) { $0 + $1.allocatedBytes } == (try allocated(file)))
        #expect(report.categories.reduce(0) { $0 + $1.fileCount } == 2)
        #expect(report.categories.first { $0.category == .media }?.fileCount == 1)
        #expect(report.categories.first { $0.category == .archives }?.fileCount == 1)
        #expect(report.hiddenFileCount == 1)
        #expect(report.hiddenLogicalBytes == 5_000)
        #expect(report.children.reduce(0) { $0 + $1.hiddenAllocatedBytes } == report.hiddenAllocatedBytes)
    }

    @Test("Symbolic link targets outside the selected folder are never measured")
    func symbolicLinksAreSkipped() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        let local = try fixture.write("selected/real.bin", count: 4_000)
        let outside = try fixture.write("outside/large.bin", count: 80_000)
        _ = try fixture.directory("selected/nested")
        try FileManager.default.createSymbolicLink(at: fixture.selected.appendingPathComponent("linked-file"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: fixture.selected.appendingPathComponent("nested/linked-folder"),
            withDestinationURL: outside.deletingLastPathComponent())
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.isPartial)
        #expect(report.fileCount == 1)
        #expect(report.logicalBytes == 4_000)
        #expect(report.allocatedBytes == (try allocated(local)))
        #expect(report.largestFiles.map(\.url) == [local])
        #expect(report.issues.filter { $0.message.contains("symbolic links") }.count == 1)
        #expect(report.children.first { $0.name == "linked-file" }?.allocatedBytes == 0)
        #expect(try Data(contentsOf: outside).count == 80_000)
    }

    @Test("A selected symbolic link root and non-folder URLs are rejected")
    func invalidRoots() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        let outside = try fixture.write("outside/large.bin", count: 80_000)
        let link = fixture.base.appendingPathComponent("selected-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.deletingLastPathComponent())
        let engine = DiskMapEngine()
        let linked = await engine.scan(url: link)
        #expect(linked.isPartial)
        #expect(linked.children.isEmpty)
        #expect(linked.fileCount == 0)
        #expect(linked.issues.first?.message.contains("symbolic link") == true)
        let file = await engine.scan(url: outside)
        #expect(file.isPartial)
        #expect(file.fileCount == 0)
        let remote = await engine.scan(url: URL(string: "https://example.com/folder")!)
        #expect(remote.isPartial)
        #expect(remote.children.isEmpty)
        #expect(remote.allocatedBytes == 0)
    }

    @Test("Shared hardlinks are attributed once across sibling folders")
    func hardLinkAttribution() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        let file = try fixture.write("selected/first/shared.bin", count: 12_000)
        let second = try fixture.directory("selected/second").appendingPathComponent("linked.bin", isDirectory: false)
        try FileManager.default.linkItem(at: file, to: second)
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(!report.isPartial)
        #expect(report.fileCount == 2)
        #expect(report.logicalBytes == 24_000)
        #expect(report.allocatedBytes == (try allocated(file)))
        #expect(report.children.reduce(0) { $0 + $1.allocatedBytes } == report.allocatedBytes)
        #expect(report.children.reduce(0) { $0 + $1.logicalBytes } == report.logicalBytes)
        #expect(report.largestFiles.count == 1)
        #expect(report.largestFiles.first?.logicalBytes == 12_000)
        #expect(report.issues.filter { $0.message.contains("hardlinked") }.count == 1)
    }

    @Test("Unreadable folders preserve readable totals and expose partial results")
    func partialPermissions() async throws {
        let fixture = try DiskFixture()
        let readable = try fixture.write("selected/readable.bin", count: 4_000)
        _ = try fixture.write("selected/locked/private.bin", count: 90_000)
        let locked = fixture.selected.appendingPathComponent("locked", isDirectory: true)
        defer {
            _ = chmod(locked.path, 0o700)
            fixture.remove()
        }
        #expect(chmod(locked.path, 0) == 0)
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.isPartial)
        #expect(report.fileCount == 1)
        #expect(report.allocatedBytes == (try allocated(readable)))
        #expect(report.logicalBytes == 4_000)
        #expect(report.issues.contains { $0.url.path == locked.path })
        let item = try #require(report.children.first { $0.name == "locked" })
        #expect(item.isDirectory)
        #expect(item.allocatedBytes == 0)
    }

    @Test("Unreadable-item details remain bounded")
    func boundedIssues() async throws {
        let fixture = try DiskFixture()
        var locked: [URL] = []
        defer {
            for directory in locked { _ = chmod(directory.path, 0o700) }
            fixture.remove()
        }
        for index in 0..<125 {
            let directory = try fixture.directory("selected/locked-\(index)")
            locked.append(directory)
            #expect(chmod(directory.path, 0) == 0)
        }
        let report = await DiskMapEngine().scan(url: fixture.selected)
        #expect(report.isPartial)
        #expect(report.children.count == 125)
        #expect(report.issues.count == 101)
        #expect(report.issues.last?.message.contains("25 additional") == true)
    }

    @Test("Progress tracks real measured files and allocation totals")
    func progressValues() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        for index in 0..<12 { _ = try fixture.write("selected/folder/\(index).bin", count: 1_024) }
        let observations = DiskProgressRecorder()
        let report = await DiskMapEngine(progressInterval: 0).scan(url: fixture.selected, progress: { observations.append($0) })
        let progress = observations.values
        #expect(progress.count > 2)
        #expect(progress.first?.visitedFiles == 0)
        #expect(progress.last?.visitedFiles == report.fileCount)
        #expect(progress.last?.allocatedBytes == report.allocatedBytes)
        #expect(progress.allSatisfy { !$0.currentName.isEmpty })
        for (previous, next) in zip(progress, progress.dropFirst()) {
            #expect(next.visitedFiles >= previous.visitedFiles)
            #expect(next.allocatedBytes >= previous.allocatedBytes)
        }
    }

    @Test("Cancellation returns promptly with internally consistent measured partial totals")
    func cancellationDuringScan() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        for index in 0..<20 { _ = try fixture.write("selected/folder/\(index).bin", count: 4_096) }
        let engine = DiskMapEngine(progressInterval: 0)
        let task = Task {
            await engine.scan(url: fixture.selected, progress: { progress in
                if progress.visitedFiles >= 1 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.isPartial)
        #expect(report.fileCount == 1)
        #expect(report.logicalBytes == 4_096)
        #expect(report.children.reduce(0) { $0 + $1.allocatedBytes } == report.allocatedBytes)
        #expect(report.children.reduce(0) { $0 + $1.fileCount } == report.fileCount)
    }

    @Test("Cancellation from initial progress avoids filesystem traversal")
    func cancellationBeforeTraversal() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        _ = try fixture.write("selected/file.bin", count: 4_096)
        let engine = DiskMapEngine()
        let task = Task {
            await engine.scan(url: fixture.selected, progress: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.isPartial)
        #expect(report.children.isEmpty)
        #expect(report.fileCount == 0)
    }

    @Test("Replacing the selected path with a symlink cannot redirect an in-flight scan")
    func concurrentRootReplacement() async throws {
        let fixture = try DiskFixture()
        defer { fixture.remove() }
        _ = try fixture.write("selected/a.bin", count: 1_000)
        _ = try fixture.write("selected/b.bin", count: 2_000)
        _ = try fixture.write("outside/a.bin", count: 80_000)
        _ = try fixture.write("outside/b.bin", count: 90_000)
        let mutation = DiskMutationState()
        let original = fixture.selected
        let moved = fixture.base.appendingPathComponent("moved", isDirectory: true)
        let outside = fixture.base.appendingPathComponent("outside", isDirectory: true)
        let report = await DiskMapEngine(progressInterval: 0).scan(url: original, progress: { progress in
            if progress.visitedFiles >= 1, mutation.claim() {
                do {
                    try FileManager.default.moveItem(at: original, to: moved)
                    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
                } catch { mutation.record(error.localizedDescription) }
            }
        })
        #expect(mutation.error == nil)
        #expect(report.isPartial)
        #expect(report.fileCount == 2)
        #expect(report.logicalBytes == 3_000)
        #expect(report.largestFiles.reduce(0) { $0 + $1.logicalBytes } == 3_000)
        #expect(report.issues.contains { $0.message.contains("selected folder") || $0.message.contains("changed during") })
        #expect(try Data(contentsOf: outside.appendingPathComponent("a.bin")).count == 80_000)
    }
}

private func allocated(_ url: URL) throws -> Int64 {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
    return Int64(info.st_blocks) * 512
}

private struct DiskFixture: Sendable {
    let base: URL
    var selected: URL { base.appendingPathComponent("selected", isDirectory: true) }

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp/RoomDiskMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
    }

    func directory(_ relative: String) throws -> URL {
        let url = base.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ relative: String, count: Int) throws -> URL {
        let url = base.appendingPathComponent(relative, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: count).write(to: url)
        return url
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}

private final class DiskProgressRecorder: Sendable {
    private let state = Mutex<[DiskScanProgress]>([])
    var values: [DiskScanProgress] { state.withLock { $0 } }
    func append(_ value: DiskScanProgress) { state.withLock { $0.append(value) } }
}

private final class DiskMutationState: Sendable {
    private let state = Mutex<(claimed: Bool, error: String?)>((false, nil))
    var error: String? { state.withLock { $0.error } }
    func claim() -> Bool {
        state.withLock {
            if $0.claimed { return false }
            $0.claimed = true
            return true
        }
    }
    func record(_ error: String) { state.withLock { $0.error = error } }
}
