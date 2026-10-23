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
        RoomSheetLayout(title: "Review cleanup", subtitle: "Only selected eligible items will move to Trash.", width: 580,
                        feedback: model.errorMessage) {
            RoomMetric(label: "Selected", bytes: model.selectedBytes)
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: RoomSpace.small) {
                    HStack(alignment: .firstTextBaseline, spacing: RoomSpace.standard) {
                        Text(source.name).font(RoomTypography.bodyEmphasis)
                        Spacer(minLength: RoomSpace.compact)
                        Text(RoomFormat.bytes(model.selectedBytes(for: source.id)))
                            .font(RoomTypography.body).monospacedDigit().fixedSize()
                    }
                    Text("\(model.selectedCount(for: source.id)) selected \(model.selectedCount(for: source.id) == 1 ? "item" : "items")")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                    Text(source.notes).font(RoomTypography.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            RoomStatusNotice(title: "Recoverable in Trash", message: "Caches may rebuild. Space is released when you empty Trash in Finder.", systemImage: "arrow.uturn.backward")
        } actions: {
            Button("Cancel") { model.errorMessage = nil; dismiss() }.roomAction(.secondary).keyboardShortcut(.cancelAction)
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button {
                Task { await model.cleanSelected(); dismiss() }
            } label: { Label(model.isWorking ? "Moving…" : "Move to Trash", systemImage: "trash") }
                .roomAction(.primary).keyboardShortcut(.defaultAction)
                .disabled(sources.isEmpty || model.isScanning || model.isWorking)
        }
        .disabled(model.isWorking)
        .interactiveDismissDisabled(model.isWorking)
        .onChange(of: model.isScanning) { _, scanning in
            if scanning && !model.isWorking { dismiss() }
        }
        #endif
    }
}

struct RoomSourceSheet: View {
    let source: RoomSource
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCleanupItems = false
    @State private var candidateQuery = ""

    private var heldBytes: Int64 { max(0, source.bytes - source.eligibleBytes) }
    private var candidates: [RoomCleanupCandidate] { model.cleanupCandidates(for: source.id) }
    private var matchingCandidates: [RoomCleanupCandidate] {
        candidates.filter { candidateQuery.isEmpty || ($0.name + " " + $0.path).localizedCaseInsensitiveContains(candidateQuery) }
    }

