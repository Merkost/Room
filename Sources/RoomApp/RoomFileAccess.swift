import AppKit
import Foundation
import Observation

nonisolated enum RoomInsightDestination: Hashable, Sendable { case overview, clean, memory, disk }

struct RoomAccessFolder: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

struct RoomUnavailableAccessFolder: Identifiable, Equatable {
    let id: String
    let url: URL?
    var name: String { url?.lastPathComponent ?? String(localized: "Unavailable folder") }
}

struct RoomBookmarkResolution {
    let url: URL
    let isStale: Bool
}

/// Stores only bookmarks created after a native folder-picker approval.
@Observable @MainActor
final class RoomFileAccess {
    static let shared = RoomFileAccess()
    private struct Record: Codable {
        let id: String
        var bookmark: Data
        var lastKnownPath: String?
    }

    private let defaults: UserDefaults
    private let key = "RoomApprovedFolderBookmarks"
    private var records: [Record]
    private var resolvedFolders: [RoomAccessFolder] = []
    private var stagedRemovalIDs: Set<String> = []
    var folders: [RoomAccessFolder] { resolvedFolders.filter { !stagedRemovalIDs.contains($0.id) } }
    private var unresolvedFolders: [RoomUnavailableAccessFolder] = []
    var unavailableFolders: [RoomUnavailableAccessFolder] {
        unresolvedFolders.filter { !stagedRemovalIDs.contains($0.id) }
    }
    private(set) var note: String?
    @ObservationIgnored private let bookmarkResolver: (Data) throws -> RoomBookmarkResolution
    @ObservationIgnored private let bookmarkCreator: (URL) throws -> Data

    init(defaults: UserDefaults = .standard,
         bookmarkResolver: ((Data) throws -> RoomBookmarkResolution)? = nil,
         bookmarkCreator: ((URL) throws -> Data)? = nil) {
        self.defaults = defaults
        self.bookmarkResolver = bookmarkResolver ?? Self.resolveBookmark
        self.bookmarkCreator = bookmarkCreator ?? Self.createBookmark
        records = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Record].self, from: $0) }) ?? []
        resolveBookmarks()
    }

    func remember(_ url: URL) throws -> URL {
        reloadRecords()
        let (bookmark, resolvedURL) = try approvedBookmark(for: url)
        let recordID: String
        if let folder = folders.first(where: { Self.lexicalPath($0.url) == Self.lexicalPath(resolvedURL) }),
           let index = records.firstIndex(where: { $0.id == folder.id }) {
            records[index].bookmark = bookmark
            records[index].lastKnownPath = resolvedURL.path
            recordID = folder.id
        } else {
            recordID = UUID().uuidString
            records.append(Record(id: recordID, bookmark: bookmark, lastKnownPath: resolvedURL.path))
        }
        persist()
        resolveBookmarks()
        guard let approved = folders.first(where: { $0.id == recordID }) else { throw CocoaError(.fileReadUnknown) }
        // Bookmark resolution may canonicalize /var to /private/var. Scan the
        // approved resolved URL instead of re-prompting on that alias mismatch.
        return approved.url
    }

    /// Restore the same root so a retained tree, saved view, or Room keeps its identity.
    func renew(id: String, approvedURL: URL) throws {
        reloadRecords()
        guard let folder = unavailableFolders.first(where: { $0.id == id }),
              let expected = folder.url, let index = records.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let (bookmark, approved) = try approvedBookmark(for: approvedURL)
        guard Self.lexicalPath(approved) == Self.lexicalPath(expected),
              !folders.contains(where: { Self.lexicalPath($0.url) == Self.lexicalPath(approved) }) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        records[index] = Record(id: id, bookmark: bookmark, lastKnownPath: approved.path)
        persist()
        resolveBookmarks()
        guard folders.contains(where: { $0.id == id }) else { throw CocoaError(.fileReadUnknown) }
    }

    func stageRemoval(id: String) { stagedRemovalIDs.insert(id) }

    func undoRemoval(id: String) { stagedRemovalIDs.remove(id) }

    func forget(id: String) {
        reloadRecords()
        records.removeAll { $0.id == id }
        stagedRemovalIDs.remove(id)
        persist()
        resolveBookmarks()
    }

    func scope(for url: URL) -> URL? {
        folders.filter { Self.contains(parent: $0.url, child: url) }
            .max { $0.url.path.count < $1.url.path.count }?.url
    }

    func setNote(_ message: String?) { note = message }

    private func reloadRecords() {
        records = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Record].self, from: $0) }) ?? []
        resolveBookmarks()
    }

    static func contains(parent: URL, child: URL) -> Bool {
        guard parent.isFileURL, child.isFileURL else { return false }
        let root = lexicalPath(parent)
        let path = lexicalPath(child)
        return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private static func lexicalPath(_ url: URL) -> String {
        var components: [String] = []
        for part in url.pathComponents where part != "/" && part != "." {
            if part == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(part) }
        }
        return "/" + components.joined(separator: "/")
    }

    private func resolveBookmarks() {
        var resolved: [RoomAccessFolder] = []
        var unavailable: [RoomUnavailableAccessFolder] = []
        var recordedPath = false
        for index in records.indices {
            let record = records[index]
            let known = record.lastKnownPath.map { URL(filePath: $0, directoryHint: .isDirectory) }
            do {
                let bookmark = try bookmarkResolver(record.bookmark)
                if bookmark.isStale {
                    unavailable.append(.init(id: record.id, url: known ?? bookmark.url))
                } else {
                    let url = bookmark.url
                    resolved.append(RoomAccessFolder(id: record.id, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, url: url))
                    if record.lastKnownPath != url.path {
                        records[index].lastKnownPath = url.path
                        recordedPath = true
                    }
                }
            } catch {
                unavailable.append(.init(id: record.id, url: known))
            }
        }
        resolvedFolders = resolved
        unresolvedFolders = unavailable
        note = unavailable.isEmpty ? nil : String(localized: "Renew or remove unavailable folders in Settings.")
        if recordedPath { persist() }
    }

    private func approvedBookmark(for url: URL) throws -> (Data, URL) {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try bookmarkCreator(url)
        let resolution = try bookmarkResolver(bookmark)
        guard !resolution.isStale, resolution.url.isFileURL else { throw CocoaError(.fileReadUnknown) }
        return (bookmark, resolution.url)
    }

    private static func createBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolveBookmark(_ data: Data) throws -> RoomBookmarkResolution {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        return RoomBookmarkResolution(url: url, isStale: stale)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
