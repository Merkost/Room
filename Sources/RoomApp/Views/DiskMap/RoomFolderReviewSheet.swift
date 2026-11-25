import RoomCore
import SwiftUI

/// The review in front of every Disk Map move: "Move 102 GB to Trash?", the folders with their real icons, and the
/// plain line that these are the person's own folders, not caches. Trash only; History keeps a receipt.
struct RoomFolderReviewSheet: View {
    let review: RoomFolderTrashModel.Review
    let model: RoomFolderTrashModel
    let finished: (FolderTrashReceipt?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: RoomReviewWords.title(review.bytes, hidden: hide.masksNow))
                .font(RoomTokens.Screen2.sheetTitle)
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(RoomTokens.Ink.graphite)
                .accessibilityAddTraits(.isHeader)
            Text(RoomReviewWords.body(.ownFolders))
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, RoomTokens.Space.tight)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(review.requests.enumerated()), id: \.offset) { index, request in
                        HStack(spacing: RoomTokens.Space.row) {
                            RoomThingIcon(path: request.url.path, fallback: .folder, size: RoomTokens.Screen2.iconSmall)
                            RoomMaskable(review.names[index], kind: .name).lineLimit(1)
                            Spacer(minLength: RoomTokens.Space.row)
                            RoomMaskable(RoomFormat.gb(request.bytes)).foregroundStyle(RoomTokens.Ink.secondary)
                        }
                        .frame(minHeight: 30)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 240)
            .padding(.top, RoomTokens.Space.group)
            if let message = model.message {
                Text(message).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.top, RoomTokens.Space.row)
            }
            HStack(spacing: RoomTokens.Space.row) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .roomSecondary().keyboardShortcut(.cancelAction)
                    .disabled(model.isMoving)
                Button(model.isMoving ? "Moving to Trash" : "Move to Trash") {
                    Task {
                        let receipt = await model.move(review)
                        finished(receipt)
                        dismiss()
                    }
                }
                .roomPrimary(accent).keyboardShortcut(.defaultAction)
                .disabled(model.isMoving || hide.masksNow)
                .help(hide.masksNow ? "Show names to review folders before moving them." : "")
                .accessibilityIdentifier("RoomFolderReviewMove")
            }
            .padding(.top, RoomTokens.Space.group)
        }
        .font(RoomTokens.Typography.body)
        .padding(.horizontal, RoomTokens.Space.group + 8)
        .padding(.top, RoomTokens.Space.group + 8)
        .padding(.bottom, RoomTokens.Space.group + 2)
        .frame(width: RoomTokens.Screen2.sheetWidth + 60)
        .interactiveDismissDisabled(model.isMoving)
    }
}
