import Darwin
import Foundation
import Synchronization
import Testing
@testable import RoomCore

@Suite("Filesystem safety", .serialized)
struct CacheEngineTests {
    @Test("The production catalogue contains only explicit cache locations")
    func explicitCatalogue() {
        let configuration = CacheConfiguration.standard
        let paths = configuration.roots.map(\.url.path)
        let home = configuration.homeDirectory.path
        #expect(!paths.contains(home + "/Library/Caches"))
        #expect(!paths.contains(home + "/.codex"))
        #expect(!paths.contains(home + "/.claude"))
        #expect(!paths.contains(home + "/.codex/tmp"))
        #expect(!paths.contains(home + "/.claude/cache"))
        #expect(paths.contains(home + "/.claude/cache/changelog.md"))
        #expect(configuration.roots.allSatisfy { $0.minimumAge >= 7 * 86_400 })
        #expect(configuration.roots.filter { $0.id == "codex-logs" || $0.id == "claude-debug" }
            .allSatisfy { $0.minimumAge == 30 * 86_400 })
        #expect(Set(configuration.roots.map(\.id)).count == configuration.roots.count)
        #expect(!configuration.protectedLocations.isEmpty)
    }

    @Test("Physical paths and directory URLs without trailing slashes stay valid")
    func physicalPathNormalization() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "cache")
        let root = CacheRoot(id: "no-slash", title: "Cache", subtitle: "", symbol: "archivebox", category: "developer",
            url: URL(fileURLWithPath: fixture.cache.path, isDirectory: false), consequence: "Rebuilds", minimumAge: 0)
        #expect(root.url.path == fixture.cache.path)
        let engine = fixture.engine(root: root)
        let report = await engine.scan()
        #expect(report.eligibleEntries.count == 1, "\(report.issues)")
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1, "\(receipt.issues)")
        #expect(await engine.restore(receiptID: receipt.id).restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Only allowlisted children are offered and protected data cannot be selected")
    func allowlistAndProtectedData() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.write("cache/archive", "rebuildable")
        let protected = try fixture.write("protected/conversation.jsonl", "important user work")
        let configuration = CacheConfiguration(roots: [fixture.root()], protectedLocations: [
            ProtectedLocation(id: "protected", title: "Conversations", url: protected.deletingLastPathComponent(), reason: "User work")
        ], homeDirectory: fixture.base)
        let engine = fixture.engine(configuration: configuration)
        let report = await engine.scan()
        #expect(report.issues.isEmpty, "\(report.issues)")
        #expect(report.groups.count == 1)
        #expect(report.eligibleEntries.map(\.url) == [cache])
        #expect(report.protectedData.first?.byteCount ?? 0 > 0)
        let forged = await engine.clean(entryIDs: [UUID()])
        #expect(forged.items.isEmpty)
        #expect(!forged.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: protected.path))
    }

    @Test("Protected size budgets return lower bounds without limiting cache verification")
    func boundedProtectedMeasurement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for name in ["a", "b", "c"] {
            _ = try fixture.write("cache/complete/\(name)", String(repeating: "cache", count: 4096))
            _ = try fixture.write("protected/\(name)", String(repeating: "protected", count: 1024))
        }
        let protected = fixture.base.appendingPathComponent("protected", isDirectory: true)
        let configuration = CacheConfiguration(roots: [fixture.root()], protectedLocations: [
            ProtectedLocation(id: "protected", title: "Protected work", url: protected, reason: "User work stays in place.")
        ], homeDirectory: fixture.base)
        let complete = await fixture.engine(configuration: configuration, protectedTimeLimit: 60).scan()
        let fullProtected = try #require(complete.protectedData.first)
        #expect(!fullProtected.isPartial)
        let marker = ScanMarker()
        let engine = fixture.engine(configuration: configuration, protectedNodeLimit: 2, protectedTimeLimit: 60,
            processes: {
                Thread.sleep(forTimeInterval: 0.01)
                marker.mark()
                return []
            })
        let limited = await engine.scan()
        let partial = try #require(limited.protectedData.first)
        #expect(partial.isPartial)
        #expect(limited.isPartial)
        #expect(limited.issues.isEmpty)
        #expect(partial.byteCount > 0)
        #expect(partial.byteCount < fullProtected.byteCount)
        #expect(partial.reason.contains("lower bound"))
        #expect(limited.eligibleEntries.count == 1)
        #expect(limited.eligibleEntries.first?.fileCount == 3)
        #expect(limited.eligibleBytes == complete.eligibleBytes)
        let afterProcessCheck = try #require(marker.date)
        #expect(limited.scannedAt >= afterProcessCheck)
        let receipt = await engine.clean(entryIDs: Set(limited.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        #expect(await engine.restore(receiptID: receipt.id).restoredCount == 1)
        #expect(FileManager.default.fileExists(atPath: protected.appendingPathComponent("c").path))
    }

    @Test("Symlink entries and symlink descendants are never followed or cleaned")
    func symbolicLinks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = try fixture.write("outside/important", "outside")
        let safeFolder = try fixture.directory("cache/with-link")
        try FileManager.default.createSymbolicLink(at: safeFolder.appendingPathComponent("linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: fixture.cache.appendingPathComponent("direct-link"), withDestinationURL: outside)
        let report = await fixture.engine().scan()
        #expect(report.groups.first?.entries.count == 2)
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.groups.first?.totalBytes == 0)
        #expect(report.groups.first?.entries.allSatisfy { $0.eligibility.reason?.contains("symbolic") == true } == true)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
    }

    @Test("A symlink cache root is never enumerated")
    func symbolicLinkRoot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = try fixture.write("outside/important", "outside")
        try FileManager.default.moveItem(at: fixture.cache, to: fixture.base.appendingPathComponent("previous-cache", isDirectory: true))
        try FileManager.default.createSymbolicLink(at: fixture.cache, withDestinationURL: outside.deletingLastPathComponent())
        let report = await fixture.engine().scan()
        #expect(report.groups.first?.entries.isEmpty == true)
        #expect(report.issues.first?.message.contains("symbolic link") == true)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
    }

    @Test("Shared hard links are kept out of reclaimable space")
    func sharedHardLinks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write("outside-shared", "shared storage")
        try FileManager.default.linkItem(at: original, to: fixture.cache.appendingPathComponent("cached-link"))
        let report = await fixture.engine().scan()
        #expect(report.groups.first?.entries.count == 1)
        #expect(report.eligibleBytes == 0)
        #expect(report.groups.first?.entries.first?.eligibility.reason?.contains("hard links") == true)
        #expect(try String(contentsOf: original, encoding: .utf8) == "shared storage")
    }

    @Test("Unreadable descendants produce a partial report and block the whole item")
    func unreadableDirectory() async throws {
        let fixture = try Fixture()
        let directory = try fixture.directory("cache/locked")
        _ = try fixture.write("cache/locked/file", "cache")
        defer {
            _ = chmod(directory.path, 0o700)
            fixture.remove()
        }
        #expect(chmod(directory.path, 0) == 0)
        let report = await fixture.engine().scan()
        #expect(report.groups.first?.entries.count == 1)
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.isPartial)
        #expect(report.issues.contains { $0.url.path == directory.path })
    }

    @Test("A fresh descendant keeps its entire cache entry in place")
    func modificationAgeAppliesToDescendants() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = try fixture.directory("cache/build")
        _ = try fixture.write("cache/build/new", "fresh")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60 * 86_400)], ofItemAtPath: directory.path)
        let report = await fixture.engine(root: fixture.root(age: 7 * 86_400)).scan()
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.groups.first?.entries.first?.eligibility.reason?.contains("7 days") == true)
    }

    @Test("An active runtime and a failed runtime check both fail closed")
    func runtimeGuards() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "cache")
        let root = fixture.root(processes: ["claude"])
        let active = fixture.engine(root: root, processes: { ["/Applications/Claude.app/Contents/MacOS/Claude"] })
        let activeReport = await active.scan()
        #expect(activeReport.groups.first?.entries.count == 1)
        #expect(activeReport.eligibleEntries.isEmpty)
        let unavailable = fixture.engine(root: root, processes: { throw FixtureError.expected })
        let report = await unavailable.scan()
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.isPartial)
    }

    @Test("A runtime that starts after review prevents the Trash move")
    func runtimeStartsAfterScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "cache")
        let runtime = RuntimeState()
        let engine = fixture.engine(root: fixture.root(processes: ["codex"]), processes: { runtime.names })
        let report = await engine.scan()
        #expect(report.eligibleEntries.count == 1)
        runtime.names = ["/Applications/Codex.app/Contents/MacOS/Codex"]
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(!receipt.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("An unknown native executable inside a cache prevents scan eligibility")
    func containedNativeExecutableAtScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try fixture.write("cache/package/bin/native-mcp", "native tool fixture")
        let archive = try fixture.write("cache/archive", "cache")
        let engine = fixture.engine(root: fixture.root(processes: ["node"]), processes: { [executable.path] })
        let report = await engine.scan()
        #expect(report.groups.first?.entries.count == 2)
        #expect(report.eligibleEntries.isEmpty)
        #expect(report.groups.first?.entries.allSatisfy { $0.eligibility.reason?.contains("A cached tool") == true } == true)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("A native executable that starts inside a cache after scanning prevents every move")
    func containedNativeExecutableStartsAfterScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try fixture.write("cache/package/bin/native-mcp", "native tool fixture")
        let archive = try fixture.write("cache/archive", "cache")
        let runtime = RuntimeState()
        let engine = fixture.engine(root: fixture.root(processes: ["node"]), processes: { runtime.names })
        let report = await engine.scan()
        #expect(report.eligibleEntries.count == 2)
        runtime.names = [executable.path]
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(receipt.items.count == 2)
        #expect(receipt.items.allSatisfy { $0.status == .failed })
        #expect(receipt.issues.allSatisfy { $0.message.contains("A cached tool") })
        #expect(FileManager.default.fileExists(atPath: executable.path))
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("A cache prefix in a different folder name does not falsely block cleanup")
    func containedExecutableRequiresPathComponentBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = try fixture.write("cache/archive", "cache")
        let outside = try fixture.write("cache-other/native-mcp", "outside tool fixture")
        let engine = fixture.engine(root: fixture.root(processes: ["node"]), processes: { [outside.path] })
        let report = await engine.scan()
        #expect(report.eligibleEntries.count == 1)
        #expect(report.eligibleEntries.first?.url == archive)
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(await engine.restore(receiptID: receipt.id).restoredCount == 1)
    }

    @Test("Versioned executables and desktop helper names are guarded",
        arguments: ["/usr/bin/python3", "/opt/bin/python3.14", "/opt/bin/pip3", "Codex (Service)",
                    "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"])
    func runtimeExecutableVariants(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "cache")
        let engine = fixture.engine(root: fixture.root(processes: ["python", "pip", "codex", "chatgpt"]), processes: { [name] })
        let report = await engine.scan()
        #expect(report.groups.first?.entries.count == 1)
        #expect(report.eligibleEntries.isEmpty)
    }

    @Test("Content modified after scanning stays in place even when the age gate is disabled")
    func staleItem() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "old")
        let engine = fixture.engine()
        let report = await engine.scan()
        try Data("newer contents".utf8).write(to: file)
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "newer contents")
    }

    @Test("A newly added descendant invalidates the reviewed tree")
    func newDescendantAfterScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/build/a", "old")
        let engine = fixture.engine()
        let report = await engine.scan()
        let newFile = try fixture.write("cache/build/nested/new", "new")
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(FileManager.default.fileExists(atPath: newFile.path))
    }

    @Test("Replacing a cache root with a symlink cannot redirect cleanup")
    func replacedRootSymlink() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "reviewed")
        let outside = try fixture.write("outside/archive", "precious")
        let engine = fixture.engine()
        let report = await engine.scan()
        try FileManager.default.moveItem(at: fixture.cache, to: fixture.base.appendingPathComponent("original-cache"))
        try FileManager.default.createSymbolicLink(at: fixture.cache, withDestinationURL: outside.deletingLastPathComponent())
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "precious")
    }

    @Test("Replacing a reviewed item with a symlink cannot redirect cleanup")
    func replacedItemSymlink() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "reviewed")
        let outside = try fixture.write("outside/archive", "precious")
        let engine = fixture.engine()
        let report = await engine.scan()
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        let receipt = await engine.clean(entryIDs: Set(report.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "precious")
    }

    @Test("Receipts persist, restore protects new files, and retry restores the previous item")
    func persistenceAndRestoreCollision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "previous")
        let first = fixture.engine()
        let scan = await first.scan()
        let receipt = await first.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let relaunched = fixture.engine()
        #expect(await relaunched.history().first?.id == receipt.id)
        _ = try fixture.write("cache/archive", "newer")
        let collision = await relaunched.restore(receiptID: receipt.id)
        #expect(collision.restoredCount == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "newer")
        #expect(collision.receipt.canRestore)
        try FileManager.default.removeItem(at: file)
        let restored = await relaunched.restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == "previous")
        #expect(!restored.receipt.canRestore)
    }

    @Test("A partial Trash receipt stays visible and directs manual Finder recovery")
    func partialRecoveryReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "previous")
        let engine = fixture.engine()
        let scan = await engine.scan()
        #expect(scan.eligibleEntries.count == 1)
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        try fixture.tamper(receipt.id) { items in
            items[0].removeValue(forKey: "trashIdentity")
            items[0].removeValue(forKey: "trashFingerprint")
        }
        let relaunched = fixture.engine()
        let history = await relaunched.history()
        #expect(history.first?.canRestore == true)
        let result = await relaunched.restore(receiptID: receipt.id)
        #expect(result.restoredCount == 0)
        #expect(result.issues.first?.message.contains("Finder") == true)
        #expect(result.receipt.items.first?.status == .trashed)
    }

    @Test("Receipts cannot restore to an unallowlisted original path")
    func tamperedOriginalPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "previous")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let outside = fixture.base.appendingPathComponent("outside-target")
        try fixture.tamper(receipt.id) { items in items[0]["originalURL"] = outside.absoluteString }
        let result = await fixture.engine().restore(receiptID: receipt.id)
        #expect(result.restoredCount == 0)
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("Receipts cannot retrieve a file from outside Trash")
    func tamperedTrashPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "previous")
        let outside = try fixture.write("outside-important", "precious")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        try fixture.tamper(receipt.id) { items in items[0]["trashURL"] = outside.absoluteString }
        let result = await fixture.engine().restore(receiptID: receipt.id)
        #expect(result.restoredCount == 0)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "precious")
    }

    @Test("Changes to descendants in Trash prevent automatic restoration")
    func changedTrashTree() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/build/nested/file", "previous")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let trash = try #require(receipt.items.first?.trashURL)
        try Data("changed".utf8).write(to: trash.appendingPathComponent("nested/file"))
        let restored = await engine.restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 0)
        #expect(FileManager.default.fileExists(atPath: trash.path))
    }

    @Test("Root-only extended attribute changes in Trash preserve file and folder recovery", arguments: [false, true])
    func trashRootMetadataDrift(isDirectory: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write(isDirectory ? "cache/build/nested/file" : "cache/archive", "previous cache payload")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        let item = try #require(receipt.items.first)
        let trash = try #require(item.trashURL)
        let recorded = try #require(item.trashIdentity)
        try addFixtureExtendedAttribute(trash)
        var current = stat()
        #expect(lstat(trash.path, &current) == 0)
        #expect(current.st_ctimespec.tv_sec != recorded.changedSeconds || current.st_ctimespec.tv_nsec != recorded.changedNanoseconds)
        #expect(UInt64(UInt32(bitPattern: current.st_dev)) == recorded.device)
        #expect(UInt64(current.st_ino) == recorded.inode)
        #expect(current.st_mode == recorded.mode)
        #expect(Int64(current.st_size) == recorded.byteCount)
        #expect(Int64(current.st_mtimespec.tv_sec) == recorded.modifiedSeconds)
        #expect(Int64(current.st_mtimespec.tv_nsec) == recorded.modifiedNanoseconds)
        if !isDirectory {
            try fixture.tamper(receipt.id) { items in items[0].removeValue(forKey: "originalParentIdentity") }
        }
        // Reloading the exact recorded fingerprint also exercises existing
        // receipts: normalization must not require a new fingerprint format.
        let restored = await fixture.engine().restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 1, "\(restored.issues)")
        #expect(try Data(contentsOf: original) == Data("previous cache payload".utf8))
    }

    @Test("Root ctime tolerance never ignores size, mtime, mode or inode changes", arguments: ["size", "mtime", "mode", "inode"])
    func changedTrashRoot(field: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write("cache/archive", "previous cache payload")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let trash = try #require(receipt.items.first?.trashURL)
        let identity = try #require(receipt.items.first?.trashIdentity)
        try addFixtureExtendedAttribute(trash)
        switch field {
        case "size":
            try Data("different and much larger replacement payload".utf8).write(to: trash)
            try restoreFixtureMtime(trash, identity: identity)
        case "mtime": try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: trash.path)
        case "mode": #expect(chmod(trash.path, mode_t(identity.mode ^ 0o100)) == 0)
        case "inode":
            let holding = fixture.trash.appendingPathComponent("previous-inode", isDirectory: false)
            try FileManager.default.moveItem(at: trash, to: holding)
            try Data("previous cache payload".utf8).write(to: trash)
            #expect(chmod(trash.path, mode_t(identity.mode)) == 0)
            try restoreFixtureMtime(trash, identity: identity)
        default: Issue.record("Unexpected test field")
        }
        let restored = await fixture.engine().restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 0)
        #expect(!restored.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: trash.path))
    }

    @Test("Root ctime normalization leaves descendant-only xattr changes strictly rejected")
    func changedTrashDescendantMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write("cache/build/nested/file", "previous cache payload")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let trash = try #require(receipt.items.first?.trashURL)
        try addFixtureExtendedAttribute(trash)
        try addFixtureExtendedAttribute(trash.appendingPathComponent("nested/file", isDirectory: false))
        let restored = await fixture.engine().restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 0)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: trash.path))
    }

    @Test("A new hardlink in Trash cannot hide behind root-only ctime drift")
    func changedTrashLinkCount() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write("cache/archive", "previous cache payload")
        let engine = fixture.engine()
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let trash = try #require(receipt.items.first?.trashURL)
        try FileManager.default.linkItem(at: trash, to: fixture.base.appendingPathComponent("extra-link", isDirectory: false))
        let restored = await fixture.engine().restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 0)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: trash.path))
    }

    @Test("A Trash source replaced during the final owner check is never restored")
    func replacedTrashSourceDuringOwnerCheck() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.write("cache/archive", "reviewed cache payload")
        let state = RestoreMutationState()
        let engine = fixture.engine(root: fixture.root(processes: ["fixturetool"]), processes: {
            try state.replaceIfArmed()
            return []
        })
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        let trash = try #require(receipt.items.first?.trashURL)
        state.target.withLock { $0 = trash }
        let restored = await engine.restore(receiptID: receipt.id)
        #expect(restored.restoredCount == 0)
        #expect(!restored.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(try Data(contentsOf: trash) == Data("unreviewed replacement".utf8))
    }

    @Test("A receipt write failure prevents every cleanup move")
    func receiptWriteFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.write("cache/archive", "cache")
        let unusableActivityDirectory = try fixture.write("bad-activity", "not a folder")
        let engine = fixture.engine(activityDirectory: unusableActivityDirectory)
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 0)
        #expect(!receipt.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A cancelled scan never leaves eligible cleanup IDs")
    func cancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.write("cache/archive", "cache")
        let engine = fixture.engine()
        let task = Task { await engine.scan() }
        task.cancel()
        let result = await task.value
        #expect(result.cancelled)
        let receipt = await engine.clean(entryIDs: Set(result.groups.flatMap(\.entries).map(\.id)))
        #expect(receipt.trashedCount == 0)
    }

    @Test("A single-file root cannot broaden into its sibling user data")
    func singleFileScope() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let allowed = try fixture.write("cache/changelog.md", "changelog")
        let protected = try fixture.write("cache/user-work", "precious")
        let root = CacheRoot(id: "single", title: "Changelog", subtitle: "", symbol: "doc", category: "agents",
            url: allowed, consequence: "Downloads again", minimumAge: 0, scope: .singleFile)
        let engine = fixture.engine(root: root)
        let scan = await engine.scan()
        #expect(scan.eligibleEntries.map(\.url) == [allowed])
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1)
        #expect(try String(contentsOf: protected, encoding: .utf8) == "precious")
        #expect(await engine.restore(receiptID: receipt.id).restoredCount == 1)
    }

    @Test("System Trash and restore operate on isolated file and folder fixtures only", arguments: [false, true])
    func actualSystemTrashRoundTrip(isDirectory: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = "room-test-\(UUID().uuidString)"
        let file: URL
        if isDirectory {
            file = try fixture.directory("cache/\(name)")
            _ = try fixture.write("cache/\(name)/nested/file.txt", "temporary Room integration fixture")
        } else {
            file = try fixture.write("cache/\(name).txt", "temporary Room integration fixture")
        }
        let engine = CacheEngine(configuration: CacheConfiguration(roots: [fixture.root()], homeDirectory: fixture.base),
            activityDirectory: fixture.activity, processProvider: { [] })
        let scan = await engine.scan()
        let receipt = await engine.clean(entryIDs: Set(scan.eligibleEntries.map(\.id)))
        #expect(receipt.trashedCount == 1, "System Trash errors: \(receipt.issues)")
        #expect(receipt.issues.isEmpty, "System Trash metadata errors: \(receipt.issues)")
        let trashURL = try #require(receipt.items.first?.trashURL)
        defer {
            if FileManager.default.fileExists(atPath: trashURL.path) {
                try? FileManager.default.moveItem(at: trashURL, to: fixture.base.appendingPathComponent("returned-system-trash-fixture"))
            }
        }
        #expect(trashURL != file)
        #expect(FileManager.default.fileExists(atPath: trashURL.path))
        let result = await engine.restore(receiptID: receipt.id)
        #expect(result.restoredCount == 1, "Restore errors: \(result.issues)")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))
    }
}