    var body: some View {
        RoomSheetLayout(title: source.name, subtitle: source.subtitle, width: 600, maxContentHeight: 390) {
            HStack(alignment: .top, spacing: RoomSpace.section) {
                RoomMetric(label: "Selected", bytes: model.selectedBytes(for: source.id), maximumSize: 34)
                RoomMetric(label: "Clearable", bytes: source.eligibleBytes, maximumSize: 22)
                RoomMetric(label: "Held", bytes: heldBytes, maximumSize: 22, lowerBound: source.isPartial)
            }
            Text("\(source.isPartial ? "At least " : "")\(RoomFormat.bytes(source.bytes)) measured on disk")
                .font(RoomTypography.caption).foregroundStyle(.secondary)
            if source.isPartial {
                RoomStatusNotice(message: "Partial measurement. Unverified items stay held.", systemImage: "info.circle")
            }
            if !candidates.isEmpty { cleanupItems }
            if !source.largestEntries.isEmpty { largestItems }
            if !source.heldReasons.isEmpty {
                DisclosureGroup("Why items are held") {
                    VStack(alignment: .leading, spacing: RoomSpace.compact) {
                        ForEach(source.heldReasons, id: \.reason) { held in
                            HStack(alignment: .top, spacing: RoomSpace.standard) {
                                Text(held.reason).font(RoomTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: RoomSpace.small)
                                VStack(alignment: .trailing, spacing: RoomSpace.micro) {
                                    Text(RoomFormat.bytes(held.bytes)).monospacedDigit()
                                    Text("\(held.count) \(held.count == 1 ? "item" : "items")").foregroundStyle(.secondary)
                                }.font(RoomTypography.caption).fixedSize()
                            }
                        }
                    }.padding(.top, RoomSpace.compact)
                }.font(RoomTypography.bodyEmphasis)
            }
            DisclosureGroup("Locations") {
                RoomPathLabel(path: source.path, lineLimit: 8).padding(.top, RoomSpace.compact)
            }.font(RoomTypography.bodyEmphasis)
            DisclosureGroup("Cleanup rules") {
                Text(source.notes).font(RoomTypography.body).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RoomSpace.compact)
            }.font(RoomTypography.bodyEmphasis)
        } actions: {
            Button { model.reveal(source: source) } label: { Label("Show in Finder", systemImage: "folder") }.roomAction(.secondary)
            Spacer()
            Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction)
        }
    }

    private var cleanupItems: some View {
        DisclosureGroup(isExpanded: $showCleanupItems) {
            VStack(alignment: .leading, spacing: RoomSpace.compact) {
                if candidates.count > 12 {
                    TextField("Find a cleanup item", text: $candidateQuery).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Find a cleanup item")
                }
                LazyVStack(alignment: .leading, spacing: RoomSpace.micro) {
                    ForEach(matchingCandidates) { candidate in
                        HStack(spacing: RoomSpace.compact) {
                            Toggle(candidate.name, isOn: Binding(
                                get: { model.isEntrySelected(candidate.id, sourceID: source.id) },
                                set: { _ in model.toggleEntrySelection(id: candidate.id, sourceID: source.id) }))
                                .toggleStyle(.checkbox).font(RoomTypography.body)
                                .lineLimit(1).truncationMode(.middle)
                                .accessibilityLabel("Select \(candidate.name)")
                            Spacer(minLength: RoomSpace.small)
                            Text(RoomFormat.bytes(candidate.bytes)).font(RoomTypography.caption)
                                .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        }
                        .padding(.vertical, 6).help(candidate.path)
                    }
                }
                .disabled(!model.canEditSelection)
                if matchingCandidates.isEmpty {
                    Text("No matching eligible items.").font(RoomTypography.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, RoomSpace.compact)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Choose cleanup items").font(RoomTypography.bodyEmphasis)
                Spacer()
                Text("\(model.selectedCount(for: source.id)) of \(candidates.count)")
                    .font(RoomTypography.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityIdentifier("RoomCleanupItemSelection")
    }

    private var largestItems: some View {
        VStack(alignment: .leading, spacing: RoomSpace.compact) {
            RoomSectionHeader(title: "Largest measured items", detail: source.entryCount > source.largestEntries.count ? "\(source.largestEntries.count) of \(source.entryCount)" : nil)
            ForEach(source.largestEntries, id: \.path) { entry in
                VStack(alignment: .leading, spacing: RoomSpace.micro) {
                    HStack(alignment: .firstTextBaseline, spacing: RoomSpace.standard) {
                        Text(entry.name).font(RoomTypography.bodyEmphasis).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: RoomSpace.small)
                        Text(RoomFormat.bytes(entry.bytes)).font(RoomTypography.body)
                            .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    }
                    Text(entry.reason ?? (source.isPartial ? "Measured; verification incomplete" : "Clearable after review"))
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(entry.path + (entry.reason.map { "\n" + $0 } ?? ""))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct RoomSettingsSheet: View {
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    let showWelcome: () -> Void
    @AppStorage("RoomAppearance") private var appearance = "system"
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @AppStorage("RoomMenuBarEnabled") private var menuBarEnabled = true
    @AppStorage("RoomMenuBarMetric") private var monitorMetric = RoomMonitorMetric.memory.rawValue
    @AppStorage("RoomMonitorShowPressure") private var showPressure = true
    @AppStorage("RoomMonitorShowSwap") private var showSwap = true
    @Environment(\.dismiss) private var dismiss
    private let about = RoomAboutInformation()

    var body: some View {
        RoomSheetLayout(title: "Settings", subtitle: "Appearance, menu bar, and folder access.", width: 600, maxContentHeight: 420) {
            settingsSection("Appearance", symbol: "circle.lefthalf.filled") {
                HStack {
                    Text("Theme").font(RoomTypography.body)
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                }
                Toggle("Gentle motion", isOn: $motionEnabled).font(RoomTypography.body).toggleStyle(.switch)
                    .accessibilityHint("Always respects Reduce Motion on your Mac")
            }
            settingsSection("Menu bar", symbol: "menubar.rectangle") {
                Toggle("Show monitor", isOn: $menuBarEnabled).font(RoomTypography.body).toggleStyle(.switch)
                HStack {
                    Text("Menu bar value").font(RoomTypography.body)
                    Spacer()
                    Picker("Menu bar value", selection: $monitorMetric) {
                        ForEach(RoomMonitorMetric.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        .accessibilityIdentifier("RoomSettingsMonitorMetric")
                }.disabled(!menuBarEnabled)
                Toggle("Memory pressure colors", isOn: $showPressure).font(RoomTypography.body).toggleStyle(.switch)
                    .disabled(!menuBarEnabled)
                Toggle("Swap details", isOn: $showSwap).font(RoomTypography.body).toggleStyle(.switch)
                    .disabled(!menuBarEnabled)
            }
            RoomFolderAccessSection(insights: insights)
            settingsSection("About", symbol: "info.circle") {
                HStack(spacing: RoomSpace.standard) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 54, height: 54)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RoomSpace.micro) {
                        Text(about.name).font(RoomTypography.sectionTitle)
                        Text(about.versionLabel).font(RoomTypography.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("RoomAboutVersion")
                        #if ROOM_APP_STORE
                        Text("Mac App Store edition").font(RoomTypography.caption).foregroundStyle(.secondary)
                        #endif
                    }
                }
                let links = RoomAppLinks()
                HStack(spacing: RoomSpace.section) {
                    if let url = links.support {
                        Link(destination: url) { Label("Support", systemImage: "questionmark.circle") }
                            .accessibilityIdentifier("RoomSupportLink")
                    }
                    if let url = links.privacy {
                        Link(destination: url) { Label("Privacy", systemImage: "hand.raised") }
                            .accessibilityIdentifier("RoomPrivacyLink")
                    }
                }.font(RoomTypography.body)
                Button(action: showWelcome) { Label("Welcome to Room", systemImage: "sparkle") }
                    .roomAction(.quiet).font(RoomTypography.body).accessibilityIdentifier("RoomReplayOnboarding")
            }
        } actions: {
            Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }.roomAction(.secondary)
            Spacer()
            Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction)
        }
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        RoomContentGroup {
            Label(title, systemImage: symbol).font(RoomTypography.sectionTitle).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14, content: content)
        }
    }
}

struct RoomProtectedSheet: View {
    @Bindable var model: RoomViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoomSheetLayout(title: "Your work stays", subtitle: "These locations are excluded from cleanup.") {
            LazyVStack(alignment: .leading, spacing: RoomSpace.section) {
                ForEach(model.protectedSources) { source in
                    VStack(alignment: .leading, spacing: RoomSpace.small) {
                        HStack(alignment: .firstTextBaseline, spacing: RoomSpace.compact) {
                            Label(source.name, systemImage: "lock").font(RoomTypography.bodyEmphasis)
                            Spacer(minLength: RoomSpace.small)
                            Text(RoomFormat.bytes(source.bytes)).font(RoomTypography.body).foregroundStyle(.secondary).monospacedDigit()
                            Button { model.revealProtected(source: source) } label: { Image(systemName: "arrow.up.forward") }
                                .roomAction(.quiet).help("Show \(source.name) in Finder")
                                .accessibilityLabel("Show \(source.name) in Finder")
                        }
                        Text(source.reason).font(RoomTypography.body).foregroundStyle(.secondary)
                        RoomPathLabel(path: source.path, lineLimit: 4)
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction)
        }
    }
}

private struct RoomFolderAccessSection: View {
    @Bindable var insights: RoomInsightsModel
    @State private var showingAll = false
    @State private var renewingID: String?
    private let access = RoomFileAccess.shared

    var body: some View {
        RoomContentGroup {
            RoomSectionHeader(title: "Folder access") {
                Button { insights.chooseAccessFolder() } label: { Label("Add folder", systemImage: "plus") }
                    .roomAction(.secondary).disabled(renewingID != nil)
                    .help("Choose a folder to save read-only access")
            }
            if access.folders.isEmpty {
                Text("Choose folders Room can revisit.").font(RoomTypography.body).foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: RoomSpace.compact) {
                    ForEach(Array(access.folders.prefix(showingAll ? .max : 4))) { folder in
                        HStack(spacing: RoomSpace.compact) {
                            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
                            RoomPathLabel(path: folder.url.path, label: folder.name, lineLimit: 1)
                            Button { insights.forgetAccessFolder(id: folder.id) } label: { Image(systemName: "minus.circle") }
                                .roomAction(.quiet).foregroundStyle(.secondary).disabled(renewingID != nil)
                                .help("Forget saved access to \(folder.name)")
                                .accessibilityLabel("Forget saved access to \(folder.name)")
                        }
                    }
                }
                if access.folders.count > 4 {
                    Button(showingAll ? "Show fewer folders" : "Show all \(access.folders.count) folders") { showingAll.toggle() }
                        .roomAction(.quiet).font(RoomTypography.caption)
                }
            }
            if !access.unavailableFolders.isEmpty {
                Divider()
                Text("Needs attention").font(RoomTypography.bodyEmphasis).accessibilityAddTraits(.isHeader)
                ForEach(access.unavailableFolders) { folder in
                    VStack(alignment: .leading, spacing: RoomSpace.small) {
                        HStack(alignment: .top, spacing: RoomSpace.compact) {
                            Image(systemName: "folder.badge.questionmark").foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: RoomSpace.micro) {
                                Text(folder.name).font(RoomTypography.bodyEmphasis)
                                Text(folder.reason).font(RoomTypography.caption).foregroundStyle(.secondary)
                                if let path = folder.path { RoomPathLabel(path: path, lineLimit: 2) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if renewingID == folder.id { ProgressView().controlSize(.small) }
                            Button("Renew") { renew(folder) }.roomAction(.secondary).disabled(renewingID != nil)
                                .accessibilityLabel("Renew access to \(folder.name)")
                            Button { access.forget(id: folder.id) } label: { Image(systemName: "minus.circle") }
                                .roomAction(.quiet).foregroundStyle(.secondary).disabled(renewingID != nil)
                                .help("Forget unavailable access to \(folder.name)")
                                .accessibilityLabel("Forget unavailable access to \(folder.name)")
                        }
                    }
                }
            }
            #if ROOM_APP_STORE
            if insights.hasRememberedHomeAccess {
                Label("Home folder access remembered", systemImage: "checkmark.circle")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
            } else {
                Button { insights.chooseHomeAccess() } label: { Label("Remember home folder", systemImage: "house") }
                    .roomAction(.secondary).disabled(renewingID != nil)
                    .accessibilityIdentifier("RoomRememberHomeFolderButton")
            }
            Text("Read approval covers accessible subfolders and hidden files. macOS can still protect locations. Other volumes need separate approval; changes need reviewed write access.")
                .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            #else
            Button { insights.openPrivacySettings() } label: { Label("Open Full Disk Access", systemImage: "lock.shield") }
                .roomAction(.secondary).accessibilityIdentifier("RoomFullDiskAccessButton")
            Text("macOS controls protected locations. Saved folder approvals provide read access; changes require separate review.")
                .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            #endif
            if let note = access.note {
                RoomStatusNotice(message: note)
            }
        }
    }

    private func renew(_ folder: RoomUnavailableAccessFolder) {
        renewingID = folder.id
        Task {
            defer { renewingID = nil }
            let initial = folder.path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            guard let approved = await RoomNativeFolderPicker.shared.choose(
                title: "Renew folder access",
                message: "Choose the original folder to renew read-only access. Choosing a different folder replaces this saved entry. No files will move.",
                prompt: "Renew Access", initialURL: initial) else { return }
            do { try access.renew(id: folder.id, approvedURL: approved) }
            catch { access.setNote("Access could not be renewed. Review this entry and choose the folder again.") }
        }
    }
}

struct RoomScanIssuesSheet: View {
    let issues: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoomSheetLayout(title: "Scan notes", subtitle: "The rest of your results are still available.") {
            LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    RoomStatusNotice(message: issue, systemImage: "info.circle")
                }
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction)
        }
    }
}

struct RoomActivityView: View {
    @Bindable var model: RoomViewModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    @State private var filter = RoomActivityFilter.all
    #endif
    #if ROOM_APP_STORE
    @State private var restoreReview: RoomActivity?
    #endif
    @State private var isLoadingHistory = true

    private var showsCaches: Bool {
        #if ROOM_APP_STORE
        true
        #else
        filter != .worktrees
        #endif
    }
    private var hasVisibleRecords: Bool {
        #if ROOM_APP_STORE
        !model.activity.isEmpty
        #else
        (showsCaches && !model.activity.isEmpty) || (filter != .caches && !agentWork.receipts.isEmpty)
        #endif
    }
    private var introduction: String {
        #if ROOM_APP_STORE
        "Review cleanup records and restore items still in Trash."
        #else
        "Cache cleanups and worktree recovery, in one place."
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            RoomPageHeader(title: "Activity", subtitle: introduction) {
                Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }
                    .roomAction(.secondary).controlSize(.large)
            }
            #if !ROOM_APP_STORE
            Picker("Activity type", selection: $filter) {
                ForEach(RoomActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                .accessibilityLabel("Activity type").accessibilityIdentifier("RoomActivityTypePicker")
            #endif
            if isLoadingHistory {
                ProgressView("Reading activity…").controlSize(.small).frame(maxWidth: .infinity, minHeight: 180)
            } else if !hasVisibleRecords {
                historyEmptyState
            } else {
                if showsCaches && !model.activity.isEmpty {
                    RoomSectionHeader(title: "Caches", detail: "\(model.activity.count)")
                    LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
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
                #if !ROOM_APP_STORE
                if filter != .caches && !agentWork.receipts.isEmpty { RoomAgentHistoryView(model: agentWork) }
                #endif
            }
            if model.statusMessage == nil {
                RoomStatusNotice(message: "Disk space is released when you empty Trash in Finder.", systemImage: "trash")
            }
            if model.isScanning {
                RoomStatusNotice(message: "Cache scan in progress. Stop it in Clean to restore caches now.", systemImage: "magnifyingglass")
            }
            if let message = model.statusMessage, !message.isEmpty {
                RoomStatusNotice(message: message).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task {
            await model.refreshHistory()
            #if !ROOM_APP_STORE
            await agentWork.refreshHistory()
            #endif
            isLoadingHistory = false
        }
        #if ROOM_APP_STORE
        .sheet(item: $restoreReview, onDismiss: { model.discardStoreReview() }) { record in
            RoomStoreRestoreSheet(model: model, record: record)
        }
        #endif
    }

    @ViewBuilder private var historyEmptyState: some View {
        #if ROOM_APP_STORE
        RoomEmptyState(title: "No cleanup history", message: "Reviewed cache moves and recovery records appear here.", systemImage: "clock.arrow.circlepath")
        #else
        switch filter {
        case .all:
            RoomEmptyState(title: "No cleanup history", message: "Reviewed cache and worktree moves appear here, with their recovery records.", systemImage: "clock.arrow.circlepath")
        case .caches:
            RoomEmptyState(title: "No cache activity", message: "Caches you move to Trash will appear here.", systemImage: "trash")
        case .worktrees:
            RoomEmptyState(title: "No worktree activity", message: "Reviewed worktree moves and recovery records appear here.", systemImage: "point.3.connected.trianglepath.dotted")
        }
        #endif
    }
}

#if !ROOM_APP_STORE
private enum RoomActivityFilter: String, CaseIterable { case all = "All", caches = "Caches", worktrees = "Worktrees" }
#endif

private struct RoomActivityRow: View {
    let record: RoomActivity
    let isWorking: Bool
    let restore: () -> Void
    @State private var expanded = false

    var body: some View {
        RoomContentGroup {
            HStack(spacing: RoomSpace.standard) {
                Image(systemName: record.canRestore ? "trash" : "arrow.uturn.backward")
                    .font(.system(size: 21)).foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title).font(RoomTypography.bodyEmphasis)
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(RoomFormat.bytes(record.bytes)).font(RoomTypography.body).monospacedDigit()
                    Text("\(record.itemCount) \(record.itemCount == 1 ? "item" : "items") · \(record.restoredCount) restored")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                Button("Restore", action: restore)
                    .roomAction(.secondary)
                    .controlSize(.large)
                    .disabled(!record.canRestore || isWorking)
            }

            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(record.details) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name).font(RoomTypography.bodyEmphasis)
                                Spacer()
                                if item.isRestored {
                                    Text("Restored").font(RoomTypography.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(item.message).font(RoomTypography.caption).foregroundStyle(.secondary)
                            RoomPathLabel(path: item.path, lineLimit: 4)
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                Text(record.errorCount > 0 ? "Review \(record.errorCount) \(record.errorCount == 1 ? "issue" : "issues") and item details" : "Item details")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 48)
        }
        .accessibilityElement(children: .contain)
    }
}
