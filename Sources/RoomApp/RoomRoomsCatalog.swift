import CoreGraphics
import Foundation

/// Spec 02 §9: the twelve Room glyphs (SF Symbols).
nonisolated enum RoomRoomGlyph: String, CaseIterable, Codable, Sendable {
    case folder, hammer, iphone, shippingbox, photo, film
    case musicNote = "music.note", doc, booksVertical = "books.vertical", externaldrive, cube, leaf
}

/// Spec 12 PE-7: seven colours, the kind label hues (app `RoomTokens.Kind` raw values). Data labels, not accents.
nonisolated enum RoomRoomColour: String, CaseIterable, Codable, Sendable {
    case developer, media, documents, apps, archives, system, hidden
}

// MARK: - Lossy decoding: one damaged entry must not drop every Room

nonisolated enum RoomRoomsDecoding {
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    /// nil only when the file is not a JSON array at all (the store then starts empty, as today).
    static func rooms(from data: Data) -> [RoomPinnedRoom]? {
        guard let items = try? JSONDecoder().decode([Lossy<RoomPinnedRoom>].self, from: data) else { return nil }
        return items.compactMap(\.value)
    }
}

// MARK: - Catalogue operations (all return a normalized array: sorted by order, unique ids, order 0..n-1, ≤ 64)

nonisolated enum RoomRoomsCatalog {
    static let maximumRooms = 64
    static let maximumNameLength = 80
    static let minimumBudgetGB = 1, maximumBudgetGB = 9_999
    static let bytesPerGB: Int64 = 1_000_000_000

    enum AddResult: Equatable, Sendable {
        case added([RoomPinnedRoom], RoomPinnedRoom)
        case alreadyPinned(UUID)          // same approved folder: select it, never a duplicate row
        case full
    }

    static func normalized(_ rooms: [RoomPinnedRoom]) -> [RoomPinnedRoom] {
        var ids: Set<UUID> = []
        let sorted = rooms.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        return sorted.filter { ids.insert($0.id).inserted }.prefix(maximumRooms).enumerated().map { index, room in
            var room = room; room.order = index; return room
        }
    }

    /// Pinning ADDS a Room (today's single-Room model replaces rooms[0]). Appended last, so the popover's Room
    /// (the first by order) does not change under the person.
    static func add(_ rooms: [RoomPinnedRoom], id: UUID, accessFolderID: String, name: String,
                    glyph: RoomRoomGlyph = .folder, colour: RoomRoomColour = .developer) -> AddResult {
        let current = normalized(rooms)
        if let existing = current.first(where: { $0.accessFolderID == accessFolderID }) { return .alreadyPinned(existing.id) }
        guard current.count < maximumRooms else { return .full }
        let room = RoomPinnedRoom(id: id, accessFolderID: accessFolderID, name: cleanName(name) ?? "Folder",
                                  order: current.count, glyph: glyph.rawValue, colour: colour.rawValue)
        return .added(normalized(current + [room]), room)
    }

    static func remove(_ rooms: [RoomPinnedRoom], id: UUID) -> [RoomPinnedRoom] {
        normalized(rooms.filter { $0.id != id })
    }

    static func move(_ rooms: [RoomPinnedRoom], id: UUID, to index: Int) -> [RoomPinnedRoom] {
        var list = normalized(rooms)
        guard let from = list.firstIndex(where: { $0.id == id }) else { return list }
        let room = list.remove(at: from)
        list.insert(room, at: max(0, min(list.count, index)))
        return normalized(list.enumerated().map { var r = $1; r.order = $0; return r })
    }

    /// nil when the new name is empty after trimming: the field keeps the old name.
    static func cleanName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(trimmed))
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maximumNameLength))
    }

    static func rename(_ rooms: [RoomPinnedRoom], id: UUID, to raw: String) -> [RoomPinnedRoom] {
        guard let name = cleanName(raw) else { return normalized(rooms) }
        return normalized(rooms.map { $0.id == id ? { var r = $0; r.name = name; return r }($0) : $0 })
    }

    /// Whole GB 1 … 9 999 (PE-8). nil clears. Out of range is rejected (returns nil), never clamped silently.
    static func budgetBytes(gb: Int?) -> Int64?? {
        guard let gb else { return .some(nil) }
        guard (minimumBudgetGB...maximumBudgetGB).contains(gb) else { return nil }
        return .some(Int64(gb) * bytesPerGB)
    }

    static func setBudget(_ rooms: [RoomPinnedRoom], id: UUID, gb: Int?) -> [RoomPinnedRoom]? {
        guard let bytes = budgetBytes(gb: gb) else { return nil }
        return normalized(rooms.map { $0.id == id ? { var r = $0; r.budgetBytes = bytes; return r }($0) : $0 })
    }

    static func setLook(_ rooms: [RoomPinnedRoom], id: UUID, glyph: RoomRoomGlyph?, colour: RoomRoomColour?) -> [RoomPinnedRoom] {
        normalized(rooms.map { room in
            guard room.id == id else { return room }
            var r = room
            if let glyph { r.glyph = glyph.rawValue }
            if let colour { r.colour = colour.rawValue }
            return r
        })
    }

    /// The popover and Settings › Menu Bar keep showing one Room: the first by order.
    static func popoverRoom(_ rooms: [RoomPinnedRoom]) -> RoomPinnedRoom? { normalized(rooms).first }

    /// Sizes for Rooms that are no longer pinned are dropped (sizes only, never paths).
    static func prunedSizes(_ sizes: [String: RoomSizeLog], rooms: [RoomPinnedRoom]) -> [String: RoomSizeLog] {
        let live = Set(rooms.map(\.id.uuidString))
        return sizes.filter { live.contains($0.key) }
    }
}