private struct Fixture {
    let base: URL
    var cache: URL { base.appendingPathComponent("cache", isDirectory: true) }
    var trash: URL { base.appendingPathComponent("fixture-trash", isDirectory: true) }
    var activity: URL { base.appendingPathComponent("activity", isDirectory: true) }

    init() throws {
        // An explicit physical path avoids macOS's /var and /tmp symlink aliases.
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("RoomTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    func directory(_ relative: String) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ relative: String, _ content: String) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    func root(age: TimeInterval = 0, processes: [String] = []) -> CacheRoot {
        CacheRoot(id: "fixture", title: "Fixture", subtitle: "Isolated test cache", symbol: "archivebox",
            category: "developer", url: cache, consequence: "Test only", minimumAge: age, guardedProcesses: processes)
    }

    func engine(root: CacheRoot? = nil, configuration: CacheConfiguration? = nil,
                activityDirectory: URL? = nil,
                protectedNodeLimit: Int = 25_000, protectedTimeLimit: TimeInterval = 1,
                processes: @escaping @Sendable () throws -> [String] = { [] }) -> CacheEngine {
        let trash = self.trash
        return CacheEngine(configuration: configuration ?? CacheConfiguration(roots: [root ?? self.root()], homeDirectory: base),
            activityDirectory: activityDirectory ?? activity, processProvider: processes, fixtureTrashDirectory: trash,
            protectedMeasurementNodeLimit: protectedNodeLimit, protectedMeasurementTimeLimit: protectedTimeLimit,
            trashProvider: { original in
                let destination = trash.appendingPathComponent(UUID().uuidString + "-" + original.lastPathComponent)
                try FileManager.default.moveItem(at: original, to: destination)
                return destination
            })
    }

    func tamper(_ id: UUID, change: (inout [[String: Any]]) -> Void) throws {
        let url = activity.appendingPathComponent("\(id.uuidString).json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var items = try #require(object["items"] as? [[String: Any]])
        change(&items)
        object["items"] = items
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}

private final class RuntimeState: Sendable {
    private let state = Mutex<[String]>([])
    var names: [String] {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private enum FixtureError: Error { case expected }

private final class ScanMarker: Sendable {
    private let value = Mutex<Date?>(nil)
    var date: Date? { value.withLock { $0 } }
    func mark() { value.withLock { $0 = Date() } }
}

private func addFixtureExtendedAttribute(_ url: URL) throws {
    let data = Data("OS-style metadata only".utf8)
    let result = data.withUnsafeBytes { bytes in
        setxattr(url.path, "com.room.fixture-recovery", bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
    }
    #expect(result == 0, "Fixture xattr mutation failed: \(String(cString: strerror(errno)))")
}

private func restoreFixtureMtime(_ url: URL, identity: FileIdentity) throws {
    var times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
        timespec(tv_sec: Int(identity.modifiedSeconds), tv_nsec: Int(identity.modifiedNanoseconds))]
    let result = times.withUnsafeMutableBufferPointer {
        utimensat(AT_FDCWD, url.path, $0.baseAddress, AT_SYMLINK_NOFOLLOW)
    }
    #expect(result == 0, "Fixture mtime mutation failed")
}

private final class RestoreMutationState: Sendable {
    let target = Mutex<URL?>(nil)
    func replaceIfArmed() throws {
        guard let url = target.withLock({ value in let result = value; value = nil; return result }) else { return }
        let holding = url.deletingLastPathComponent().appendingPathComponent("previous-reviewed-item", isDirectory: false)
        try FileManager.default.moveItem(at: url, to: holding)
        try Data("unreviewed replacement".utf8).write(to: url)
    }
}
