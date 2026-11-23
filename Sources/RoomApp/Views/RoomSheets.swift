import AppKit
import SwiftUI

struct RoomSourceSheet: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let source: RoomSource
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var itemQuery = ""

    private var heldBytes: Int64 { max(0, source.bytes - source.eligibleBytes) }
    private func measured(_ bytes: Int64) -> String {
        (source.isPartial ? "≥ " : "") + RoomCachesVisibility.bytes(bytes, hidden: hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: source.name, subtitle: source.subtitle)

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(RoomCachesVisibility.bytes(source.eligibleBytes, hidden: hidden))
                        .font(RoomType.figure(34))
                        .tracking(-1)
                    Text("Clearable").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(measured(source.bytes)).font(RoomType.figure(22))
                    Text("Found").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(alignment: .trailing, spacing: 5) {
                    Text(measured(heldBytes)).font(RoomType.figure(22))
                    Text("Held").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if source.isPartial {
                        Label("Partial measurement. Unverified items stay held.", systemImage: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !model.cleanupCandidates(for: source.id).isEmpty {
                        candidateSelection
                    }

                    if !source.largestEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Largest measured items").font(.system(size: 14, weight: .medium))
                                Spacer()
                                if source.entryCount > source.largestEntries.count {
                                    Text("\(source.largestEntries.count) of \(source.entryCount)")
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(source.largestEntries, id: \.path) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                                        Text(hidden ? "Item name hidden" : entry.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        Text(RoomCachesVisibility.bytes(entry.bytes, hidden: hidden))
                                            .font(.system(size: 13)).monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                    Text(entry.reason ?? (source.isPartial ? "Measured; verification incomplete" : "Clearable after review"))
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .help(hidden ? "Location hidden" : entry.path + (entry.reason.map { "\n" + $0 } ?? ""))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    if !source.heldReasons.isEmpty {
                        DisclosureGroup("Why items are held") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(source.heldReasons, id: \.reason) { held in
                                    HStack(alignment: .top, spacing: 16) {
                                        Text(held.reason)
                                            .font(.system(size: 13))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(RoomCachesVisibility.bytes(held.bytes, hidden: hidden)).monospacedDigit()
                                            Text("\(held.count) \(held.count == 1 ? "item" : "items")").foregroundStyle(.secondary)
                                        }
                                        .font(.system(size: 12))
                                        .fixedSize()
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }

                    DisclosureGroup("Locations") {
                        Text(hidden ? "Location hidden" : source.path)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                    .font(.system(size: 13, weight: .medium))

                    DisclosureGroup("Cleanup rules") {
                        Text(hidden ? "Review details hidden" : source.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 310)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button { model.reveal(source: source) } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(.glass)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 580)
    }

    private var candidateSelection: some View {
        let candidates = model.cleanupCandidates(for: source.id)
        let query = itemQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = hidden || query.isEmpty ? candidates : candidates.filter {
            $0.name.localizedStandardContains(query) || $0.url.path.localizedStandardContains(query)
        }
        return VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack {
                Text("Choose clearable items").font(RoomTokens.Typography.section)
                Spacer()
                Text("\(RoomCachesVisibility.bytes(model.selectedBytes(for: source.id), hidden: hidden)) selected")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            if !hidden, candidates.count > 6 {
                TextField("Filter items", text: $itemQuery)
                    .textFieldStyle(.roundedBorder)
            }
            if filtered.isEmpty {
                Text("No matching items.").foregroundStyle(RoomTokens.Ink.secondary)
            }
            LazyVStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                ForEach(filtered) { item in
                    Toggle(isOn: Binding(
                        get: { model.isEntrySelected(item.id, sourceID: source.id) },
                        set: { _ in model.toggleEntrySelection(id: item.id, sourceID: source.id) }
                    )) {
                        HStack {
                            RoomMaskable(item.name, kind: .name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(RoomCachesVisibility.bytes(item.bytes, hidden: hidden)).monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!model.canEditSelection)
                    .help(hidden ? "Location hidden" : item.url.path)
                }
            }
        }
    }
}

struct RoomScanIssuesSheet: View {
    let issues: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoomSheetHeading(title: "A few scan notes.", subtitle: "The rest of your results are still available.")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.system(size: 13)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 340)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction) }
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 570)
    }
}

struct RoomSheetHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(RoomType.heading(24))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }
}
