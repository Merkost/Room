import Foundation
import RoomCore

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

    static func visible<T>(_ items: [T], expanded: Bool, limit: Int = collapsedLimit) -> (shown: [T], hidden: Int) {
        guard !expanded, items.count > limit + 1 else { return (items, 0) }
        return (Array(items.prefix(limit)), items.count - limit)
    }
}

extension RoomDeveloperModel {
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

extension RoomDeveloperModel {
    /// One room per part of the scan, each with its size once that part has been read.
    var scanTiles: [RoomScanTile] {
        var tiles = scanParts.map { part in
            let (title, glyph, kinds): (String, RoomGlyph, Set<RoomDeveloperHeadline.Kind>) = switch part.scope {
            case .devices: ("Devices", .phone, [.devices])
            case .toolStorage: ("Storage", .box, [.toolStorage])
            case .aiTools: ("AI tools", .spark, [.aiTools])
            default: ("Projects", .folder, [.inUse, .unreferenced])
            }
            let state: RoomScanTile.State = switch part.state {
            case .waiting: .waiting
            case .reading: .reading(fraction: nil)
            case .done: .done
            case .stopped: .stopped
            }
            var tile = RoomScanTile(id: title, title: title, glyph: glyph, state: state)
            tile.value = RoomFormat.gb(RoomDeveloperPresentation.sum(headline.parts.filter { kinds.contains($0.kind) }.map(\.bytes)))
            tile.detail = Self.scanDetail(state)
            return tile
        }
        if scanIncludedWorktrees {
            // Worktrees are read alongside; a stopped scan marks the other parts, so it marks these too.
            let state: RoomScanTile.State = worktrees?.isScanning == true ? .reading(fraction: nil)
                : !isScanning && progress.hasPrefix("Stopped") ? .stopped : .done
            var tile = RoomScanTile(id: "Worktrees", title: "Worktrees", glyph: .branch, state: state)
            tile.value = worktrees?.measuredBytes.map { RoomFormat.gb($0) } ?? "Read"
            tile.detail = Self.scanDetail(state)
            tiles.append(tile)
        }
        return tiles
    }

    private static func scanDetail(_ state: RoomScanTile.State) -> String {
        switch state {
        case .waiting: "Next"
        case .reading: "Reading"
        case .stopped: "Stopped"
        case .done, .skipped: ""
        }
    }
}
