import RoomCore
import SwiftUI

/// Copy for the Caches ready state (REVIEW §3 Caches). The Store edition keeps its folder sentence first.
/// The check's progress line: determinate when the engine reports how many places it will read.
nonisolated enum RoomCachesProgress {
    static func isDeterminate(total: Int) -> Bool { total > 0 }

    static func line(completed: Int, total: Int) -> String? {
        guard isDeterminate(total: total) else { return nil }
        return "Checking, \(min(completed, total)) of \(total) places"
    }
}

nonisolated enum RoomCachesReadyCopy {
    static let promise = "Room checks these places. Nothing is deleted. You review before anything moves to Trash."

    static func lead(needsFolder: Bool) -> String {
        needsFolder ? "Choose a folder to check, then review what can move to Trash." : promise
    }

    /// The last result as a number, or nil when there is none to show.
    static func lastResult(_ check: RoomCachesCheck, format: (Int64) -> String) -> String? {
        guard check.bytes > 0 else { return nil }
        let amount = format(check.bytes)
        return "\(check.partial ? RoomFormat.lowerBound(amount) : amount) could go"
    }
}

struct RoomCachesView: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    let review: () -> Void
    let inspect: (RoomSource) -> Void
    let showKept: () -> Void
    let showScanNotes: () -> Void
    let restore: (RoomActivity) -> Void
    /// Heavy agent worktrees (already over the threshold), or nil. Never cleaned here.
    var agentWorktreeBytes: Int64? = nil
    var reviewWorktrees: (() -> Void)? = nil

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var undo: Undo?

    private struct Undo: Equatable {
        let rules: Set<UUID>
        let name: String
    }

    private var isStore: Bool {
        #if ROOM_APP_STORE
        true
        #else
        false
        #endif
    }

    private var needsFolderApproval: Bool {
        #if ROOM_APP_STORE
        model.approvedStoreFolderCount == 0
        #else
        false
        #endif
    }

    private var hero: RoomCachesHero {
        #if ROOM_APP_STORE
        let store = true, hasFolders = model.approvedStoreFolderCount > 0
        #else
        let store = false, hasFolders = true
        #endif
        return .make(.init(hasReport: model.hasReport, remembered: !model.hasReport && model.cachesCheckStore.check != nil,
            partial: model.isPartialScan || model.isScanning, store: store, storeHasFolders: hasFolders,
            totalBytes: model.totalBytes, clearableBytes: model.clearableBytes, selectedBytes: model.selectedBytes,
            sourceCount: model.measuredSourceCount, readableSourceCount: model.readableSourceCount))
    }

    private var words: RoomCachesWords {
        RoomCachesWords.make(.init(
            scanning: model.isScanning, afterRestore: model.isAfterRestore, hasReport: model.hasReport,
            partial: model.isPartialScan, totalBytes: model.totalBytes, clearableBytes: model.clearableBytes,
            places: model.sources.filter(\.isAvailable).count, measured: model.measuredSourceCount,
            readable: model.readableSourceCount, checked: model.scannedLocationCount, toCheck: model.scanLocationCount,
            unreadable: model.scanIssues.count, rememberedBytes: model.cachesCheckStore.check?.bytes,
            needsFolder: needsFolderApproval))
    }

    var body: some View {
        let words = words
        RoomScreenFrame(headline: words.headline, supporting: words.supporting, supportingMasked: true,
                        note: words.note, scrollsEvidence: true,
                        entersEvidence: !(model.hasReport || model.isScanning || model.isPartialScan)) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                #if ROOM_APP_STORE
                npmBatch
                #endif
                if model.isScanning, model.scanLocationCount > 0 {
                    RoomScanSegments(done: model.scannedLocationCount, total: model.scanLocationCount)
                        .transition(.opacity)
                }
                if model.hasReport || model.isScanning || model.isPartialScan {
                    RoomCachesPlaces(model: model, inspect: inspect, showKept: showKept,
                                     neverSuggest: model.ignoreStore != nil ? { neverSuggest($0) } : nil)
                        .opacity(model.isAfterRestore ? 0.6 : 1)
                    if allClear { startingPlaces(checked: true) }
                } else {
                    startAction(hero: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RoomTokens.Space.group)
                    startingPlaces(checked: false)
                    lastReceipt
                }
                if let bytes = agentWorktreeBytes, let reviewWorktrees, !model.isScanning {
                    worktreeHint(bytes, review: reviewWorktrees)
                }
                if !model.scanIssues.isEmpty {
                    Button("Scan notes", action: showScanNotes).roomLink(accent)
                }
                if let undo {
                    HStack {
                        Text("Room won’t suggest \(undo.name) again.")
                        Button("Undo") { restoreSuggestion(undo) }.roomLink(accent)
                            .disabled(model.isScanning || model.isWorking)
                    }
                    .font(RoomTokens.Typography.caption)
                    .transition(.opacity)
                }
            }
        } action: {
            HStack(spacing: RoomTokens.Space.group) {
                if model.isScanning {
                    Button("Stop", action: model.cancelScan).roomQuiet(large: true)
                } else if model.hasReport, !needsFolderApproval {
                    Button("Check again", action: model.scan).roomQuiet(large: true)
                        .disabled(!model.canScan)
                }
                // Before the first check the button stands in the middle of the page, not here.
                if !model.isScanning, model.hasReport || model.isPartialScan { primary(hero) }
            }
        }
        .foregroundStyle(RoomTokens.Ink.graphite)
        .task(id: undo) {
            guard undo != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            undo = nil
        }
    }

    #if ROOM_APP_STORE
    @ViewBuilder private var npmBatch: some View {
        if let batch = model.npmBatch, batch.isBatch {
            HStack(spacing: RoomTokens.Space.inner) {
                Text(batch.hasMore ? "npm totals reflect this batch" : "Last npm batch")
                    .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                if batch.hasMore {
                    Button("Next npm batch", action: model.continueNPM)
                        .roomLink(accent)
                        .disabled(!model.canContinueNPM)
                        .accessibilityIdentifier("RoomCachesNextNPMBatch")
                }
            }
            .help("npm sizes and selections apply to the current batch.")
        }
    }
    #endif

    /// The lower half of the ready state: the last receipt, so the page answers "what happened last time".
    @ViewBuilder private var lastReceipt: some View {
        if model.movedReceipt == nil, let receipt = model.activity.first {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                Text("Last cleanup").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                RoomReceiptView(receipt: receipt, entry: model.makeRoomStore?.entry(for: receipt.id),
                    restore: model.isWorking || model.isScanning || !receipt.canRestore ? nil : { restore(receipt) })
            }
            .frame(maxWidth: RoomTokens.Space.measure, alignment: .leading)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func primary(_ hero: RoomCachesHero) -> some View {
        if model.isAfterRestore || model.isPartialScan {
            startAction(hero: false)
        } else {
            switch hero.primary {
            case .check, .checkAgain:
                checkButton(hero: false)
            case .chooseFolderAndCheck:
                chooseFolderButton(hero: false)
            case .review(let bytes):
                if model.movedReceipt == nil || bytes > 0 {
                    Button(bytes > 0 ? "Review \(format(bytes))" : "Review", action: review)
                    .roomScreenPrimary(accent).disabled(!model.canReviewCleanup) // one-filled: exclusive with Check (hero.primary switch)
                    .help(hero.disabledReason ?? "Review the selected caches.")
                }
            case .none: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func startAction(hero: Bool) -> some View {
        if needsFolderApproval { chooseFolderButton(hero: hero) } else { checkButton(hero: hero) }
    }

    private func chooseFolderButton(hero: Bool) -> some View {
        Button {
            #if ROOM_APP_STORE
            model.chooseStoreFolder(scanAfterApproval: true)
            #else
            model.scan()
            #endif
        } label: {
            Label(String(localized: "caches.action.choose", defaultValue: "Choose Folder & Check",
                table: "Caches", bundle: RoomCopy.bundle), systemImage: "folder.badge.plus")
        }
        .roomScreenPrimary(accent, hero: hero) // one-filled: exclusive with Check (Store folder approval)
        .disabled(!model.canScan)
    }

    private func checkButton(hero: Bool) -> some View {
        Button(action: model.scan) {
            Label(String(localized: "caches.action.check", defaultValue: "Check caches", table: "Caches",
                bundle: RoomCopy.bundle), systemImage: "magnifyingglass")
        }
        .roomScreenPrimary(accent, hero: hero)
        .disabled(!model.canScan)
    }

    /// Before a check: the places Room will look, as the mockup's evidence rows (icon, name, where), so the screen
    /// says what the check will cover instead of standing empty.
    /// A finished check that found nothing: the page says where Room looked instead of standing empty.
    private var allClear: Bool {
        model.hasReport && !model.isScanning && !model.isPartialScan && model.scanIssues.isEmpty
            && !model.sources.contains(where: \.isAvailable)
    }

    @ViewBuilder
    private func startingPlaces(checked: Bool) -> some View {
        let groups = model.checkLocations
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                RoomGroupLabel(text: checked ? "Where Room looked" : "Where Room looks")
                    .padding(.top, checked ? 0 : -RoomTokens.Space.group)
                ForEach(Array(groups.prefix(Self.readyRows)), id: \.id) { group in
                    let title = hidden && group.isPersonal ? "Folder hidden" : group.title
                    HStack(spacing: RoomTokens.Space.row) {
                        RoomThingIcon(path: group.locations.first?.url.path, name: hidden ? nil : group.title, fallback: .box)
                        Text(title).font(RoomTokens.Screen2.listName).foregroundStyle(RoomTokens.Ink.graphite).lineLimit(1)
                        Group {
                            if group.locations.count > 1 {
                                Text(hidden ? "Locations hidden" : "\(group.locations.count) locations")
                            } else if let location = group.locations.first {
                                locationPath(location.url)
                            }
                        }
                        .font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary).lineLimit(1)
                        Spacer(minLength: RoomTokens.Space.group)
                        Text(checked ? "Nothing to move" : "Not checked").font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.tertiary)
                    }
                    .frame(minHeight: RoomTokens.Screen2.listRow)
                    .padding(.horizontal, RoomTokens.Space.row)
                    .roomRowHover()
                    .padding(.horizontal, -RoomTokens.Space.row)
                    .accessibilityElement(children: .combine)
                }
                if groups.count > Self.readyRows {
                    Text(groups.count - Self.readyRows == 1 ? "and 1 more place" : "and \(groups.count - Self.readyRows) more places")
                        .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
                        .padding(.top, RoomTokens.Space.row)
                }
                if !isStore {
                    Text(model.isDeepScan ? "Full checks can find more locations. Full Disk Access is optional."
                                          : "Full Disk Access is optional.")
                        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.tertiary)
                        .padding(.top, RoomTokens.Space.tight)
                }
            }
        }
    }

    private static let readyRows = 7

    @ViewBuilder
    private func locationRow(_ group: RoomCacheLocationGroup) -> some View {
        let title = hidden && group.isPersonal ? "Folder hidden" : group.title
        if group.locations.count > 1 {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    ForEach(group.locations) { location in
                        locationLine(location.title) { locationPath(location.url) }
                    }
                }
                .padding(.leading, RoomTokens.Space.group)
                .padding(.vertical, RoomTokens.Space.row)
            } label: {
                locationLine(title) {
                    Text(hidden ? "Locations hidden" : "\(group.locations.count) locations")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
        } else if let location = group.locations.first {
            locationLine(title) { locationPath(location.url) }
        }
    }

    private func locationLine<Detail: View>(_ title: String, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Text(title).font(RoomTokens.Typography.body).lineLimit(1)
                .frame(idealWidth: 148, maxWidth: 148, alignment: .leading)
            detail()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
        .accessibilityElement(children: .combine)
    }

    private func locationPath(_ url: URL) -> some View {
        #if ROOM_APP_STORE
        let home = RoomStoreEnvironment.userHome
        #else
        let home: URL? = FileManager.default.homeDirectoryForCurrentUser
        #endif
        let path = home.map { RoomPillPath.abbreviate(url.path, home: $0.path) } ?? url.path
        return Text(hidden ? "Location hidden" : path)
            .font(RoomTokens.Typography.caption.monospaced())
            .foregroundStyle(RoomTokens.Ink.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    /// One quiet line and one secondary button; Developer does the reviewing.
    private func worktreeHint(_ bytes: Int64, review: @escaping () -> Void) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Text(RoomAgentWorktreeHint.line(bytes: bytes, hidden: hidden))
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(RoomAgentWorktreeHint.actionTitle, action: review)
                .roomLink(accent)
                .font(RoomTokens.Typography.caption.weight(.medium))
                .accessibilityIdentifier("RoomCachesReviewWorktrees")
        }
        .frame(maxWidth: RoomTokens.Space.measure, alignment: .leading)
        .transition(.opacity)
    }

    private func format(_ bytes: Int64) -> String { format(bytes, hero: false) }

    private func format(_ bytes: Int64, hero: Bool) -> String {
        RoomCachesVisibility.figure(RoomFormat.gb(bytes, hero: hero), hidden: hidden)
    }

    private func neverSuggest(_ source: RoomSource) {
        Task {
            let ids = await model.neverSuggest(source)
            if !ids.isEmpty { undo = Undo(rules: ids, name: source.name) }
        }
    }

    private func restoreSuggestion(_ removed: Undo) {
        Task {
            await model.removeIgnoreRules(removed.rules)
            if undo == removed { undo = nil }
        }
    }
}
