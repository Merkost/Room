import SwiftUI

struct RoomCleanupReviewSheet: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    var mapCleanup: RoomMapCleanup? = nil
    var canAccessMapCleanup: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        let review = presentation
        let mapIssue = mapCleanupIssue(review)
        let saved = review.phase == .moving
            ? Set(model.cleanupProgress.filter { $0.value == .trashed }.keys)
            : []
        let ticked = review.tickedRows(reported: saved)
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("caches.review.title", tableName: "Caches", bundle: RoomCopy.bundle).font(RoomTokens.Typography.lead.weight(.semibold)).accessibilityHeading(.h1)
                if let mapCleanup {
                    Text(hidden ? "Clearable caches in the selected location." :
                        "Clearable caches in “\(mapCleanup.location.lastPathComponent)”.")
                        .foregroundStyle(RoomTokens.Ink.secondary)
                } else {
                    Text("caches.review.intro", tableName: "Caches", bundle: RoomCopy.bundle).foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    ForEach(review.rows) { row in
                        let selected = review.selected.contains(row.id)
                        let partial = selected && row.selectedBytes < row.bytes
                        Toggle(isOn: Binding(get: { selectedRows.contains(row.id) },
                                             set: { setSelection(row.id, selected: $0) })) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hidden ? "Name hidden" : row.name)
                                        .font(RoomTokens.Typography.section)
                                        .overlay {
                                            Rectangle()
                                                .fill(RoomTokens.Ink.secondary)
                                                .frame(height: 1)
                                                .scaleEffect(x: selected ? 0 : 1, y: 1, anchor: .leading)
                                                .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: selected)
                                                .allowsHitTesting(false)
                                                .accessibilityHidden(true)
                                        }
                                    rowDetail(row)
                                }
                                Spacer()
                                Text(format(selected ? row.selectedBytes : row.bytes))
                                    .font(RoomTokens.Typography.section.monospacedDigit())
                                if ticked.contains(row.id) {
                                    RoomCheckmarkPath()
                                        .stroke(accent.text, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                        .frame(width: 9, height: 6)
                                        .roomPanelArrival()
                                        .accessibilityLabel("Saved in receipt")
                                } else if review.phase == .moving, row.entryIDs.contains(where: { model.cleanupProgress[$0] == .failed }) {
                                    Text("Kept").foregroundStyle(RoomTokens.Ink.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!review.canCancel || !model.canEditSelection || mapIssue != nil)
                        .help(hidden ? "" : row.location ?? "")
                        .accessibilityValue(partial ? "Some items selected" : selected ? "Selected" : "Not selected")
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        Text("Before you move").font(RoomTokens.Typography.section)
                        ForEach(review.beforeYouMove(keptBytes: model.heldBytes,
                            keptExample: hidden ? nil : model.protectedSources.first?.name, format: format), id: \.self) { line in
                            Label(line, systemImage: "circle.fill")
                                .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                        }
                    }
                    if let mapIssue {
                        Label(mapIssue, systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("RoomMapCleanupUnavailable")
                    }
                    #if ROOM_APP_STORE
                    if review.selectedBytes > 0 && mapIssue == nil {
                        RoomStorePermissionSection(model: model, retry: { Task { await prepareStoreReview() } },
                            canApprove: { mapCleanupIssue(presentation) == nil })
                    }
                    #endif
                    if let message = model.errorMessage {
                        Text(message)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    move()
                } label: {
                    ZStack {
                        if review.phase == .moving {
                            Text(commitLabel(.move(review.selectedBytes))).hidden().accessibilityHidden(true)
                        }
                        // Keep the primary button's position while it acknowledges the operation.
                        RoomChangingLabel(value: review.phase == .moving, animates: !hidden, alignment: .center) {
                            if review.phase == .moving {
                                HStack(spacing: RoomTokens.Space.row) {
                                    ProgressView().controlSize(.small)
                                    Text(commitLabel(review.commit))
                                }
                            } else {
                                Text(commitLabel(review.commit))
                            }
                        }
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
        .task { await prepareStoreReview() }
        .onChange(of: mapIssue) { _, issue in
            if issue != nil && committed == nil { model.discardStoreReview() }
        }
        .onDisappear { model.discardStoreReview() }
        #endif
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
        } else {
            Text(row.consequence).foregroundStyle(RoomTokens.Ink.secondary)
        }
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
        if mapCleanup != nil { return RoomCachesVisibility.figure(RoomFormat.bytes(bytes), hidden: hidden) }
        return RoomCachesVisibility.bytes(bytes, hidden: hidden)
    }
}
