#if ROOM_APP_STORE
import SwiftUI

struct RoomStoreCacheReviewSheet: View {
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    private var sources: [RoomSource] { model.sources.filter { model.selection.contains($0.id) && $0.isAvailable } }
    private var impacts: [String] { Array(Set(sources.flatMap(\.cleanupConsequences))).sorted() }

    var body: some View {
        RoomSheetLayout(title: "Review cleanup", subtitle: "Approve exact folders for the selected eligible items.", width: 600, maxContentHeight: 390, feedback: model.errorMessage) {
            RoomMetric(label: "Selected", bytes: model.selectedBytes)
            if !impacts.isEmpty {
                RoomContentGroup {
                    RoomStatusNotice(title: "Before you move", message: impacts.joined(separator: "\n\n"), systemImage: "exclamationmark.triangle", tone: .warning)
                }
                .accessibilityIdentifier("RoomStoreCleanupImpact")
            }
            ForEach(sources) { source in
                HStack(alignment: .top, spacing: RoomSpace.standard) {
                    VStack(alignment: .leading, spacing: RoomSpace.micro) {
                        Text(source.name).font(RoomTypography.bodyEmphasis)
                        Text("\(model.selectedCount(for: source.id)) selected \(model.selectedCount(for: source.id) == 1 ? "item" : "items")")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: RoomSpace.compact)
                    Text(RoomFormat.bytes(model.selectedBytes(for: source.id)))
                        .font(RoomTypography.body).monospacedDigit().fixedSize()
                }
            }
            RoomStorePermissionSection(model: model, retry: { Task { await model.prepareStoreCleanupReview() } })
            RoomStatusNotice(message: "Items move to Trash; Room never empties it.", systemImage: "arrow.uturn.backward")
        } actions: {
            Button("Cancel") { model.errorMessage = nil; dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction).disabled(model.isWorking)
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button {
                Task {
                    await model.cleanSelected()
                    if model.lastStoreMoveCompleted { dismiss() }
                }
            } label: { Label(model.isWorking ? "Moving…" : "Move to Trash", systemImage: "trash") }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(!model.canRunStoreCleanup)
                .accessibilityIdentifier("RoomStoreMoveToTrashButton")
        }
        .interactiveDismissDisabled(model.isWorking)
        .task(id: model.selectedEntryIDs) { await model.prepareStoreCleanupReview() }
        .onDisappear { model.discardStoreReview() }
        .onChange(of: model.isScanning) { _, scanning in
            if scanning && !model.isWorking { dismiss() }
        }
    }
}

struct RoomStoreRestoreSheet: View {
    @Bindable var model: RoomViewModel
    let record: RoomActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoomSheetLayout(title: "Restore cleanup", subtitle: "Approve the exact original folders before returning files.", width: 600, feedback: model.errorMessage) {
            RoomStatusNotice(message: "Room checks recorded items and destinations again. New or changed files are kept; nothing is overwritten.", systemImage: "arrow.uturn.backward")
            RoomStorePermissionSection(model: model, retry: { Task { await model.prepareStoreRestoreReview(record) } })
            if model.storeReviewLocations.isEmpty && !model.isPreparingStoreReview {
                Text("If saved folder access was removed, approve the original cache folder, then review again.")
                    .font(RoomTypography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Approve original folder") { model.chooseStoreFolder() }
                    .buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
            }
            if !model.storeTrashPaths.isEmpty {
                RoomStatusNotice(message: "Some saved Trash access is unavailable. Choose only the exact recorded item shown; Room does not ask for the whole Trash folder.")
            }
        } actions: {
            Button("Cancel") { model.errorMessage = nil; dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction).disabled(model.isWorking)
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button("Restore") {
                Task {
                    await model.restore(record: record)
                    if model.lastStoreRestoreCompleted { dismiss() }
                }
            }
            .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            .disabled(!model.canRunStoreRestore)
            .accessibilityIdentifier("RoomStoreRestoreButton")
        }
        .interactiveDismissDisabled(model.isWorking)
        .task(id: record.id) { await model.prepareStoreRestoreReview(record) }
        .onDisappear { model.discardStoreReview() }
        .onChange(of: model.isScanning) { _, scanning in
            if scanning && !model.isWorking { dismiss() }
        }
    }
}

private struct RoomStorePermissionSection: View {
    @Bindable var model: RoomViewModel
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.standard) {
            RoomSectionHeader(title: "Folder approval")
            Text("Access alone does not move files. Write approvals last for this review and are not saved.")
                .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.isPreparingStoreReview {
                ProgressView("Checking review…").controlSize(.small)
            } else if model.storeReviewLocations.isEmpty {
                Button("Review again", action: retry).buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
                    .accessibilityIdentifier("RoomStoreReviewAgainButton")
            } else {
                ForEach(model.storeReviewLocations, id: \.path) { url in
                    HStack(spacing: RoomSpace.standard) {
                        RoomPathLabel(path: url.path, label: model.storeTrashPaths.contains(url.path) ? "Exact Trash item" : "Original parent folder")
                        if model.storeGrantedPaths.contains(url.path) {
                            Label("Allowed", systemImage: "checkmark.circle")
                                .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize()
                        } else {
                            Button("Allow") { Task { await model.allowStoreReviewLocation(url) } }
                                .buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
                                .accessibilityLabel("Allow exactly \(url.path)")
                        }
                    }
                }
            }
        }
    }
}
#endif
