import RoomCore
import SwiftUI

/// The review in front of every Disk Map move: "Move 102 GB to Trash?", the folders with their real icons, and the
/// plain line that these are the person's own folders, not caches. Trash only; History keeps a receipt.
/// Return never confirms here (Cancel is the default); the move needs a click on Move to Trash.
struct RoomFolderReviewSheet: View {
    let review: RoomFolderTrashModel.Review
    let model: RoomFolderTrashModel
    let finished: (FolderTrashReceipt?) -> Void

    private enum Phase: Equatable { case reviewing, moving, outcome(FolderTrashReceipt?) }

    @State private var phase = Phase.reviewing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(RoomTokens.Screen2.sheetTitle)
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(RoomTokens.Ink.graphite)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, RoomTokens.Space.tight)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(review.requests.enumerated()), id: \.offset) { index, request in
                        row(index: index, request: request)
                    }
                }
            }
            .frame(maxHeight: 240)
            .padding(.top, RoomTokens.Space.group)
            if !review.dropped.isEmpty, phase == .reviewing {
                Text(Self.droppedLine(review))
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.top, RoomTokens.Space.row)
            }
            if let message = model.message, phase != .reviewing {
                Text(message).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RoomTokens.Space.row)
            }
            HStack(spacing: RoomTokens.Space.row) {
                Spacer()
                if case .outcome(let receipt) = phase {
                    Button("Done") { close(receipt) }
                        .roomSecondary().keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .roomSecondary().keyboardShortcut(.defaultAction)
                        .disabled(phase == .moving)
                    Button(phase == .moving ? "Moving to Trash" : "Move to Trash", action: move)
                        .roomPrimary(accent)
                        .disabled(phase != .reviewing || hide.masksNow || !model.canMove)
                        .help(hide.masksNow ? "Show names to review folders before moving them." : "")
                        .accessibilityIdentifier("RoomFolderReviewMove")
                }
            }
            .padding(.top, RoomTokens.Space.group)
        }
        .font(RoomTokens.Typography.body)
        .padding(.horizontal, RoomTokens.Space.group + 8)
        .padding(.top, RoomTokens.Space.group + 8)
        .padding(.bottom, RoomTokens.Space.group + 2)
        .frame(width: RoomTokens.Screen2.sheetWidth + 60)
        .interactiveDismissDisabled(phase == .moving)
        .onExitCommand { if phase == .reviewing { dismiss() } }
    }

    static func droppedLine(_ review: RoomFolderTrashModel.Review) -> String {
        let noun = review.isBuildFolders ? ("folder", "folders") : ("room", "rooms")
        return review.dropped.count == 1 ? "1 ticked \(noun.0) could not be checked, so it is not in this review."
            : "\(review.dropped.count) ticked \(noun.1) could not be checked, so they are not in this review."
    }

    private var title: String {
        if case .outcome(let receipt) = phase {
            guard let receipt, receipt.movedCount > 0 else { return "Nothing moved" }
            return hide.masksNow ? "Moved to Trash" : "Moved \(RoomFormat.gb(receipt.movedBytes)) to Trash"
        }
        return RoomReviewWords.title(review.bytes, hidden: hide.masksNow)
    }

    private var subtitle: String {
        if case .outcome = phase { return "Folders that could not move are where they were." }
        return RoomReviewWords.body(review.isBuildFolders ? .buildFolders : .ownFolders)
    }

    private func row(index: Int, request: FolderTrashRequest) -> some View {
        let item: FolderTrashItem? = if case .outcome(let receipt) = phase { receipt?.items[safe: index] } else { nil }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: RoomTokens.Space.row) {
                RoomThingIcon(path: request.url.path, fallback: .folder, size: RoomTokens.Screen2.iconSmall)
                RoomMaskable(review.names[index], kind: .name).lineLimit(1)
                Spacer(minLength: RoomTokens.Space.row)
                if let item, item.status != .trashed {
                    Text("Stayed").foregroundStyle(RoomTokens.Ink.secondary)
                }
                RoomMaskable(RoomFormat.gb(request.bytes)).foregroundStyle(RoomTokens.Ink.secondary)
            }
            if let message = item?.message, !hide.masksNow {
                Text(message).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.leading, RoomTokens.Screen2.iconSmall + RoomTokens.Space.row)
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    /// One submit only: the button disables and the sheet stays put until the move has finished.
    private func move() {
        guard phase == .reviewing, model.canMove else { return }
        phase = .moving
        Task {
            let receipt = await model.move(review)
            if let receipt, receipt.failedCount == 0, !receipt.receiptWriteFailed {
                close(receipt)
            } else {
                phase = .outcome(receipt)
            }
        }
    }

    private func close(_ receipt: FolderTrashReceipt?) {
        finished(receipt)
        dismiss()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
