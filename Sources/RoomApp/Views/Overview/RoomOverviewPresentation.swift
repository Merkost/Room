import CoreGraphics
import Foundation
import RoomCore

/// Only this presentation, never the measured plan input, is exposed to accessibility.
nonisolated struct RoomOverviewPlanPresentation {
    struct Row: Identifiable, Equatable {
        let id: RoomPlanRoom
        let name: String
        let size: String
        let visualSize: String
        let dots: String
        let spoken: String
        let readout: String
    }

    let caption: String
    let accessibilityLabel: String
    let rows: [Row]
    let goalLabel: String?

    init(plan: RoomOverviewPlanInput, hidden: Bool, solidKinds: Bool = false, format: (Int64) -> String) {
        let unit = format(Int64(plan.gbPerDot * 1e9))
        let scale = solidKinds
            ? String(localized: "plan.area", defaultValue: "Area shows storage size", table: "Overview", bundle: RoomCopy.bundle)
            : String(localized: "plan.unit", defaultValue: "1 dot = about \(unit)")
        let captionText = plan.homeKinds.map {
            let day = $0.mappedAt.formatted(.dateTime.day().month())
            return String(localized: "plan.mapped", defaultValue: "\(scale) · mapped \(day)")
        } ?? scale
        caption = Self.visible(captionText, hidden: hidden)
        if hidden {
            accessibilityLabel = String(localized: "plan.a11y.hidden", defaultValue: "Storage plan. Sizes hidden.")
        } else if solidKinds {
            accessibilityLabel = String(localized: "plan.a11y.rooms", defaultValue: "Storage plan. Area shows storage size.", table: "Overview", bundle: RoomCopy.bundle)
        } else {
            accessibilityLabel = String(localized: "plan.a11y", defaultValue: "Storage plan, one dot is about \(unit).")
        }
        let ordered: [(RoomPlanRoom, Int64)] = [(.free, plan.freeBytes), (.notMapped, plan.notMappedBytes)] +
            plan.kindValues.map { (.kind($0.0), Int64(($0.1 * 1e9).rounded())) }
        rows = ordered.filter { $0.0 == .free || $0.1 > 0 }.sorted { $0.1 > $1.1 }.map { id, bytes in
            let mapped = id != .notMapped
            let name: String
            switch id {
            case .free: name = String(localized: "plan.free", defaultValue: "Free")
            case .notMapped: name = String(localized: "plan.notMapped", defaultValue: "Not mapped yet")
            case .kind(let kind): name = StorageKind(rawValue: kind)?.title ?? kind
            }
            let size = format(bytes)
            if hidden {
                let redacted = String(localized: "plan.hidden", defaultValue: "hidden")
                let spoken = String(localized: "plan.row.hidden", defaultValue: "\(name), hidden")
                return Row(id: id, name: name, size: redacted, visualSize: Self.visible(size, hidden: true),
                           dots: "", spoken: spoken, readout: spoken)
            }
            let dots: String
            let spoken: String
            if mapped && solidKinds {
                dots = ""
                spoken = String(localized: "plan.room.area", defaultValue: "\(name), \(size)", table: "Overview", bundle: RoomCopy.bundle)
            } else if mapped {
                let dotsForRoom = RoomPure.dotAlloc([(key: name, gb: Double(bytes) / 1e9)], unit: plan.gbPerDot)[0].dots
                if bytes > 0, dotsForRoom == 0 {
                    dots = String(localized: "plan.underUnit", defaultValue: "under \(unit)")
                } else if dotsForRoom == 0 {
                    dots = String(localized: "plan.noDots", defaultValue: "No dots")
                } else {
                    dots = String(localized: "plan.dotCount", defaultValue: "about \(dotsForRoom) dots")
                }
                spoken = String(localized: "plan.row.free", defaultValue: "\(name), \(size), \(dots)")
            } else {
                dots = String(localized: "plan.notMeasured", defaultValue: "not measured")
                spoken = String(localized: "plan.row.notMapped", defaultValue: "\(name), \(size). Room hasn't looked here.")
            }
            return Row(id: id, name: name, size: size, visualSize: size, dots: dots, spoken: spoken, readout: "\(name) · \(size)")
        }
        goalLabel = plan.goalBytes.map {
            let goal = format($0)
            return Self.visible(String(localized: "plan.goal", defaultValue: "Keep \(goal)"), hidden: hidden)
        }
    }

    static func visible(_ text: String, hidden: Bool) -> String {
        hidden ? RoomPure.mask(text, first: .max, lettersToo: false) : text
    }

    func nextFocus(from current: RoomPlanRoom?, step: Int) -> RoomPlanRoom? {
        guard let current, let index = rows.firstIndex(where: { $0.id == current }) else {
            return step < 0 ? rows.last?.id : rows.first?.id
        }
        return rows[min(max(0, index + step), rows.count - 1)].id
    }
}
