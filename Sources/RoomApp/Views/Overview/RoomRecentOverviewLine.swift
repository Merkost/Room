import RoomCore
import SwiftUI

struct RoomRecentOverviewLine: View {
    let entry: RoomMakeRoomEntry?
    let receipt: RoomActivity?
    let restore: (() -> Void)?
    var standalone = false
    @Environment(\.roomAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            if standalone {
                Text(String(localized: "recent.title", defaultValue: "Recent", table: "Overview", bundle: RoomCopy.bundle)).font(RoomTokens.Typography.title).accessibilityHeading(.h2)
            }
            if let entry {
                RoomMaskable(RoomMakeRoomCopy.headline(entry, format: RoomFormat.overviewBytes))
                    .font(RoomTokens.Typography.section)
                HStack(spacing: RoomTokens.Space.row) {
                    if entry.stage == .emptied && entry.observedGain > 0 {
                        Text("Trash emptied \(entry.lastChangedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    } else {
                        Text(entry.movedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        RoomMaskable("\(entry.itemCount) \(entry.itemCount == 1 ? "item" : "items")")
                    }
                    if let receipt, let restore,
                       RoomMakeRoomCopy.footerWord(entry, receiptCanRestore: receipt.canRestore) == nil {
                        Button("Restore", action: restore).roomLink(accent)
                    }
                }
                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                Text(String(localized: "recent.empty", defaultValue: "Nothing moved yet. Anything you move goes to Trash first, with a receipt.", table: "Overview", bundle: RoomCopy.bundle))
                    .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