// MARK: - Measuring many Rooms: one at a time, oldest first, at most hourly

nonisolated enum RoomRoomsMeasureQueue {
    static let minimumAge: TimeInterval = 3_600

    /// Never-measured Rooms first (by order), then the oldest latest point. Fresh (< 1 h) and unavailable Rooms are
    /// skipped. The caller runs one measurement, then asks again; nothing runs while a cleanup or picker is active.
    static func next(rooms: [RoomPinnedRoom], sizes: [String: RoomSizeLog], unavailable: Set<UUID>, now: Date) -> UUID? {
        let candidates = RoomRoomsCatalog.normalized(rooms).filter { !unavailable.contains($0.id) }
        if let never = candidates.first(where: { sizes[$0.id.uuidString]?.latest == nil }) { return never.id }
        let stale = candidates.compactMap { room -> (RoomPinnedRoom, Date)? in
            guard let at = sizes[room.id.uuidString]?.latest?.at, now.timeIntervalSince(at) >= minimumAge else { return nil }
            return (room, at)
        }
        return stale.min { $0.1 == $1.1 ? $0.0.order < $1.0.order : $0.1 < $1.1 }?.0.id
    }
}

// MARK: - Twelve weeks, trend line and sparkline

nonisolated struct RoomRoomWeek: Equatable, Sendable {
    let weekStart: Date
    let bytes: Int64
    let partial: Bool
}

nonisolated enum RoomRoomWeekly {
    static let weeks = 12

    /// One value per Monday week, oldest first, the current week last. A week without a measurement is nil (a gap,
    /// never 0 and never interpolated). The value is the week's last daily point.
    static func series(_ log: RoomSizeLog, now: Date, calendar: Calendar, weeks: Int = weeks) -> [RoomRoomWeek?] {
        let current = RoomSizeLog.weekStart(containing: now, calendar: calendar)
        return (0..<weeks).reversed().map { back -> RoomRoomWeek? in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: current),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            guard let point = log.points.last(where: { $0.at >= start && $0.at < end && $0.at <= now }) else { return nil }
            return RoomRoomWeek(weekStart: start, bytes: point.bytes, partial: point.partial)
        }
    }

    /// Polyline segments for the 72 × 20 slot; a gap breaks the line. Nothing drawn under two measured weeks.
    /// Vertical span at least 1 GB (RoomSparkline.minimumSpanBytes), inset 2 pt, x spaced over all 12 weeks.
    static func segments(_ weeks: [RoomRoomWeek?], width: Double = 72, height: Double = 20) -> [[CGPoint]] {
        let values = weeks.compactMap { $0?.bytes }
        guard values.count >= 2, weeks.count >= 2, let low = values.min(), let high = values.max() else { return [] }
        let inset = RoomSparkline.inset, minSpan = RoomSparkline.minimumSpanBytes
        var bottom = Double(low), span = Double(high) - Double(low)
        if span < minSpan { bottom = (Double(low) + Double(high)) / 2 - minSpan / 2; span = minSpan }
        var result: [[CGPoint]] = [], run: [CGPoint] = []
        for (i, week) in weeks.enumerated() {
            guard let week else { if !run.isEmpty { result.append(run); run = [] }; continue }
            run.append(CGPoint(x: Double(i) * width / Double(weeks.count - 1),
                               y: height - inset - (Double(week.bytes) - bottom) / span * (height - 2 * inset)))
        }
        if !run.isEmpty { result.append(run) }
        return result
    }
}

