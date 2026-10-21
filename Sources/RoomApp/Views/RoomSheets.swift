import AppKit
import SwiftUI

struct RoomReviewSheet: View {
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    private var sources: [RoomSource] { model.sources.filter { model.selection.contains($0.id) && $0.isAvailable } }

    var body: some View {
        #if ROOM_APP_STORE
        RoomStoreCacheReviewSheet(model: model)
        #else
        VStack(alignment: .leading, spacing: 24) {
            RoomSheetHeading(title: "Make a little room.", subtitle: "Review the caches you’ve selected.")

            HStack(alignment: .firstTextBaseline) {
                Text(RoomFormat.bytes(model.selectedBytes))
                    .font(RoomType.figure(40))
                    .tracking(-1.5)
                Spacer()
                Text("\(sources.count) \(sources.count == 1 ? "source" : "sources")")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(source.name).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(RoomFormat.bytes(source.eligibleBytes)).font(.system(size: 14)).monospacedDigit()
                            }
                            Text(source.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            }
            .frame(maxHeight: 250)
            .scrollIndicators(.visible)

            Label {
                Text("Caches may rebuild. Items stay recoverable in Trash; disk space is released when Trash is emptied.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15))
            }
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        await model.cleanSelected()
                        dismiss()
                    }
                } label: {
                    Label(model.isWorking ? "Moving…" : "Move to Trash", systemImage: "trash")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sources.isEmpty || model.isScanning || model.isWorking)
            }
            .controlSize(.large)
            .disabled(model.isWorking)
        }
        .padding(32)
        .frame(width: 550)
        .interactiveDismissDisabled(model.isWorking)
        #endif
    }
}

struct RoomSourceSheet: View {
    let source: RoomSource
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss

    private var heldBytes: Int64 { max(0, source.bytes - source.eligibleBytes) }
    private func measured(_ bytes: Int64) -> String {
        (source.isPartial ? "≥ " : "") + RoomFormat.bytes(bytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: source.name, subtitle: source.subtitle)

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(RoomFormat.bytes(source.eligibleBytes))
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
                                        Text(entry.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        Text(RoomFormat.bytes(entry.bytes))
                                            .font(.system(size: 13)).monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                    Text(entry.reason ?? (source.isPartial ? "Measured; verification incomplete" : "Clearable after review"))
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .help(entry.path + (entry.reason.map { "\n" + $0 } ?? ""))
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
                                            Text(RoomFormat.bytes(held.bytes)).monospacedDigit()
                                            Text("\(held.count) items").foregroundStyle(.secondary)
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
                        Text(source.path)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                    .font(.system(size: 13, weight: .medium))

                    DisclosureGroup("Cleanup rules") {
                        Text(source.notes)
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
}

struct RoomSettingsSheet: View {
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    let showWelcome: () -> Void
    @AppStorage("RoomAppearance") private var appearance = "dark"
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @AppStorage("RoomMenuBarMetric") private var monitorMetric = RoomMonitorMetric.memory.rawValue
    @AppStorage("RoomMonitorShowPressure") private var showPressure = true
    @AppStorage("RoomMonitorShowSwap") private var showSwap = true
    @Environment(\.dismiss) private var dismiss
    private let about = RoomAboutInformation()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoomSheetHeading(title: "Settings", subtitle: "Make Room feel at home.")
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    settingsSection("Appearance", symbol: "circle.lefthalf.filled") {
                        HStack {
                            Text("Theme").font(.system(size: 13))
                            Spacer()
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                        }
                        Toggle("Gentle motion", isOn: $motionEnabled).font(.system(size: 13)).toggleStyle(.switch)
                            .accessibilityHint("Always respects Reduce Motion on your Mac")
                        Text("Motion follows your Mac’s accessibility settings.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    settingsSection("Menu bar", symbol: "menubar.rectangle") {
                        Toggle("Show monitor", isOn: $menuBarEnabled).font(.system(size: 13)).toggleStyle(.switch)
                        HStack {
                            Text("Menu bar value").font(.system(size: 13))
                            Spacer()
                            Picker("Menu bar value", selection: $monitorMetric) {
                                ForEach(RoomMonitorMetric.allCases) { Text($0.title).tag($0.rawValue) }
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                                .accessibilityIdentifier("RoomSettingsMonitorMetric")
                        }.disabled(!menuBarEnabled)
                        Toggle("Memory pressure colors", isOn: $showPressure).font(.system(size: 13)).toggleStyle(.switch)
                            .disabled(!menuBarEnabled)
                        Toggle("Swap details", isOn: $showSwap).font(.system(size: 13)).toggleStyle(.switch)
                            .disabled(!menuBarEnabled)
                    }
                    RoomFolderAccessSection(insights: insights)
                    settingsSection("About", symbol: "info.circle") {
                        HStack(spacing: 15) {
                            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 54, height: 54)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(about.name).font(RoomType.heading(18))
                                Text(about.versionLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("RoomAboutVersion")
                                #if ROOM_APP_STORE
                                Text("Mac App Store edition").font(.system(size: 11)).foregroundStyle(.tertiary)
                                #endif
                            }
                        }
                        let links = RoomAppLinks()
                        HStack(spacing: 20) {
                            if let url = links.support {
                                Link(destination: url) { Label("Support", systemImage: "questionmark.circle") }
                                    .accessibilityIdentifier("RoomSupportLink")
                            }
                            if let url = links.privacy {
                                Link(destination: url) { Label("Privacy", systemImage: "hand.raised") }
                                    .accessibilityIdentifier("RoomPrivacyLink")
                            }
                        }.font(.system(size: 13))
                        Button(action: showWelcome) { Label("Welcome to Room", systemImage: "sparkle") }
                            .buttonStyle(.plain).font(.system(size: 13)).accessibilityIdentifier("RoomReplayOnboarding")
                        Text("Reviewed cache moves stay recoverable in Trash until you empty it.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.frame(maxHeight: 380).scrollIndicators(.hidden)
            HStack {
                Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }.buttonStyle(.glass)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.large)
        }.padding(32).frame(width: 540)
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 14, content: content)
        }
    }
}

struct RoomProtectedSheet: View {
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoomSheetHeading(title: "Your work stays.", subtitle: "These locations are excluded from cleanup.")
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(model.protectedSources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(source.name, systemImage: "lock")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(RoomFormat.bytes(source.bytes))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Button { model.revealProtected(source: source) } label: { Image(systemName: "arrow.up.forward") }
                                    .buttonStyle(.plain)
                                    .help("Show \(source.name) in Finder")
                                    .accessibilityLabel("Show \(source.name) in Finder")
                            }
                            Text(source.reason).font(.system(size: 13)).foregroundStyle(.secondary)
                            Text(source.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction) }
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 580)
    }
}

