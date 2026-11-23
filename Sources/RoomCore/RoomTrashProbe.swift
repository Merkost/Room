import Darwin
import Foundation

package nonisolated enum RoomTrashProbe {
    package static func observation(_ receipt: ActivityReceipt, home: URL) -> RoomTrashObservation? {
        RoomTrashPresence.observation(receipt.items.compactMap { item in
            switch item.status {
            case .restored: (item.byteCount, .putBack)
            case .trashed: (item.byteCount, state(of: item, home: home))
            case .pending, .failed: nil
            }
        })
    }

    package static func state(of item: ActivityItem, home: URL) -> RoomTrashItemState {
        #if ROOM_APP_STORE
        RoomTrashPresence.store(bookmark(item.trashAccessBookmark), trashPath: item.trashURL?.path,
            originalPath: item.originalURL.path, trashDirectories: [home.appendingPathComponent(".Trash").path])
        #else
        RoomTrashPresence.direct(hasTrashURL: item.trashURL != nil,
            trash: item.trashURL.map { stat($0) } ?? .missing, original: stat(item.originalURL),
            trashIdentity: item.trashIdentity.map { ($0.device, $0.inode, $0.mode) },
            originalIdentity: (item.originalIdentity.device, item.originalIdentity.inode, item.originalIdentity.mode))
        #endif
    }

    static func stat(_ url: URL) -> RoomStatProbe {
        var attributes = Darwin.stat()
        if lstat(url.path, &attributes) == 0 {
            return .object(device: UInt64(UInt32(bitPattern: attributes.st_dev)), inode: attributes.st_ino, mode: attributes.st_mode)
        }
        let code = errno
        return code == ENOENT || code == ENOTDIR ? .missing : .failed(code)
    }

    #if ROOM_APP_STORE
    private static func bookmark(_ data: Data?) -> RoomBookmarkProbe {
        guard let data else { return .noBookmark }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { return .failed }
            return .resolved(path: url.roomLexicallyNormalized.path)
        } catch CocoaError.fileNoSuchFile {
            return .noSuchFile
        } catch CocoaError.fileReadNoSuchFile {
            return .noSuchFile
        } catch {
            return .failed
        }
    }
    #endif
}