nonisolated enum RoomRoomTrend: Equatable, Sendable {
    case change(deltaBytes: Int64, since: String)   // since == "Monday" reads "this week"
    case noChange(since: String)
    case notMeasuredThisWeek
    case notMeasuredYet
    case trackingFromToday
    case partial

    static func make(_ log: RoomSizeLog?, now: Date, calendar: Calendar) -> Self {
        guard let log, let latest = log.latest else { return .notMeasuredYet }
        if latest.at < RoomSizeLog.weekStart(containing: now, calendar: calendar) { return .notMeasuredThisWeek }
        switch log.change(now: now, calendar: calendar) {
        case .tracking: return .trackingFromToday
        case .partial: return .partial
        case let .since(label, delta):
            return abs(delta) < RoomSizeLog.noChangeBytes ? .noChange(since: label) : .change(deltaBytes: delta, since: label)
        }
    }

    /// Board v4 row: "**+3.2 GB** this week". `emphasis` is the part drawn semibold.
    func text(format: (Int64) -> String) -> (emphasis: String?, rest: String) {
        switch self {
        case let .change(delta, since):
            let figure = "\(delta > 0 ? "+" : "−")\(format(abs(delta)))"
            return (figure, since == "Monday" ? " this week" : " since \(since)")
        case let .noChange(since): return (nil, since == "Monday" ? "No change this week" : "No change since \(since)")
        case .notMeasuredThisWeek: return (nil, "Not measured this week")
        case .notMeasuredYet: return (nil, "Not measured yet")
        case .trackingFromToday: return (nil, "Tracking from today")
        case .partial: return (nil, "Some folders could not be read")
        }
    }
}

// MARK: - Budget frame (PAT 7, board v4 `bframeSVG`, 55-patterns.js:241-248). Flat only.

nonisolated struct RoomBudgetFrame: Equatable, Sendable {
    static let frameWidth: CGFloat = 54, originX: CGFloat = 1, originY: CGFloat = 4
    let fill: CGRect          // Room colour fill, radius 2, inside the frame
    let overrun: CGRect?      // Status.elevated, radius 1, runs past the frame to the slot edge at most
    let isOver: Bool
    let frameOpenAtRight: Bool

    static func make(sizeBytes: Int64, budgetBytes: Int64, slot: CGSize = CGSize(width: 72, height: 20)) -> RoomBudgetFrame? {
        guard budgetBytes > 0, sizeBytes >= 0, slot.width > originX + 2, slot.height > 8 else { return nil }
        let ratio = CGFloat(Double(sizeBytes) / Double(budgetBytes))
        let fh = slot.height - 8
        let fw = min(ratio, (slot.width - 2 - originX) / frameWidth) * frameWidth
        let over = ratio > 1
        return RoomBudgetFrame(
            fill: CGRect(x: originX, y: originY, width: min(fw, frameWidth), height: fh),
            overrun: over ? CGRect(x: originX + frameWidth, y: originY, width: fw - frameWidth, height: fh) : nil,
            isOver: over, frameOpenAtRight: over)
    }

    /// VoiceOver / tooltip. A partial size is a lower bound: "left" cannot be promised, "over" is at least.
    static func spoken(name: String, sizeBytes: Int64, partial: Bool, budgetBytes: Int64, format: (Int64) -> String) -> String {
        let size = (partial ? "at least " : "") + format(sizeBytes)
        if sizeBytes > budgetBytes {
            return "\(name): \(size) of a \(format(budgetBytes)) budget, \(partial ? "at least " : "")\(format(sizeBytes - budgetBytes)) over"
        }
        if partial { return "\(name): \(size) of a \(format(budgetBytes)) budget" }
        if sizeBytes == budgetBytes { return "\(name): \(size), at its \(format(budgetBytes)) budget" }
        return "\(name): \(size) of a \(format(budgetBytes)) budget, \(format(budgetBytes - sizeBytes)) left"
    }
}

