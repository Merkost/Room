import SwiftUI

struct RoomCleanupReviewSheet: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var committed: RoomCleanupReview?

    private var presentation: RoomCleanupReview {
        if let committed { return committed }
        #if ROOM_APP_STORE
        return .init(rows: model.cleanupRows, selected: model.selection, store: true,
            allowed: model.storeGrantedPaths, phase: model.isPreparingStoreReview ? .preparingAccess : .reviewing)
        #else
        return .init(rows: model.cleanupRows, selected: model.selection, store: false)
        #endif
    }

    var body: some View {
        let review = presentation
        let saved = review.phase == .moving
            ? Set(model.cleanupProgress.filter { $0.value == .trashed }.keys)
            : []
        let ticked = review.tickedRows(reported: saved)
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("Make room").font(RoomTokens.Typography.lead.weight(.semibold)).accessibilityHeading(.h1)
                Text("Review what will move to Trash.").foregroundStyle(RoomTokens.Ink.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    ForEach(review.rows) { row in
                        let selected = review.selected.contains(row.id)
                        Toggle(isOn: Binding(get: { selected }, set: { _ in model.toggleSelection(id: row.id) })) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(RoomTokens.Typography.section).strikethrough(!selected)
                                    Text(row.consequence).foregroundStyle(RoomTokens.Ink.secondary)
                                }
                                Spacer()
                                Text(format(row.bytes)).font(RoomTokens.Typography.section.monospacedDigit())
                                if ticked.contains(row.id) {
                                    Image(systemName: "checkmark").foregroundStyle(accent.text)
                                        .accessibilityLabel("Saved in receipt")
                                } else if review.phase == .moving, row.entryIDs.contains(where: { model.cleanupProgress[$0] == .failed }) {
                                    Text("Kept").foregroundStyle(RoomTokens.Ink.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!review.canCancel || model.isWorking)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        Text("Before you move").font(RoomTokens.Typography.section)
                        ForEach(review.beforeYouMove(keptBytes: model.heldBytes,
                            keptExample: model.protectedSources.first?.name, format: format), id: \.self) { line in
                            Label(line, systemImage: "circle.fill")
                                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                        }
                    }
                    #if ROOM_APP_STORE
                    if review.selectedBytes > 0 {
                        RoomStorePermissionSection(model: model) { Task { await model.prepareStoreCleanupReview() } }
                    }
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)
            HStack(spacing: RoomTokens.Space.row) {
                Text("Selected \(format(review.selectedBytes)) of \(format(review.offeredBytes))")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .roomSecondary().keyboardShortcut(.cancelAction)
                    .disabled(!review.canCancel || model.isWorking)
                Button {
                    move(review)
                } label: {
                    if review.phase == .moving {
                        ProgressView().controlSize(.small).accessibilityLabel("Moving to Trash")
                    } else {
                        Text(commitLabel(review.commit))
                    }
                }
                .roomPrimary(accent).keyboardShortcut(.defaultAction)
                .disabled(!canCommit(review))
                .accessibilityLabel(hidden && review.canCommit ? "Move selected items to Trash. Sizes hidden." : commitLabel(review.commit))
                .accessibilityIdentifier("RoomReviewMoveButton")
            }
        }
        .font(RoomTokens.Typography.caption)
        .padding(RoomTokens.Space.breath1)
        .frame(width: 560)
        .interactiveDismissDisabled(!review.canCancel || model.isWorking)
        #if ROOM_APP_STORE
        .task { await model.prepareStoreCleanupReview() }
        .onDisappear { model.discardStoreReview() }
        #endif
    }

    private func move(_ review: RoomCleanupReview) {
        guard canCommit(review) else { return }
        var moving = review
        moving.phase = .moving
        withAnimation(motion.animation(RoomTokens.Motion.standard)) { committed = moving }
        Task {
            await model.cleanSelected()
            committed = nil
            #if ROOM_APP_STORE
            if model.lastStoreMoveCompleted { dismiss() }
            #else
            if model.movedReceipt != nil || model.errorMessage == nil { dismiss() }
            #endif
        }
    }

    private func canCommit(_ review: RoomCleanupReview) -> Bool {
        guard review.canCommit, model.canReviewCleanup else { return false }
        #if ROOM_APP_STORE
        return model.canRunStoreCleanup
        #else
        return true
        #endif
    }

    private func commitLabel(_ commit: RoomCleanupReview.Commit) -> String {
        switch commit {
        case .move(let bytes): "Move \(format(bytes)) to Trash"
        case .selectAtLeastOne: "Select at least one item"
        case .allow(let count): "Allow \(count) \(count == 1 ? "folder" : "folders") to continue"
        case .checkingAccess: "Checking folders…"
        case .moving: "Moving to Trash"
        }
    }

    private func format(_ bytes: Int64) -> String { RoomCachesVisibility.bytes(bytes, hidden: hidden) }
}
