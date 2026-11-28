import Foundation
import RoomCore

/// Which Developer views have something to show. Rooms and Matrix share one review scan.
struct RoomDeveloperAvailability: Equatable {
    var review = false
    var devices = false
    var storage = false
    var aiTools = false
    var worktrees = false

    var sectionsWithData: Set<RoomDeveloperSection> {
        var result: Set<RoomDeveloperSection> = []
        if review { result.formUnion([.rooms, .matrix]) }
        if devices { result.insert(.devices) }
        if storage { result.insert(.storage) }
        if aiTools { result.insert(.aiTools) }
        #if !ROOM_APP_STORE
        if worktrees { result.insert(.worktrees) }
        #endif
        return result
    }
}

/// Tabs appear only once there is data to switch between (the first scan decides).
enum RoomDeveloperTabRules {
    static func visible(_ availability: RoomDeveloperAvailability, current: RoomDeveloperSection) -> [RoomDeveloperSection] {
        let withData = availability.sectionsWithData
        if withData.isEmpty { return current == .rooms ? [] : RoomDeveloperSection.allCases }
        return RoomDeveloperSection.allCases.filter { withData.contains($0) || $0 == current }
    }

    static func hidden(_ availability: RoomDeveloperAvailability, current: RoomDeveloperSection) -> [RoomDeveloperSection] {
        let shown = visible(availability, current: current)
        return shown.isEmpty ? [] : RoomDeveloperSection.allCases.filter { !shown.contains($0) }
    }

    /// Before any data and while on the default view the screen is the quiet start page.
    static func showsIntro(_ availability: RoomDeveloperAvailability, current: RoomDeveloperSection, isScanning: Bool) -> Bool {
        visible(availability, current: current).isEmpty && !isScanning
    }
}

/// The one number that matters, and the parts it is made of.
struct RoomDeveloperHeadline: Equatable {
    enum Kind: CaseIterable { case inUse, unreferenced, devices, toolStorage, aiTools }
    struct Part: Equatable, Identifiable {
        let kind: Kind
        let bytes: Int64
        var id: Kind { kind }
    }

    let parts: [Part]
    let partial: Bool

    var total: Int64 { RoomDeveloperPresentation.sum(parts.map(\.bytes)) }
    var unreferenced: Int64 { parts.first { $0.kind == .unreferenced }?.bytes ?? 0 }
    var isEmpty: Bool { total == 0 }

    init(inUse: Int64 = 0, unreferenced: Int64 = 0, devices: Int64 = 0, toolStorage: Int64 = 0,
         aiTools: Int64 = 0, partial: Bool = false) {
        let all: [Part] = [.init(kind: .inUse, bytes: inUse), .init(kind: .unreferenced, bytes: unreferenced),
                           .init(kind: .devices, bytes: devices), .init(kind: .toolStorage, bytes: toolStorage),
                           .init(kind: .aiTools, bytes: aiTools)]
        parts = all.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        self.partial = partial
    }

    /// Fractions of the whole for the breakdown bar; each part keeps a visible sliver.
    func fractions(minimum: Double = 0.02) -> [Double] {
        let total = Double(max(1, total))
        return parts.map { max(minimum, Double($0.bytes) / total) }
    }

    var hasAnyData: Bool { !parts.isEmpty }
}

extension RoomDevPinKind {
    /// Short legend label so an entry never wraps.
    var legendTitle: String { self == .derivedData ? "DerivedData" : title }
}

enum RoomDeveloperFormat {
    /// Whole units for rows ("12 GB", "480 MB"). The hero figure alone keeps a decimal.
    static func whole(_ bytes: Int64, partial: Bool = false) -> String {
        let text = RoomFormat.gb(max(0, bytes))
        return partial ? RoomFormat.lowerBound(text) : text
    }
}

enum RoomDeveloperList {
    static let collapsedLimit = 8

    /// Largest first; ties fall back to the name so the order never jumps between scans.
    static func bySize<T>(_ items: [T], bytes: (T) -> Int64, name: (T) -> String) -> [T] {
        items.sorted {
            let (a, b) = (bytes($0), bytes($1))
            return a == b ? name($0).localizedStandardCompare(name($1)) == .orderedAscending : a > b
        }
    }

