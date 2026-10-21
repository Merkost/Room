#if ROOM_APP_STORE
import AppKit
import Darwin
import Foundation
import Observation
import RoomCore

/// Account metadata identifies the real home; it never grants access to it.
@MainActor
enum RoomStoreEnvironment {
    static var userHome: URL? {
        guard let record = getpwuid(getuid()), let value = record.pointee.pw_dir else { return nil }
        let path = String(cString: value)
        guard path.hasPrefix("/"), path != "/" else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var activityDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Room/Activity", isDirectory: true)
    }
}

/// A native write approval is bound to an exact physical directory and one review.
/// No writable bookmark is created or stored.
@Observable @MainActor
final class RoomStoreFolderReview {
    struct DirectoryIdentity: Equatable {
        let device: Int32
        let inode: UInt64
        let owner: UInt32
        let mode: UInt16
    }
    private(set) var locations: [URL] = []
    private(set) var grantedPaths: Set<String> = []
    private(set) var trashPaths: Set<String> = []
    @ObservationIgnored private var identities: [String: DirectoryIdentity] = [:]
    @ObservationIgnored private var grants: [String: (url: URL, scoped: Bool)] = [:]
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let picker: @MainActor (URL, Bool) async -> URL?
    @ObservationIgnored private let beginScope: @MainActor (URL) -> Bool
    @ObservationIgnored private let endScope: @MainActor (URL) -> Void

    var allGranted: Bool { !locations.isEmpty && locations.allSatisfy { grantedPaths.contains($0.path) } }

    init(picker: (@MainActor (URL, Bool) async -> URL?)? = nil,
         beginScope: @escaping @MainActor (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         endScope: @escaping @MainActor (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.picker = picker ?? { expected, allowsFiles in
            await RoomNativeFolderPicker.shared.choose(title: "Allow this reviewed change",
                message: "Choose exactly \(expected.path). Room uses this write approval only for the current review and does not save it. Allowing access does not move files.",
                prompt: allowsFiles ? "Allow This Item" : "Allow This Folder", initialURL: expected, allowsFiles: allowsFiles)
        }
        self.beginScope = beginScope
        self.endScope = endScope
    }

    func prepare(_ urls: [URL], recordedDirectories: [(url: URL, identity: FileIdentity)] = [],
                 trashItems: [(url: URL, identity: FileIdentity)] = []) throws {
        discard()
        let unique = Dictionary(grouping: urls, by: \.path).compactMap { $0.value.first }.sorted { $0.path < $1.path }
        var expected: [String: DirectoryIdentity] = [:]
        for url in unique { expected[url.path] = try Self.identity(url) }
        var allLocations = unique
        // Receipt-backed identity lets a native picker re-authorize the exact
        // original parent even after its remembered read bookmark was removed.
        for item in recordedDirectories where expected[item.url.path] == nil {
            guard item.identity.mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { throw RoomStoreAccessError.reviewChanged }
            expected[item.url.path] = DirectoryIdentity(device: Int32(truncatingIfNeeded: item.identity.device),
                inode: item.identity.inode, owner: getuid(), mode: item.identity.mode)
            allLocations.append(item.url)
        }
        for item in trashItems where expected[item.url.path] == nil {
            expected[item.url.path] = DirectoryIdentity(device: Int32(truncatingIfNeeded: item.identity.device),
                inode: item.identity.inode, owner: getuid(), mode: item.identity.mode)
            allLocations.append(item.url)
        }
        identities = expected
        trashPaths = Set(trashItems.map { $0.url.path })
        locations = allLocations
    }

    func allow(_ expected: URL) async throws {
        guard let expectedIdentity = identities[expected.path] else { throw RoomStoreAccessError.reviewChanged }
        let token = generation
        guard let selected = await picker(expected, trashPaths.contains(expected.path)) else { return }
        guard token == generation, identities[expected.path] == expectedIdentity else { return }
        let scoped = beginScope(selected)
        do {
            guard try Self.identity(expected, allowsFile: trashPaths.contains(expected.path)) == expectedIdentity,
                  try Self.identity(selected, allowsFile: trashPaths.contains(expected.path)) == expectedIdentity else {
                throw RoomStoreAccessError.exactFolderRequired
            }
        } catch {
            if scoped { endScope(selected) }
            throw error
        }
        if let prior = grants.removeValue(forKey: expected.path), prior.scoped { endScope(prior.url) }
        grants[expected.path] = (selected, scoped)
        grantedPaths.insert(expected.path)
    }

    func validate(exactly urls: [URL]) throws {
        let paths = Set(urls.map(\.path))
        guard !paths.isEmpty, paths == Set(locations.map(\.path)), allGranted else { throw RoomStoreAccessError.approvalRequired }
        for url in locations {
            guard let identity = identities[url.path], let grant = grants[url.path],
                  try Self.identity(url, allowsFile: trashPaths.contains(url.path)) == identity,
                  try Self.identity(grant.url, allowsFile: trashPaths.contains(url.path)) == identity else { throw RoomStoreAccessError.reviewChanged }
        }
    }

    var approvedTrashItems: [URL] {
        trashPaths.compactMap { grants[$0]?.url }
    }

    func discard() {
        generation = UUID()
        for grant in grants.values where grant.scoped { endScope(grant.url) }
        grants = [:]
        grantedPaths = []
        identities = [:]
        locations = []
        trashPaths = []
    }

    private static func identity(_ url: URL, allowsFile: Bool = false) throws -> DirectoryIdentity {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR)
               || (allowsFile && info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG) && info.st_nlink == 1)) else {
            throw RoomStoreAccessError.exactFolderRequired
        }
        return DirectoryIdentity(device: info.st_dev, inode: info.st_ino, owner: info.st_uid, mode: info.st_mode)
    }
}

enum RoomStoreAccessError: LocalizedError {
    case approvalRequired, exactFolderRequired, reviewChanged, homeUnavailable
    var errorDescription: String? {
        switch self {
        case .approvalRequired: "Approve every exact folder in this review before changing files. Nothing moved."
        case .exactFolderRequired: "Choose the exact owned folder shown in the review. Parent folders, links and lookalikes are not accepted."
        case .reviewChanged: "The review or a folder changed. Review the current selection again before changing files."
        case .homeUnavailable: "The account home could not be identified. No storage locations were inspected."
        }
    }
}
#endif
