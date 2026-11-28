import SwiftUI

struct RoomCleanupReviewSheet: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    var mapCleanup: RoomMapCleanup? = nil
    var canAccessMapCleanup: () -> Bool = { true }
    /// Set when the review is drawn in the window (`roomSheetOverlay`) rather than as a system sheet.
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var committed: RoomCleanupReview?
    @State private var mapSelection: Set<String>?

    private var reviewRows: [RoomCleanupReview.Row] { mapCleanup?.rows ?? model.cleanupRows }
    private var selectedRows: Set<String> {
        if let mapCleanup { return mapSelection ?? Set(mapCleanup.rows.map(\.id)) }
        return model.selection
    }

    private var presentation: RoomCleanupReview {
        if let committed { return committed }
        #if ROOM_APP_STORE
        return .init(rows: reviewRows, selected: selectedRows, store: true,
            allowed: model.storeGrantedPaths, phase: model.isPreparingStoreReview ? .preparingAccess : .reviewing)
        #else
        return .init(rows: reviewRows, selected: selectedRows, store: false)
        #endif
    }

    private func dismiss() {
        if let close { close() } else { systemDismiss() }
    }

    var body: some View {
        let review = presentation
        let mapIssue = mapCleanupIssue(review)
        let saved = review.phase == .moving
            ? Set(model.cleanupProgress.filter { $0.value == .trashed }.keys)
            : []
        let ticked = review.tickedRows(reported: saved)
        let kind: RoomReviewWords.Kind = mapCleanup == nil ? .caches : .cachesInFolder
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: RoomReviewWords.title(review.selectedBytes, hidden: hidden))
                .font(RoomTokens.Screen2.sheetTitle)
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(RoomTokens.Ink.graphite)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(hidden ? "Move selected items to Trash?" : RoomReviewWords.title(review.selectedBytes, hidden: false))
            Text(RoomReviewWords.body(kind))
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, RoomTokens.Space.tight)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(review.rows) { row in
                        reviewRow(row, review: review, ticked: ticked.contains(row.id), editable: review.canCancel
                                  && model.canEditSelection && mapIssue == nil)
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        ForEach(review.beforeYouMove(keptBytes: model.heldBytes,
                            keptExample: hidden ? nil : model.protectedSources.first?.name, format: format), id: \.self) { line in
                            Text(line).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, RoomTokens.Space.row)
                    if let mapIssue {
                        Text(mapIssue)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, RoomTokens.Space.row)
                            .accessibilityIdentifier("RoomMapCleanupUnavailable")
                    }
                    #if ROOM_APP_STORE
                    if review.selectedBytes > 0 && mapIssue == nil {
                        RoomStorePermissionSection(model: model, retry: { Task { await prepareStoreReview() } },
                            canApprove: { mapCleanupIssue(presentation) == nil })
                            .padding(.top, RoomTokens.Space.row)
                    }
                    #endif
                    if let message = model.errorMessage {
                        Text(message)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, RoomTokens.Space.row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // As tall as the list, up to 300 pt, so a short review has no empty band above the buttons.
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: min(300, CGFloat(review.rows.count) * RoomTokens.Screen2.sheetRow + RoomTokens.Screen2.sheetNotes))
            .padding(.top, RoomTokens.Space.group)
            HStack(spacing: RoomTokens.Space.row) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .roomQuiet().keyboardShortcut(.cancelAction)
                    .disabled(!review.canCancel || model.isWorking)
                Button {
                    move()
                } label: {
                    RoomChangingLabel(value: review.phase == .moving, animates: !hidden, alignment: .center) {
                        Text(commitLabel(review.commit))
                    }
                }
                .roomScreenPrimary(accent).keyboardShortcut(.defaultAction)
                .disabled(!canCommit(review))
                .accessibilityLabel(hidden && review.canCommit ? "Move selected items to Trash. Sizes hidden." : commitLabel(review.commit))
                .accessibilityIdentifier("RoomReviewMoveButton")
            }
            .padding(.top, RoomTokens.Space.group)
        }
        .font(RoomTokens.Typography.body)
        .padding(.horizontal, RoomTokens.Screen2.sheetPad)
        .padding(.top, RoomTokens.Screen2.sheetPad)
        .padding(.bottom, RoomTokens.Screen2.sheetPadBottom)
        .frame(width: RoomTokens.Screen2.sheetWidth)
        .interactiveDismissDisabled(!review.canCancel || model.isWorking)
        .onExitCommand { if review.canCancel && !model.isWorking { dismiss() } }
        #if ROOM_APP_STORE
        .task { await prepareStoreReview() }
        .onChange(of: mapIssue) { _, issue in
            if issue != nil && committed == nil { model.discardStoreReview() }
        }
        .onDisappear { model.discardStoreReview() }
        #endif
    }

    /// One chosen place: tick (editable while reviewing), its real icon, name, size; a check once saved in the receipt.
    private func reviewRow(_ row: RoomCleanupReview.Row, review: RoomCleanupReview, ticked: Bool, editable: Bool) -> some View {
        let selected = review.selected.contains(row.id)
        let partial = selected && row.selectedBytes < row.bytes
        let path = row.location ?? model.sources.first { $0.id == row.id }?.path
        return Button {
            setSelection(row.id, selected: !selectedRows.contains(row.id))
        } label: {
            HStack(spacing: RoomTokens.Space.row) {
                RoomTick(on: selected, partial: partial)
                RoomThingIcon(path: path, name: row.name, fallback: .box, size: RoomTokens.Screen2.iconSmall)
                VStack(alignment: .leading, spacing: 1) {
                    RoomMaskable(row.name, kind: .name).foregroundStyle(selected ? RoomTokens.Ink.graphite : RoomTokens.Ink.tertiary)
                        .lineLimit(1)
                    rowDetail(row).font(RoomTokens.Typography.caption).lineLimit(1)
                }
                Spacer(minLength: RoomTokens.Space.row)
                if ticked {
                    RoomCheckmarkPath()
                        .stroke(accent.text, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 9, height: 6)
                        .accessibilityLabel("Saved in receipt")
                } else if review.phase == .moving, row.entryIDs.contains(where: { model.cleanupProgress[$0] == .failed }) {
                    Text("Kept").foregroundStyle(RoomTokens.Ink.secondary)
                }
                RoomMaskable(RoomFormat.gb(selected ? row.selectedBytes : row.bytes))
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .frame(minHeight: RoomTokens.Screen2.sheetRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .help(hidden ? "" : row.location ?? "")
        .accessibilityLabel(hidden ? "Place, name hidden" : row.name)
        .accessibilityValue(partial ? "Some items selected" : selected ? "Selected" : "Not selected")
    }

    private func mapCleanupIssue(_ review: RoomCleanupReview) -> String? {
        guard let mapCleanup, review.phase != .moving else { return nil }
        if hidden { return "Reveal item names to review this Disk Map selection." }
        if !canAccessMapCleanup() { return "Disk Map changed. Close this review and select the item again." }
        if !model.isCurrentMapSelection(mapCleanup, entryIDs: review.selectedEntryIDs) {
            return "The cache check changed. Close this review and check the selection again."
        }
        return nil
    }

    @ViewBuilder private func rowDetail(_ row: RoomCleanupReview.Row) -> some View {
        if let location = row.location, let mapCleanup {
            let components = URL(fileURLWithPath: location).pathComponents
            let parents = components.dropFirst(mapCleanup.location.pathComponents.count).dropLast()
            if !parents.isEmpty {
                Text(hidden ? "Location hidden" : parents.joined(separator: "/"))
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        // Cache rows stay one line (mockup `.sheet li`); what moving means is said once under the list.
    }

    private func setSelection(_ id: String, selected: Bool) {
        guard mapCleanup != nil else {
            model.setSelection(id: id, selected: selected)
            return
        }
        var updated = selectedRows
        if selected { updated.insert(id) } else { updated.remove(id) }
        mapSelection = updated
        #if ROOM_APP_STORE
        if let mapCleanup {
            let ids = Set(mapCleanup.rows.filter { updated.contains($0.id) }.flatMap(\.entryIDs))
            model.updateStoreMapCleanupReview(mapCleanup, entryIDs: ids)
        }
        #endif
    }

    #if ROOM_APP_STORE
    private func prepareStoreReview() async {
        if let mapCleanup {
            guard mapCleanupIssue(presentation) == nil else { return }
            await model.prepareStoreMapCleanupReview(mapCleanup, entryIDs: presentation.selectedEntryIDs) {
                !hidden && canAccessMapCleanup()
            }
        } else {
            await model.prepareStoreCleanupReview()
        }
    }
    #endif

    private func move() {
        let review = presentation
        guard canCommit(review) else { return }
        var moving = review
        moving.phase = .moving
        committed = moving
        Task {
            if let mapCleanup {
                guard !hidden, canAccessMapCleanup(),
                      model.canCleanMapSelection(mapCleanup, entryIDs: review.selectedEntryIDs) else {
                    committed = nil
                    return
                }
                await model.cleanMapSelection(mapCleanup, entryIDs: review.selectedEntryIDs)
            } else {
                await model.cleanSelected()
            }
            committed = nil
            #if ROOM_APP_STORE
            if model.lastStoreMoveCompleted { dismiss() }
            #else
            if model.movedReceipt != nil || model.errorMessage == nil { dismiss() }
            #endif
        }
    }

    private func canCommit(_ review: RoomCleanupReview) -> Bool {
        guard review.canCommit else { return false }
        if let mapCleanup {
            guard !hidden, canAccessMapCleanup(),
                  model.canCleanMapSelection(mapCleanup, entryIDs: review.selectedEntryIDs) else { return false }
            #if ROOM_APP_STORE
            return model.hasStoreCleanupApproval(for: review.selectedEntryIDs)
            #else
            return true
            #endif
        }
        guard model.canReviewCleanup else { return false }
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

    private func format(_ bytes: Int64) -> String {
        if mapCleanup != nil { return RoomCachesVisibility.figure(RoomFormat.gb(bytes), hidden: hidden) }
        return RoomCachesVisibility.bytes(bytes, hidden: hidden)
    }
}
