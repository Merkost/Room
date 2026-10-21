#if ROOM_APP_STORE
import SwiftUI

struct RoomStoreCacheReviewSheet: View {
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    private var sources: [RoomSource] { model.sources.filter { model.selection.contains($0.id) && $0.isAvailable } }
    private var impacts: [String] { Array(Set(sources.flatMap(\.cleanupConsequences))).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: "Make a little room.", subtitle: "Review the selection and approve its exact folders.")
            HStack(alignment: .firstTextBaseline) {
                Text(RoomFormat.bytes(model.selectedBytes)).font(RoomType.figure(36)).monospacedDigit()
                Spacer()
                Text("\(sources.count) \(sources.count == 1 ? "source" : "sources")").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if !impacts.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Before you move", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                    ForEach(impacts, id: \.self) { impact in
                        Text(impact).font(.system(size: 12)).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("RoomStoreCleanupImpact")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sources) { source in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name).font(.system(size: 14, weight: .medium))
                                Text(source.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(RoomFormat.bytes(source.eligibleBytes)).font(.system(size: 13)).monospacedDigit()
                        }
                    }
                    RoomStorePermissionSection(model: model, retry: { Task { await model.prepareStoreCleanupReview() } })
                    Label("Items move to Trash; Room never empties it.", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = model.errorMessage {
                        Text(message).font(.system(size: 13)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        await model.cleanSelected()
                        if model.lastStoreMoveCompleted { dismiss() }
                    }
                } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(!model.canRunStoreCleanup)
                .accessibilityIdentifier("RoomStoreMoveToTrashButton")
            }
            .controlSize(.large)
        }
        .padding(28).frame(width: 600)
        .interactiveDismissDisabled(model.isWorking)
        .task { await model.prepareStoreCleanupReview() }
        .onDisappear { model.discardStoreReview() }
    }
}

struct RoomStoreRestoreSheet: View {
    @Bindable var model: RoomViewModel
    let record: RoomActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: "Restore this cleanup.", subtitle: "Approve the exact original folders before returning files.")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Room checks recorded items and their destinations again. New or changed files are kept; nothing is overwritten.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    RoomStorePermissionSection(model: model, retry: { Task { await model.prepareStoreRestoreReview(record) } })
                    if model.storeReviewLocations.isEmpty && !model.isPreparingStoreReview {
                        Text("If saved folder access was removed, approve the original cache folder, then review again.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Approve original folder") { model.chooseStoreFolder() }
                            .buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
                    }
                    if !model.storeTrashPaths.isEmpty {
                        Text("Some saved Trash access is unavailable. Choose only the exact recorded item shown; Room does not ask for the whole Trash folder.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let message = model.errorMessage {
                        Text(message).font(.system(size: 13)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
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
            .controlSize(.large)
        }
        .padding(28).frame(width: 600)
        .interactiveDismissDisabled(model.isWorking)
        .task(id: record.id) { await model.prepareStoreRestoreReview(record) }
        .onDisappear { model.discardStoreReview() }
    }
}

private struct RoomStorePermissionSection: View {
    @Bindable var model: RoomViewModel
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folder approval").font(.system(size: 15, weight: .semibold))
            Text("Allowing access does not move files. These write approvals are used for this review and are not saved.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPreparingStoreReview {
                ProgressView("Checking review…").controlSize(.small)
            } else if model.storeReviewLocations.isEmpty {
                Button("Review again", action: retry).buttonStyle(.glass)
                    .disabled(model.isWorking || model.isScanning)
                    .accessibilityIdentifier("RoomStoreReviewAgainButton")
            } else {
                ForEach(model.storeReviewLocations, id: \.path) { url in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.storeTrashPaths.contains(url.path) ? "Exact Trash item" : "Original parent folder")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Text(url.path).font(.system(size: 12)).lineLimit(2).truncationMode(.middle)
                                .textSelection(.enabled).help(url.path)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if model.storeGrantedPaths.contains(url.path) {
                            Label("Allowed", systemImage: "checkmark.circle").font(.system(size: 12))
                                .foregroundStyle(.secondary).fixedSize()
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
