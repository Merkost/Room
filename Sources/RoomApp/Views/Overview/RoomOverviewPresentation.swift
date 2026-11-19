import CoreGraphics
import Foundation

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

    init(plan: RoomOverviewPlanInput, hidden: Bool, format: (Int64) -> String) {
        let unit = format(Int64(plan.gbPerDot * 1e9))
        let scale = String(localized: "plan.unit", defaultValue: "1 dot = about \(unit)")
        caption = Self.visible(scale, hidden: hidden)
        accessibilityLabel = hidden
            ? String(localized: "plan.a11y.hidden", defaultValue: "Storage plan. Sizes hidden.")
            : String(localized: "plan.a11y", defaultValue: "Storage plan, one dot is about \(unit).")
        let freeDots = plan.freeDots
        let ordered: [(RoomPlanRoom, Int64)] = [
            (.free, plan.freeBytes),
            (.notMapped, plan.notMappedBytes),
        ]
        rows = ordered.filter { $0.0 == .free || $0.1 > 0 }.sorted { $0.1 > $1.1 }.map { id, bytes in
            let free = id == .free
            let name = free ? String(localized: "plan.free", defaultValue: "Free")
                : String(localized: "plan.notMapped", defaultValue: "Not mapped yet")
            let size = format(bytes)
            if hidden {
                let redacted = String(localized: "plan.hidden", defaultValue: "hidden")
                let spoken = String(localized: "plan.row.hidden", defaultValue: "\(name), hidden")
                return Row(id: id, name: name, size: redacted, visualSize: Self.visible(size, hidden: true),
                           dots: "", spoken: spoken, readout: spoken)
            }
            let dots: String
            let spoken: String
            if free {
                if bytes > 0, freeDots == 0 {
                    dots = String(localized: "plan.underUnit", defaultValue: "under \(unit)")
                } else if freeDots == 0 {
                    dots = String(localized: "plan.noDots", defaultValue: "No dots")
                } else {
                    dots = String(localized: "plan.dotCount", defaultValue: "about \(freeDots) dots")
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
