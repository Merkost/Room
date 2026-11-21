// Caches screen and the shared review sheet: pure parts.
// Spec: CACHES-RECEIPTS-SPEC.md §3–§4, §6 (amends spec 07 §§1–5, 8).
import Foundation

// MARK: - Hero figures (CA-1..CA-3)

nonisolated struct RoomCachesHero: Equatable, Sendable {
    enum Primary: Equatable, Sendable { case check, chooseFolderAndCheck, review(Int64), checkAgain, none }
    var heroLabel: String
    var heroBytes: Int64?          // nil: no figure is drawn (nothing clearable / couldn't read / never checked)
    var foundBytes: Int64?
    var keptBytes: Int64?
    var lowerBound: Bool           // "≥" on found and kept
    var primary: Primary
    var disabledReason: String?

    struct Input: Equatable, Sendable {
        var hasReport: Bool            // a completed report this session (cleanup IDs exist in the engine)
        var remembered: Bool           // figures from a previous launch / pre-move report (no IDs)
        var partial: Bool              // stopped or partial measurement
        var store: Bool
        var storeHasFolders: Bool
        var totalBytes: Int64
        var clearableBytes: Int64      // after the ignore filter
        var selectedBytes: Int64
        var sourceCount: Int
        var readableSourceCount: Int
    }

    static func make(_ i: Input) -> RoomCachesHero {
        if !i.hasReport && !i.remembered && !i.partial {
            return RoomCachesHero(heroLabel: "", heroBytes: nil, foundBytes: nil, keptBytes: nil, lowerBound: false,
                primary: i.store && !i.storeHasFolders ? .chooseFolderAndCheck : .check, disabledReason: nil)
        }
        let kept = max(0, i.totalBytes - i.clearableBytes)
        if i.sourceCount > 0 && i.readableSourceCount == 0 {
            return RoomCachesHero(heroLabel: "Room couldn't read any caches.", heroBytes: nil, foundBytes: nil, keptBytes: nil,
                lowerBound: false, primary: i.store ? .chooseFolderAndCheck : .check, disabledReason: nil)
        }
        if i.partial {
            return RoomCachesHero(heroLabel: "Clearable", heroBytes: nil, foundBytes: i.totalBytes, keptBytes: kept,
                lowerBound: true, primary: .review(0), disabledReason: "Finish the check to review")
        }
        if i.remembered {
            return RoomCachesHero(heroLabel: "Clearable", heroBytes: i.clearableBytes, foundBytes: i.totalBytes, keptBytes: kept,
                lowerBound: false, primary: .checkAgain, disabledReason: nil)
        }
        if i.clearableBytes <= 0 {
            return RoomCachesHero(heroLabel: "Nothing is safe to clear right now.", heroBytes: nil, foundBytes: i.totalBytes,
                keptBytes: kept, lowerBound: false, primary: .none, disabledReason: nil)
        }
        let selecting = i.selectedBytes > 0
        return RoomCachesHero(heroLabel: selecting ? "Selected to clear" : "Clearable",
            heroBytes: selecting ? i.selectedBytes : i.clearableBytes, foundBytes: i.totalBytes, keptBytes: kept,
            lowerBound: false, primary: .review(i.selectedBytes),
            disabledReason: selecting ? nil : "Select at least one item")
    }
}
