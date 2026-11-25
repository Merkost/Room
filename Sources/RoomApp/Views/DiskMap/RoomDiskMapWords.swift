import Foundation

/// Disk Map's headline (nav-v3): "430 GB in your home", or "120 GB in Developer" one level in.
nonisolated struct RoomDiskMapWords: Equatable, Sendable {
    let headline: RoomHeadline
    let supporting: String

    static func isHome(_ url: URL) -> Bool {
        url.standardizedFileURL.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    static func make(levelName: String, atRoot: Bool, rootIsHome: Bool, bytes: Int64, partial: Bool, folders: Int,
                     scannedAt: Date, now: Date) -> RoomDiskMapWords {
        let figure = partial ? RoomFormat.lowerBound(bytes) : RoomFormat.gb(bytes)
        let headline: RoomHeadline = atRoot && rootIsHome
            ? RoomHeadline(figure: figure, words: "in your home")
            : RoomHeadline(figure: figure, words: "in \(levelName)", masksWords: true)
        let count = folders == 1 ? "1 folder" : "\(folders) folders"
        let supporting = atRoot ? "\(count), mapped \(when(scannedAt, now: now))" : "\(count) inside"
        return RoomDiskMapWords(headline: headline, supporting: supporting)
    }

    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        return "on \(date.formatted(.dateTime.day().month(.wide)))"
    }
}