private struct RoomFolderAccessSection: View {
    @Bindable var insights: RoomInsightsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Folder access", systemImage: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button { insights.chooseAccessFolder() } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass).help("Choose a folder to save access")
                    .accessibilityLabel("Choose a folder to save access")
            }
            if insights.accessFolders.isEmpty {
                Text("Choose folders Room can revisit.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(insights.accessFolders) { folder in
                            HStack(spacing: 12) {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(folder.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(folder.url.path).font(.system(size: 12)).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Button { insights.forgetAccessFolder(id: folder.id) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .help("Forget saved access to \(folder.name)")
                                    .accessibilityLabel("Forget saved access to \(folder.name)")
                            }
                        }
                    }
                }
                .frame(height: min(140, CGFloat(insights.accessFolders.count) * 47))
            }
            #if ROOM_APP_STORE
            Text("Choose folders to inspect. macOS permissions can keep some locations unavailable.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #else
            HStack {
                Text("macOS manages system permissions.").foregroundStyle(.secondary)
                Spacer()
                Button("Privacy settings") { insights.openPrivacySettings() }.buttonStyle(.plain)
            }
            .font(.system(size: 12))
            #endif
            if let note = insights.accessNote {
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

struct RoomActivityView: View {
    @Bindable var model: RoomViewModel
    #if ROOM_APP_STORE
    @State private var restoreReview: RoomActivity?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Room to look back.")
                        .font(RoomType.heading(27)).tracking(-0.8)
                    Text("Your cleanup history. Restore anything still in Trash.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            .padding(.top, 35)

            if model.activity.isEmpty {
                ContentUnavailableView {
                    Label("A fresh start.", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Caches you move to Trash will appear here.")
                }
                .frame(maxWidth: .infinity, minHeight: 350)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(model.activity) { record in
                        RoomActivityRow(record: record, isWorking: model.isWorking || model.isScanning) {
                            #if ROOM_APP_STORE
                            restoreReview = record
                            #else
                            Task { await model.restore(record: record) }
                            #endif
                        }
                    }
                }
            }

            Text("Disk space is released when you empty Trash in Finder.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if model.isScanning {
                Label("Cache scan in progress. Stop it in Clean to restore now.", systemImage: "magnifyingglass")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if let message = model.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        #if ROOM_APP_STORE
        .sheet(item: $restoreReview, onDismiss: { model.discardStoreReview() }) { record in
            RoomStoreRestoreSheet(model: model, record: record)
        }
        #endif
    }
}

private struct RoomActivityRow: View {
    let record: RoomActivity
    let isWorking: Bool
    let restore: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 18) {
                Image(systemName: record.canRestore ? "trash" : "arrow.uturn.backward")
                    .font(.system(size: 21)).foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title).font(.system(size: 14, weight: .medium))
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(RoomFormat.bytes(record.bytes)).font(.system(size: 14)).monospacedDigit()
                    Text("\(record.itemCount) items · \(record.restoredCount) restored")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Button("Restore", action: restore)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(!record.canRestore || isWorking)
            }

            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(record.details) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name).font(.system(size: 13, weight: .medium))
                                Spacer()
                                if item.isRestored {
                                    Text("Restored").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            Text(item.message).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(item.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                Text(record.errorCount > 0 ? "Review \(record.errorCount) issues and item details" : "Item details")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.leading, 48)
        }
        .padding(22)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct RoomSheetHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(RoomType.heading(25)).tracking(-0.7)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }
}