// MARK: - The Your Rooms chapter (spec 05 §7)

nonisolated struct RoomRoomRow: Equatable, Sendable {
    let id: UUID
    let name: String          // masked under Hide
    let size: String          // "—" unmeasured, "≥ " partial, masked under Hide
    let trendEmphasis: String?
    let trendRest: String
    let budget: RoomBudgetFrame?
    let sparkline: [[CGPoint]] // empty when a budget is shown, or under two measured weeks
    let spoken: String
    let isUnavailable: Bool
}

nonisolated enum RoomRoomsChapter {
    static let visibleRows = 3   // board v4 OV_ROWS

    /// First three by order. A Room being edited in Customise takes the last row while Customise is open (OV-16).
    static func shown(_ rooms: [RoomPinnedRoom], editing: UUID?) -> (rows: [RoomPinnedRoom], more: Int) {
        let all = RoomRoomsCatalog.normalized(rooms)
        var rows = Array(all.prefix(visibleRows))
        if let editing, let room = all.first(where: { $0.id == editing }), !rows.contains(room), !rows.isEmpty {
            rows[rows.count - 1] = room
        }
        return (rows, all.count - rows.count)
    }

    static func hiddenText(_ s: String, lettersToo: Bool) -> String { String(s.map { character in character.isNumber || (lettersToo && character.isLetter) ? "•" : character }) }

    static func row(_ room: RoomPinnedRoom, log: RoomSizeLog?, unavailable: Bool, now: Date, calendar: Calendar,
                    hidden: Bool, format: (Int64) -> String) -> RoomRoomRow {
        let latest = unavailable ? nil : log?.latest
        let trend = unavailable ? RoomRoomTrend.notMeasuredYet : RoomRoomTrend.make(log, now: now, calendar: calendar)
        var (emphasis, rest) = trend.text(format: format)
        if unavailable { emphasis = nil; rest = "Needs access" }
        let size = latest.map { ($0.partial ? "≥ " : "") + format($0.bytes) } ?? "—"
        let frame = room.budgetBytes.flatMap { budget in latest.flatMap { RoomBudgetFrame.make(sizeBytes: $0.bytes, budgetBytes: budget) } }
        let spark = frame == nil && !unavailable ? log.map { RoomRoomWeekly.segments(RoomRoomWeekly.series($0, now: now, calendar: calendar)) } ?? [] : []
        let spoken: String
        if hidden {
            spoken = "Room, name hidden, size hidden. Open in Disk Map."
        } else {
            var parts = [room.name]
            if let latest {
                if let budget = room.budgetBytes {
                    parts = [RoomBudgetFrame.spoken(name: room.name, sizeBytes: latest.bytes, partial: latest.partial,
                                                    budgetBytes: budget, format: format)]
                } else {
                    parts.append((latest.partial ? "at least " : "") + format(latest.bytes))
                }
            } else { parts.append("not measured yet") }
            if case let .change(delta, since) = trend {
                parts.append("\(delta > 0 ? "up" : "down") \(format(abs(delta))) \(since == "Monday" ? "this week" : "since \(since)")")
            } else if latest != nil || unavailable { parts.append(rest.prefix(1).lowercased() + rest.dropFirst()) }
            spoken = parts.joined(separator: ", ") + ". Open in Disk Map."
        }
        return RoomRoomRow(id: room.id,
            name: hidden ? hiddenText(room.name, lettersToo: true) : room.name,
            size: hidden ? hiddenText(size, lettersToo: false) : size,
            trendEmphasis: hidden ? emphasis.map { hiddenText($0, lettersToo: false) } : emphasis,
            trendRest: rest, budget: frame, sparkline: spark, spoken: spoken, isUnavailable: unavailable)
    }
}
