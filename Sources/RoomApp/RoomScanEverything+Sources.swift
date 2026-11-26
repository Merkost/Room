import Foundation
import RoomCore

/// The four reads behind "Scan everything". Each one is the same call its own screen makes.
extension RoomScanEverything {
    static func sources(cache: RoomViewModel, insights: RoomInsightsModel,
                        developer: RoomDeveloperModel) -> [Part: Source] {
        [.caches: caches(cache), .disk: disk(insights), .developer: self.developer(developer),
         .memory: memory(insights)]
    }

    private static func caches(_ model: RoomViewModel) -> Source {
        Source(unavailable: {
            #if ROOM_APP_STORE
            if model.approvedStoreFolderCount == 0 { return "Choose a folder in Caches" }
            #endif
            return model.isScanning || model.canScan ? nil : "Busy right now"
        }, start: model.scan, stop: model.cancelScan, read: { _ in
            let counted = model.scanLocationCount > 0
            let unreadable = model.measuredSourceCount > 0 && model.readableSourceCount == 0
            return Reading(
                running: model.isScanning, finished: model.hasReport,
                problem: !model.isScanning && model.hasReport && unreadable ? "Couldn’t read" : nil,
                fraction: counted ? Double(model.scannedLocationCount) / Double(model.scanLocationCount) : nil,
                detail: counted ? "\(model.scannedLocationCount) of \(model.scanLocationCount) places" : "Finding places",
                figure: model.clearableBytes > 0 ? "\(RoomFormat.gb(model.clearableBytes)) could go" : "All clear")
        })
    }

    private static func disk(_ insights: RoomInsightsModel) -> Source {
        Source(unavailable: {
            if insights.isScanningDisk { return insights.isMappingHome ? nil : "Mapping another folder" }
            return insights.canChooseDiskLocation ? nil : "Busy right now"
        }, start: { if !insights.isScanningDisk { insights.scanHome() } },
           stop: { if insights.isMappingHome { insights.cancelDiskScan() } }, read: { since in
            let blueprint = insights.diskMap.blueprint
            let total = blueprint?.topLevelTotal ?? 0
            let measured = blueprint?.measuredCount ?? 0
            // Only a Home map counts: another folder mapped meanwhile belongs to Disk Map, not to this room.
            let report = insights.diskReport.flatMap { insights.isHomeFolder($0.url) ? $0 : nil }
            let fresh = report.map { $0.scannedAt >= since && !$0.cancelled } ?? false
            return Reading(
                running: insights.isScanningDisk && insights.isMappingHome, pending: insights.isChoosingDiskFolder && !insights.isScanningDisk,
                finished: fresh, fraction: total > 0 ? Double(measured) / Double(total) : nil,
                detail: total > 0 ? "\(measured) of \(total) folders" : "Mapping",
                figure: report.map { RoomFormat.gb($0.allocatedBytes) })
        })
    }

    private static func developer(_ model: RoomDeveloperModel) -> Source {
        Source(unavailable: {
            model.isScanning || model.canScan ? nil : "Add a folder in Developer"
        }, start: model.scan, stop: model.stop, read: { _ in
            let parts = model.scanTiles
            let done = parts.filter { $0.state == .done }.count
            return Reading(
                running: model.isScanning,
                finished: !parts.isEmpty && done == parts.count,
                fraction: parts.isEmpty ? nil : Double(done) / Double(parts.count),
                detail: parts.first(where: \.isReading).map { "Reading \($0.title.lowercased())" } ?? "Reading",
                // With no folders set up only the worktrees are read, and the folder total would say zero.
                figure: model.scanParts.isEmpty ? model.worktrees?.measuredBytes.map { RoomFormat.gb($0) } ?? "Read"
                    : RoomFormat.gb(model.headline.total))
        })
    }

    private static func memory(_ insights: RoomInsightsModel) -> Source {
        Source(unavailable: { nil }, start: insights.scanMemory, stop: {}, read: { since in
            let report = insights.memoryReport
            return Reading(
                running: insights.isScanningMemory,
                finished: report.map { $0.scannedAt >= since && $0.totalBytes > 0 } ?? false,
                detail: "Reading memory",
                figure: report.map { "\(RoomFormat.memory($0.usedBytes)) in use" })
        })
    }
}
