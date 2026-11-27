import SwiftUI

struct RoomWhatStaysSheet: View {
    let model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @State private var stagedRemovals: Set<UUID> = []
    private let removalPrefix = "caches:ignore:"

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Text("caches.ignore.title", tableName: "Caches", bundle: RoomCopy.bundle).font(RoomTokens.Typography.figure).accessibilityHeading(.h1)
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    HStack {
                        Spacer()
                        Button("Add Folder…") { Task { await model.chooseIgnoreLocation() } }
                            .buttonStyle(.glass).tint(nil).disabled(model.isWorking || model.isScanning)
                    }
                    ForEach((model.ignoreStore?.rules ?? []).filter { !stagedRemovals.contains($0.id) }) { rule in
                        HStack {
                            RoomMaskable(rule.path, kind: .name)
                                .font(RoomTokens.Typography.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                            Spacer()
                            RoomInlineConfirmButton(id: removalPrefix + rule.id.uuidString,
                                title: String(localized: "caches.ignore.remove", defaultValue: "Remove…", table: "Caches", bundle: RoomCopy.bundle),
                                confirmTitle: String(localized: "caches.ignore.confirm", defaultValue: "Remove rule?", table: "Caches", bundle: RoomCopy.bundle),
                                doneLine: String(localized: "caches.ignore.removed", defaultValue: "Rule removed.", table: "Caches", bundle: RoomCopy.bundle),
                                isAllowed: !model.isWorking && !model.isScanning,
                                stage: { stagedRemovals.insert(rule.id) },
                                commit: { Task { await model.removeIgnoreRules([rule.id]); stagedRemovals.remove(rule.id) } },
                                undo: { stagedRemovals.remove(rule.id) })
                        }
                    }
                    RoomInlineUndoRows(prefix: removalPrefix)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 390)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.roomSecondary().keyboardShortcut(.cancelAction)
            }
        }
        .font(RoomTokens.Typography.body)
        .padding(RoomTokens.Space.breath1)
        .frame(width: 560)
        .task { await model.ignoreStore?.load() }
        .onDisappear { RoomInlineConfirmCenter.shared.finishAll(prefix: removalPrefix) }
    }
}