    static func byName<T>(_ items: [T], name: (T) -> String) -> [T] {
        items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }

    static func visible<T>(_ items: [T], expanded: Bool, limit: Int = collapsedLimit) -> (shown: [T], hidden: Int) {
        guard !expanded, items.count > limit + 1 else { return (items, 0) }
        return (Array(items.prefix(limit)), items.count - limit)
    }

    struct Group<Item> {
        let key: String
        let bytes: Int64
        let items: [Item]
    }

    /// Groups keep their items largest first and sit largest group first.
    static func grouped<T>(_ items: [T], key: (T) -> String, bytes: (T) -> Int64, name: (T) -> String) -> [Group<T>] {
        Dictionary(grouping: items, by: key).map { key, values in
            Group(key: key, bytes: RoomDeveloperPresentation.sum(values.map(bytes)),
                  items: bySize(values, bytes: bytes, name: name))
        }.sorted { $0.bytes == $1.bytes ? $0.key < $1.key : $0.bytes > $1.bytes }
    }

    /// Bar widths as a share of the full width: the largest item fills it, the rest are proportional, and
    /// anything with data keeps a visible sliver. Zero or negative sizes stay empty; no item gives no fractions.
    static func barFractions(_ sizes: [Int64], minimum: Double = 0.03) -> [Double] {
        let largest = sizes.max() ?? 0
        guard largest > 0 else { return sizes.map { _ in 0 } }
        return sizes.map { $0 > 0 ? max(minimum, Double($0) / Double(largest)) : 0 }
    }

    /// Rows arrive in order as results appear; the stagger stops growing after `maxStaggered`.
    static func staggerDelay(index: Int) -> TimeInterval {
        Double(min(max(0, index), RoomTokens.Motion.maxStaggered)) * RoomTokens.Motion.stagger
    }
}

extension RoomDeveloperModel {
    var availability: RoomDeveloperAvailability {
        RoomDeveloperAvailability(review: report != nil, devices: devicesReport != nil,
                                  storage: storageReport != nil, aiTools: aiToolsReport != nil)
    }

    /// The figure the Developer screen's headline shows for a room, so the sidebar value matches the screen it opens
    /// ("120 GB in projects" on Rooms and Matrix, the devices, storage, AI tools or worktrees total elsewhere).
    func headlineBytes(for section: RoomDeveloperSection, worktreesBytes: Int64 = 0) -> Int64 {
        let headline = headline
        func part(_ kind: RoomDeveloperHeadline.Kind) -> Int64 { headline.parts.first { $0.kind == kind }?.bytes ?? 0 }
        switch section {
        case .rooms, .matrix: return part(.inUse) + part(.unreferenced)
        case .devices: return part(.devices)
        case .storage: return part(.toolStorage)
        case .aiTools: return part(.aiTools)
        #if !ROOM_APP_STORE
        case .worktrees: return worktreesBytes
        #endif
        }
    }

    var headline: RoomDeveloperHeadline {
        let reports = [report, devicesReport, storageReport, aiToolsReport].compactMap { $0 }
        let partial = (summary?.partial ?? false) || reports.contains { $0.isPartial || $0.cancelled }
            || (storageReport?.storageResources.contains(where: \.isPartial) ?? false)
            || (aiToolsReport?.aiStorageResources.contains(where: \.isPartial) ?? false)
        let devices = (devicesReport?.androidDevices.map(\.allocatedBytes) ?? [])
            + (devicesReport?.simulatorDevices.map(\.allocatedBytes) ?? [])
        return RoomDeveloperHeadline(
            inUse: summary?.pinnedBytes ?? 0, unreferenced: summary?.orphanBytes ?? 0,
            devices: RoomDeveloperPresentation.sum(devices),
            toolStorage: RoomDeveloperPresentation.sum(storageReport?.storageResources.map(\.allocatedBytes) ?? []),
            aiTools: RoomDeveloperPresentation.sum(aiToolsReport?.aiStorageResources.map(\.allocatedBytes) ?? []),
            partial: partial)
    }
}
