import SwiftUI

struct RoomWhatStaysSheet: View {
    let model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("RoomHideSizes") private var hidden = false
    @State private var pendingRemoval: RoomIgnoreRule?

    private struct Reason: Identifiable {
        var id: String { label }
        let label: String
        let bytes: Int64
    }

    private var reasons: [Reason] {
        let held = model.sources.flatMap(\.heldReasons).map { Reason(label: $0.reason, bytes: $0.bytes) }
            + model.protectedSources.map { Reason(label: $0.reason, bytes: $0.bytes) }
        return Dictionary(grouping: held, by: \.label).map { label, lines in
            Reason(label: label, bytes: lines.reduce(0) { $0 + $1.bytes })
        }.sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Text("What stays").font(RoomTokens.Typography.figure).accessibilityHeading(.h1)
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    ForEach(reasons) { reason in
                        HStack {
                            Text(reason.label).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: RoomTokens.Space.row)
                            Text(amount(reason.bytes)).monospacedDigit().fixedSize()
                                .accessibilityLabel(hidden ? "Size hidden" : amount(reason.bytes))
                        }
                    }
                    Divider()
                    HStack {
                        Text("Never suggest").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                        Spacer()
                        Button("Add Folder…") { Task { await model.chooseIgnoreLocation() } }
                            .buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
                    }
                    ForEach(model.ignoreStore?.rules ?? []) { rule in
                        HStack {
                            Text(hidden ? "Folder hidden" : rule.path)
                                .font(RoomTokens.Typography.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { pendingRemoval = rule }
                                .buttonStyle(.glass).disabled(model.isWorking || model.isScanning)
                        }
                    }
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
        .confirmationDialog("Remove this Never Suggest rule?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { rule in
            Button("Remove Rule", role: .destructive) { Task { await model.removeIgnoreRules([rule.id]) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Room can suggest eligible caches in this folder again after you check caches.")
        }
    }

    private func amount(_ bytes: Int64) -> String {
        let value = RoomFormat.overviewBytes(bytes)
        let displayed = hidden ? String(value.map { $0.isNumber ? "•" : $0 }) : value
        return model.hasPartialMeasurements ? "≥ \(displayed)" : displayed
    }
}
