import Foundation
import RoomCore

nonisolated struct RoomActionAlert: Equatable, Sendable {
    var title: String
    var message: String
    enum Primary: String, Sendable {
        case ok = "OK"
        case checkAgain = "Check Again"
        case showSkipped = "Show Skipped"
        case reviewAgain = "Review Again"
        case showWhy = "Show Why"
        case showInTrash = "Show in Trash"
    }

    var primary: Primary
    var secondary: String?
}

nonisolated struct RoomMoveOutcome: Equatable, Sendable {
    var movedCount: Int
    var movedBytes: Int64
    var failures: [RoomMoveFailure: Int]
    var withoutRecoveryInfo: Int       // trashed, but Restore must go through Finder's Put Back

    var failedCount: Int { failures.values.reduce(0, +) }
    private var only: RoomMoveFailure? { failures.count == 1 ? failures.keys.first : nil }

    func alert(format: (Int64) -> String) -> RoomActionAlert? {
        let tail = withoutRecoveryInfo > 0
            ? " \(withoutRecoveryInfo) \(withoutRecoveryInfo == 1 ? "item needs" : "items need") Put Back in Finder to restore." : ""
        if movedCount > 0, failedCount == 0 {
            return withoutRecoveryInfo > 0
                ? RoomActionAlert(title: "Moved \(format(movedBytes)) to Trash", message: String(tail.dropFirst()), primary: .ok, secondary: nil)
                : nil
        }
        if movedCount > 0 {
            let why = only == .inUse ? " because they're in use." : "."
            return RoomActionAlert(title: "Moved \(movedCount) \(movedCount == 1 ? "item" : "items") to Trash",
                message: "\(failedCount) \(failedCount == 1 ? "was" : "were") skipped\(why)" + tail,
                primary: .showSkipped, secondary: "OK")
        }
        guard failedCount > 0 else { return nil }
        let title = "Couldn't move \(failedCount) \(failedCount == 1 ? "item" : "items") to Trash"
        switch only {
        case .changed?, .staleScan?:
            return RoomActionAlert(title: title, message: "They changed after Room checked them. Check caches again, then review.",
                                   primary: .checkAgain, secondary: "OK")
        case .inUse?:
            return RoomActionAlert(title: title, message: "They're in use. Quit the app using them, then check again.",
                                   primary: .checkAgain, secondary: "OK")
        case .access?:
            return RoomActionAlert(title: title, message: "Room needs your approval for their folders. Nothing moved.",
                                   primary: .reviewAgain, secondary: "Cancel")
        case .receiptNotSaved?:
            return RoomActionAlert(title: title, message: "Room couldn't save the recovery record, so nothing moved.",
                                   primary: .ok, secondary: nil)
        default:
            return RoomActionAlert(title: title, message: "Nothing moved. Show why lists each item.", primary: .showWhy, secondary: "OK")
        }
    }

    func pill(receiptID: UUID, format: (Int64) -> String) -> RoomActivityPillState {
        if movedCount > 0 {
            return .moved(.init(id: receiptID, sentence: "Moved \(format(movedBytes)) to Trash", canRestore: movedCount > withoutRecoveryInfo))
        }
        return .failed(action: "Couldn't move \(failedCount) \(failedCount == 1 ? "item" : "items") to Trash")
    }
}

nonisolated struct RoomRestoreOutcome: Equatable, Sendable {
    var restored: Int
    var skipped: [RoomRestoreSkip: Int]
    var skippedCount: Int { skipped.values.reduce(0, +) }

    /// Toast text (16 §5) with the reason only when it is the single true reason.
    var toast: String? {
        guard restored > 0 else { return nil }
        if skippedCount == 0 { return "Put \(restored) \(restored == 1 ? "item" : "items") back where \(restored == 1 ? "it was" : "they were")." }
        let head = "Put \(restored) \(restored == 1 ? "item" : "items") back. \(skippedCount) "
        switch skipped.count == 1 ? skipped.keys.first : nil {
        case .occupied?: return head + "stayed in Trash because something new is in their place."
        case .missing?: return head + (skippedCount == 1 ? "is" : "are") + " no longer in Trash."
        default: return head + (skippedCount == 1 ? "wasn't" : "weren't") + " put back. Show why lists each item."
        }
    }

    var alert: RoomActionAlert? {
        guard restored == 0, skippedCount > 0 else { return nil }
        let title = "Couldn't restore \(skippedCount) \(skippedCount == 1 ? "item" : "items")"
        switch skipped.count == 1 ? skipped.keys.first : nil {
        case .occupied?: return RoomActionAlert(title: title, message: "Something new is in their place. They stay in Trash.", primary: .showInTrash, secondary: "OK")
        case .missing?: return RoomActionAlert(title: title, message: "They're no longer in Trash.", primary: .ok, secondary: nil)
        case .access?: return RoomActionAlert(title: title, message: "Room needs your approval for their folders. Nothing moved.", primary: .reviewAgain, secondary: "Cancel")
        default: return RoomActionAlert(title: title, message: "They stay in Trash. Show why lists each item.", primary: .showWhy, secondary: "OK")
        }
    }
}
