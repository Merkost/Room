import AppKit
import Foundation
import Observation

enum RoomInsightDestination: Hashable { case clean, memory, disk, settings }

struct RoomAccessFolder: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

/// Identity survives a stale or unresolvable bookmark without granting scope.
struct RoomUnavailableAccessFolder: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String?
    let reason: String
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
        var lastKnownName: String?
    }

    private let defaults: UserDefaults
    private let key = "RoomApprovedFolderBookmarks"
    private var records: [Record]
    private(set) var folders: [RoomAccessFolder] = []
    private(set) var unavailableFolders: [RoomUnavailableAccessFolder] = []
    private(set) var note: String?

    @ObservationIgnored private let bookmarkResolver: @MainActor (Data) throws -> RoomBookmarkResolution
    @ObservationIgnored private let bookmarkCreator: @MainActor (URL) throws -> Data

    init(defaults: UserDefaults = .standard,
         bookmarkResolver: (@MainActor (Data) throws -> RoomBookmarkResolution)? = nil,
         bookmarkCreator: (@MainActor (URL) throws -> Data)? = nil) {
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
        if let folder = folders.first(where: { $0.url.standardizedFileURL.path == resolvedURL.standardizedFileURL.path }),
           let index = records.firstIndex(where: { $0.id == folder.id }) {
            records[index].bookmark = bookmark
            records[index].lastKnownPath = resolvedURL.path
            records[index].lastKnownName = Self.name(for: resolvedURL)
            recordID = folder.id
        } else {
            recordID = UUID().uuidString
            records.append(Record(id: recordID, bookmark: bookmark,
                                  lastKnownPath: resolvedURL.path, lastKnownName: Self.name(for: resolvedURL)))
        }
        persist()
        resolveBookmarks()
        guard let approved = folders.first(where: { $0.id == recordID }) else { throw CocoaError(.fileReadUnknown) }
        // Bookmark resolution may canonicalize /var to /private/var. Scan the
        // approved resolved URL instead of re-prompting on that alias mismatch.
        return approved.url
    }

    /// Call only with a URL explicitly approved by the native folder picker.
    /// A removed record cannot be resurrected by a picker that was already open.
    @discardableResult
    func renew(id: String, approvedURL: URL) throws -> URL {
        reloadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let (bookmark, approved) = try approvedBookmark(for: approvedURL)
        records[index] = Record(id: id, bookmark: bookmark,
                               lastKnownPath: approved.path, lastKnownName: Self.name(for: approved))
        persist()
        resolveBookmarks()
        guard let folder = folders.first(where: { $0.id == id }) else { throw CocoaError(.fileReadUnknown) }
        note = "Folder access renewed. Changes still require a separate review."
        return folder.url
    }

    func forget(id: String) {
        reloadRecords()
        records.removeAll { $0.id == id }
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
        note = nil
        var resolved: [RoomAccessFolder] = []
        var unavailable: [RoomUnavailableAccessFolder] = []
        var updatedIdentity = false
        for index in records.indices {
            var record = records[index]
            do {
                let resolution = try bookmarkResolver(record.bookmark)
                let path = resolution.isStale ? record.lastKnownPath ?? resolution.url.path : resolution.url.path
                let name = resolution.isStale ? record.lastKnownName ?? Self.name(for: resolution.url) : Self.name(for: resolution.url)
                if record.lastKnownPath != path || record.lastKnownName != name {
                    record.lastKnownPath = path
                    record.lastKnownName = name
                    records[index] = record
                    updatedIdentity = true
                }
                if resolution.isStale {
                    unavailable.append(Self.unavailable(record, reason: "Approval needs renewal"))
                } else {
                    resolved.append(RoomAccessFolder(id: record.id, name: name, url: resolution.url))
                }
            } catch {
                unavailable.append(Self.unavailable(record, reason: "Folder unavailable"))
            }
        }
        folders = resolved
        unavailableFolders = unavailable
        if !unavailable.isEmpty {
            note = "\(unavailable.count) saved \(unavailable.count == 1 ? "folder needs" : "folders need") attention. Renew or forget access in Settings."
        }
        if updatedIdentity { persist() }
    }

    private func approvedBookmark(for url: URL) throws -> (Data, URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try bookmarkCreator(url)
        let resolution = try bookmarkResolver(bookmark)
        guard !resolution.isStale else { throw CocoaError(.fileReadUnknown) }
        return (bookmark, resolution.url)
    }

    private static func name(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private static func unavailable(_ record: Record, reason: String) -> RoomUnavailableAccessFolder {
        let name = record.lastKnownName
            ?? record.lastKnownPath.map { Self.name(for: URL(fileURLWithPath: $0)) }
            ?? "Saved folder"
        return RoomUnavailableAccessFolder(id: record.id, name: name, path: record.lastKnownPath, reason: reason)
    }

    private static func createBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolveBookmark(_ bookmark: Data) throws -> RoomBookmarkResolution {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return RoomBookmarkResolution(url: url, isStale: stale)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
