import Foundation

/// Room's places in order, with their glyphs and ⌘ numbers. Five stand in the dock; History and Settings sit in the
/// top bar.
nonisolated enum RoomPlacePlan {
    static let places: [RoomDestination] = [.overview, .disk, .clean, .developer, .memory, .history, .settings]

    static let dock: [RoomDestination] = [.overview, .disk, .clean, .developer, .memory]

    /// ⌘1 … ⌘7, in this order.
    static func shortcut(_ place: RoomDestination) -> Int { (places.firstIndex(of: place) ?? 0) + 1 }

    static func place(forShortcut number: Int) -> RoomDestination? {
        places.indices.contains(number - 1) ? places[number - 1] : nil
    }

    static func glyph(_ place: RoomDestination) -> RoomGlyph {
        switch place {
        case .overview: .overview
        case .disk: .diskMap
        case .clean: .caches
        case .developer: .developer
        case .memory: .memory
        case .history: .history
        case .settings: .settings
        }
    }

    static func title(_ place: RoomDestination) -> String {
        switch place {
        case .overview: String(localized: "menu.overview", defaultValue: "Overview", bundle: RoomCopy.bundle)
        case .disk: String(localized: "menu.disk", defaultValue: "Disk Map", bundle: RoomCopy.bundle)
        case .clean: String(localized: "menu.caches", defaultValue: "Caches", bundle: RoomCopy.bundle)
        case .developer: String(localized: "menu.developer", defaultValue: "Developer", bundle: RoomCopy.bundle)
        case .memory: String(localized: "menu.memory", defaultValue: "Memory", bundle: RoomCopy.bundle)
        case .history: String(localized: "menu.history", defaultValue: "History", bundle: RoomCopy.bundle)
        case .settings: String(localized: "menu.settingsScreen", defaultValue: "Settings", bundle: RoomCopy.bundle)
        }
    }

    /// The next place for ← / →, clamped at the ends.
    static func step(from place: RoomDestination, by offset: Int) -> RoomDestination {
        let index = places.firstIndex(of: place) ?? 0
        return places[min(places.count - 1, max(0, index + offset))]
    }
}

/// The one figure per place. Sizes go through `RoomFormat.gb`; the view masks them with Hide.
nonisolated enum RoomPlaceValue: Equatable, Sendable {
    case none
    case size(String)          // a size: Hide masks it
    case words(String)         // a count or a word: not a size

    struct Input: Equatable, Sendable {
        var freeBytes: Int64?
        var mappedBytes: Int64?
        var cachesChecked = false
        var cachesReclaimableBytes: Int64 = 0
        var developerBytes: Int64?
        var memoryUsedBytes: Int64?
        var receipts = 0
    }

    static func make(_ place: RoomDestination, _ input: Input) -> RoomPlaceValue {
        switch place {
        case .overview:
            return input.freeBytes.map { .size(RoomFormat.gb($0)) } ?? .none
        case .disk:
            guard let bytes = input.mappedBytes, bytes > 0 else { return .none }
            return .size(RoomFormat.gb(bytes))
        case .clean:
            guard input.cachesChecked else { return .none }
            return input.cachesReclaimableBytes > 0
                ? .size(RoomFormat.gb(input.cachesReclaimableBytes))
                : .words(String(localized: "nav.value.clear", defaultValue: "Clear", bundle: RoomCopy.bundle))
        case .developer:
            guard let bytes = input.developerBytes, bytes > 0 else { return .none }
            return .size(RoomFormat.gb(bytes))
        case .memory:
            guard let used = input.memoryUsedBytes, used > 0 else { return .none }
            return .size(RoomFormat.memory(used))
        case .history:
            guard input.receipts > 0 else { return .none }
            return .words(input.receipts == 1
                ? String(localized: "nav.value.receipt", defaultValue: "1 receipt", bundle: RoomCopy.bundle)
                : String(localized: "nav.value.receipts", defaultValue: "\(input.receipts) receipts", bundle: RoomCopy.bundle))
        case .settings:
            return .none
        }
    }
}

/// The footer meter: used space in ink, what Make room would give back in the accent, free space as the track.
nonisolated struct RoomNameplateMeter: Equatable, Sendable {
    let used: Double
    let couldGo: Double
    let free: Double

    static func make(capacityBytes: Int64?, freeBytes: Int64?, couldGoBytes: Int64) -> RoomNameplateMeter? {
        guard let capacity = capacityBytes, let free = freeBytes, capacity > 0, free >= 0, free <= capacity else { return nil }
        let used = capacity - free
        let could = min(max(0, couldGoBytes), used)
        let total = Double(capacity)
        return RoomNameplateMeter(used: Double(used - could) / total, couldGo: Double(could) / total,
                                  free: Double(free) / total)
    }
}
