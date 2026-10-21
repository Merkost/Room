import AppKit
import Foundation
import Observation

enum RoomInsightDestination: Hashable { case clean, memory, disk }

struct RoomAccessFolder: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

/// Stores only bookmarks created after a native folder-picker approval.
@Observable @MainActor
final class RoomFileAccess {
    static let shared = RoomFileAccess()
    private struct Record: Codable {
        let id: String
        var bookmark: Data
    }

    private let defaults: UserDefaults
    private let key = "RoomApprovedFolderBookmarks"
    private var records: [Record]
    private(set) var folders: [RoomAccessFolder] = []
    private(set) var note: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Record].self, from: $0) }) ?? []
        resolveBookmarks()
    }

    func remember(_ url: URL) throws -> URL {
        reloadRecords()
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        let recordID: String
        if let folder = folders.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }),
           let index = records.firstIndex(where: { $0.id == folder.id }) {
            records[index].bookmark = bookmark
            recordID = folder.id
        } else {
            recordID = UUID().uuidString
            records.append(Record(id: recordID, bookmark: bookmark))
        }
        persist()
        resolveBookmarks()
        guard let approved = folders.first(where: { $0.id == recordID }) else { throw CocoaError(.fileReadUnknown) }
        // Bookmark resolution may canonicalize /var to /private/var. Scan the
        // approved resolved URL instead of re-prompting on that alias mismatch.
        return approved.url
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
        folders = records.compactMap { record in
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: record.bookmark, options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale else {
                    note = "A saved folder needs approval again. Choose it with Add Folder."
                    return nil
                }
                return RoomAccessFolder(id: record.id, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, url: url)
            } catch {
                note = "A saved folder is unavailable. Choose it again to renew access."
                return nil
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
