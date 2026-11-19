import Foundation

nonisolated enum RoomSignature: Equatable, Sendable {
    case hidden
    case moved(bytes: Int64, cleanups: Int, since: Date)
    case made(bytes: Int64, cleanups: Int, since: Date)

    static func make(ledgerMadeBytes: Int64?, ledgerCleanups: Int, ledgerSince: Date?,
                     movedKeptBytes: Int64, movedCleanups: Int, movedSince: Date?) -> Self {
        if let made = ledgerMadeBytes {
            guard made > 0, ledgerCleanups > 0, let since = ledgerSince else { return .hidden }
            return .made(bytes: made, cleanups: ledgerCleanups, since: since)
        }
        guard movedKeptBytes > 0, movedCleanups > 0, let since = movedSince else { return .hidden }
        return .moved(bytes: movedKeptBytes, cleanups: movedCleanups, since: since)
    }

    func caption(month: String) -> String? {
        let count: Int
        let key: String
        let prefix: String
        switch self {
        case .hidden: return nil
        case .moved(_, let cleanups, _):
            count = cleanups
            key = "settings.about.moved"
            prefix = "moved to Trash"
        case .made(_, let cleanups, _):
            count = cleanups
            key = "settings.about.made"
            prefix = "of room made"
        }
        let fallback = count == 1 ? "\(prefix) since %1$@, across %2$lld cleanup" : "\(prefix) since %1$@, across %2$lld cleanups"
        let format = RoomCopy.bundle.localizedString(forKey: key, value: fallback, table: nil)
        return String.localizedStringWithFormat(format, month, Int64(count))
    }
}
