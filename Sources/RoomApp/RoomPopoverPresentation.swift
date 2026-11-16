import Foundation

/// The popover's text, accessibility labels and geometry, shared by the view and its fixtures.
nonisolated struct RoomPopoverPresentation: Equatable, Sendable {
    nonisolated struct Disk: Equatable, Sendable {
        let value: String
        let caption: String
        let goalCaption: String?
        let usedFraction: Double?
        let goalFraction: Double?
        let belowGoal: Bool
        let accessibilityLabel: String
    }

    nonisolated struct Memory: Equatable, Sendable {
        let value: String
        let caption: String
        let status: String?
        let pocketFill: Double?
        let pressure: RoomMenuBarPressure
        let swapCaption: String?
        let accessibilityLabel: String
    }

    nonisolated struct Card: Equatable, Sendable {
        let title: String
        let caption: String
        let accessory: String?
        let accessibilityLabel: String
    }

    static let title = "Room"
    static let settingsTitle = "Settings"
    static let openRoomTitle = "Open Room"
    static let quitTitle = "Quit"

    let disk: Disk
    let memory: Memory
    let caches: Card?
    let room: Card

    /// In the frozen string-audit order, including the gear's label and tooltip once.
    var strings: [String] {
        var strings = [Self.title, Self.settingsTitle, disk.value, disk.caption]
        if let goal = disk.goalCaption { strings.append(goal) }
        strings += [memory.value, memory.caption]
        if let status = memory.status { strings.append(status) }
        if let swap = memory.swapCaption { strings.append(swap) }
        if let caches {
            strings += [caches.title, caches.caption]
            if let accessory = caches.accessory { strings.append(accessory) }
        }
        strings += [room.title, room.caption]
        if let accessory = room.accessory { strings.append(accessory) }
        return strings + [Self.openRoomTitle, Self.quitTitle]
    }

    static func make(input: RoomMenuBarInput, diskCapacityBytes: Int64,
                     swapBytes: Int64? = nil, showSwap: Bool = false,
                     caches: RoomCachesCheck? = nil, room: RoomRoomsModel.State = .empty,
                     now: Date = Date(), calendar: Calendar = .current,
                     format: RoomMenuBarFormat, formatSize: (Int64) -> String) -> Self {
        Self(disk: disk(input: input, capacity: diskCapacityBytes, format: format.disk),
             memory: memory(input: input, swapBytes: swapBytes, showSwap: showSwap, format: format.memory),
             caches: caches.map { check in
                 let title = check.title(format: formatSize)
                 let caption = check.caption(now: now, calendar: calendar)
                 return Card(title: title, caption: caption, accessory: "Open Caches",
                             accessibilityLabel: "\(spoken(title)), \(lowercasingFirst(caption)). Open Caches.")
             },
             room: roomCard(room, now: now, calendar: calendar, format: formatSize))
    }

    private static func disk(input: RoomMenuBarInput, capacity: Int64, format: (Int64) -> String) -> Disk {
        let hasGoal = input.goalBytes > 0
        let goalCaption = hasGoal ? "Goal: keep \(format(input.goalBytes)) free" : nil
        guard capacity > 0, let measuredFree = input.diskFreeBytes else {
            return Disk(value: "—", caption: "Free space unavailable", goalCaption: goalCaption,
                        usedFraction: nil, goalFraction: nil, belowGoal: false,
                        accessibilityLabel: "Free space unavailable. Open Disk Map.")
        }
        let free = max(0, min(capacity, measuredFree))
        let goalFraction = hasGoal ? max(0, min(1, 1 - Double(input.goalBytes) / Double(capacity))) : nil
        let goalSpoken = hasGoal ? ", goal \(number(in: format(input.goalBytes)))" : ""
        return Disk(value: "\(format(free)) free", caption: "of \(format(capacity))", goalCaption: goalCaption,
                    usedFraction: max(0, min(1, 1 - Double(free) / Double(capacity))),
                    goalFraction: goalFraction, belowGoal: hasGoal && free < input.goalBytes,
                    accessibilityLabel: "Free space, \(spoken(format(free))) of \(number(in: format(capacity)))\(goalSpoken). Open Disk Map.")
    }

    private static func memory(input: RoomMenuBarInput, swapBytes: Int64?, showSwap: Bool,
                               format: (Int64) -> String) -> Memory {
        guard let total = input.memoryTotalBytes, total > 0, let measuredUsed = input.memoryUsedBytes else {
            return Memory(value: "—", caption: "Memory measurement unavailable", status: nil,
                          pocketFill: nil, pressure: .unknown, swapCaption: nil,
                          accessibilityLabel: "Memory measurement unavailable. Open Memory.")
        }
        let used = max(0, min(total, measuredUsed))
        let status: String
        let fill: Double?
        switch input.pressure {
        case .normal: status = "Normal"; fill = 0
        case .elevated: status = "Elevated"; fill = 0.5
        case .critical: status = "Critical"; fill = 1
        case .unknown: status = "—"; fill = nil
        }
        let swapCaption = showSwap ? swapBytes.map { "\(format(max(0, $0))) swap used" } : nil
        var detail = input.pressure == .unknown ? "pressure unavailable" : "\(status) pressure"
        if let swapCaption { detail += ", \(spoken(swapCaption))" }
        return Memory(value: format(used), caption: "of \(format(total)) memory", status: status,
                      pocketFill: fill, pressure: input.pressure, swapCaption: swapCaption,
                      accessibilityLabel: "Memory, \(spoken(format(used))) of \(number(in: format(total))), \(detail). Open Memory.")
    }

    private static func roomCard(_ state: RoomRoomsModel.State, now: Date, calendar: Calendar,
                                 format: (Int64) -> String) -> Card {
        switch state {
        case .empty:
            return Card(title: "Pin a folder", caption: "See how much it grows each week", accessory: "Pin a Folder…",
                        accessibilityLabel: "Pin a folder. See how much it grows each week.")
        case let .measuring(room):
            return measuring(room)
        case .unavailable:
            return Card(title: "Room can't read this folder", caption: "Pin it again", accessory: nil,
                        accessibilityLabel: "Room can't read this folder. Pin it again.")
        case let .measured(room, log):
            guard let latest = log.latest else { return measuring(room) }
            let partial = latest.partial || log.change(now: now, calendar: calendar) == .partial
            let size = partial ? "≥ \(format(latest.bytes))" : log.sizeText(format: format)
            // A partial baseline also makes the card incomplete; the frozen log stays unchanged.
            let caption = partial ? "Some folders could not be read"
                : log.caption(now: now, calendar: calendar, format: format)
            return Card(title: room.name, caption: caption, accessory: size,
                        accessibilityLabel: "\(room.name), \(spoken(size)), \(lowercasingFirst(spoken(caption))). Open in Disk Map.")
        }
    }

    private static func measuring(_ room: RoomPinnedRoom) -> Card {
        Card(title: room.name, caption: "Measuring…", accessory: "—",
             accessibilityLabel: "\(room.name), measuring. Open in Disk Map.")
    }

    private static func number(in amount: String) -> String {
        guard let separator = amount.lastIndex(where: \.isWhitespace) else { return amount }
        return String(amount[..<separator])
    }

    private static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func spoken(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        if text.hasPrefix("≥ ") { text = "at least " + text.dropFirst(2) }
        if text.hasPrefix("+") { text = "plus " + text.dropFirst() }
        if text.hasPrefix("−") { text = "minus " + text.dropFirst() }
        for (unit, name) in [("KB", "kilobytes"), ("MB", "megabytes"), ("GB", "gigabytes"),
                             ("TB", "terabytes"), ("PB", "petabytes"), ("EB", "exabytes"), ("B", "bytes")] {
            text = text.replacingOccurrences(of: " \(unit)", with: " \(name)")
        }
        return text
    }
}
