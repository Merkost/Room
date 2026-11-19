import RoomCore
import SwiftUI

struct RoomCachesView: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let model: RoomViewModel
    let review: () -> Void
    let inspect: (RoomSource) -> Void
    let showKept: () -> Void
    let showScanNotes: () -> Void
    let restore: (RoomActivity) -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var filter = Filter.clearable
    @State private var undo: Undo?
    @FocusState private var focusedSource: String?

    private enum Filter: String, CaseIterable {
        case clearable = "Clearable", kept = "Kept", all = "All"
    }

    private struct Undo: Equatable {
        let rules: Set<UUID>
        let name: String
    }

    private var rows: [RoomSource] {
        switch filter {
        case .clearable: model.hasReport && !model.isPartialScan ? model.sources.filter(\.isAvailable) : model.sources
        case .kept: model.sources.filter { $0.bytes > $0.eligibleBytes || !$0.heldReasons.isEmpty }
        case .all: model.sources
        }
    }

    private var isStore: Bool {
        #if ROOM_APP_STORE
        true
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

    var body: some View {
        let presentation = hero
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            if model.isAfterRestore {
                headline(presentation) {
                    Text("Check again to see which caches are available.").font(RoomTokens.Typography.lead)
                }
            } else if model.hasReport || model.isPartialScan {
                headline(presentation) { figures(presentation) }
            } else if model.cachesCheckStore.check == nil {
                headline(presentation) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        Text("Make a little room.").font(RoomTokens.Typography.figure.weight(.semibold))
                            .accessibilityHeading(.h1)
                        Text("Room checks the cache folders below and shows what rebuilds on its own. Scanning only looks. Nothing moves until you say so.")
                            .font(RoomTokens.Typography.body)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(idealWidth: 440, maxWidth: 440, alignment: .leading)
                }
            } else if !model.isScanning {
                primary(presentation)
            }
            if let receipt = model.movedReceipt {
                let entry = model.makeRoomStore?.entry(for: receipt.id)
                moved(receipt, entry: entry)
                RoomReceiptView(receipt: receipt, entry: entry,
                    restore: model.isWorking || model.isScanning ? nil : { restore(receipt) },
                    printsOnArrival: true)
                    .id(receipt.id)
            }
            if !model.sources.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: RoomTokens.Space.group) { comparison; sources }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.group) { comparison; sources }
                }
                .opacity(model.isAfterRestore ? 0.6 : 1)
            } else if !model.isScanning && !model.hasReport {
                startingPlaces
            }
            if !model.scanIssues.isEmpty {
                Button("See scan notes", action: showScanNotes).roomLink(accent)
            }
            if let undo {
                HStack {
                    Text("Room won’t suggest \(undo.name) again.")
                    Button("Undo") { restoreSuggestion(undo) }.roomLink(accent)
                        .disabled(model.isScanning || model.isWorking)
                }
                .font(RoomTokens.Typography.caption)
            }
        }
        .foregroundStyle(RoomTokens.Ink.graphite)
        .task(id: undo) {
            guard undo != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            undo = nil
        }
    }

    private func headline<Summary: View>(_ hero: RoomCachesHero, @ViewBuilder summary: () -> Summary) -> some View {
        let content = summary()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: RoomTokens.Space.group) {
                content
                Spacer(minLength: 0)
                if !model.isScanning { primary(hero).fixedSize() }
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                content
                if !model.isScanning { primary(hero) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figures(_ hero: RoomCachesHero) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: RoomTokens.Space.breath1) {
            if let bytes = hero.heroBytes {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text(hero.heroLabel).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    metric(format(bytes), number: RoomTokens.Typography.hero, unit: RoomTokens.Typography.counter)
                        .contentTransition(motion.isFull ? .numericText() : .identity)
                        .animation(motion.animation(RoomTokens.Motion.countAnimation, fallback: nil), value: bytes)
                }
            } else if !hero.lowerBound {
                Text(hero.heroLabel).font(RoomTokens.Typography.lead)
            }
            if let found = hero.foundBytes, !hero.lowerBound || found > 0 {
                statistic("Caches found", bytes: found, lowerBound: hero.lowerBound)
            }
            if let kept = hero.keptBytes, !hero.lowerBound || kept > 0 {
                statistic("Kept safe", bytes: kept, lowerBound: hero.lowerBound)
            }
            if !model.isScanning && hero.keptBytes != nil {
                Button("What stays ›", action: showKept).roomLink(accent)
            }
        }
    }

    private func statistic(_ title: String, bytes: Int64, lowerBound: Bool) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text(title).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            metric("\(lowerBound ? "≥ " : "")\(format(bytes))",
                   number: RoomTokens.Typography.figure, unit: RoomTokens.Typography.micro)
        }
    }

    private func metric(_ value: String, number: Font, unit: Font) -> Text {
        guard let split = value.lastIndex(where: \.isWhitespace) else {
            return Text(value).font(number)
        }
        let amount = Text(value[..<split]).font(number)
        let suffix = Text(value[split...]).font(unit).foregroundColor(RoomTokens.Ink.secondary)
        return Text("\(amount)\(suffix)")
    }

    @ViewBuilder
    private func primary(_ hero: RoomCachesHero) -> some View {
        if model.isAfterRestore {
            checkButton
        } else {
            switch hero.primary {
            case .check, .checkAgain:
                checkButton
            case .chooseFolderAndCheck:
                Button(String(localized: "caches.action.choose", defaultValue: "Choose Folder & Check", table: "Caches", bundle: RoomCopy.bundle)) {
                    #if ROOM_APP_STORE
                    model.chooseStoreFolder(scanAfterApproval: true)
                    #else
                    model.scan()
                    #endif
                }
                .roomScreenPrimary(accent).disabled(!model.canScan)
            case .review(let bytes):
                if model.movedReceipt == nil || bytes > 0 {
                    Button(bytes > 0 ? "Review \(format(bytes))" : "Review", action: review)
                        .roomScreenPrimary(accent).disabled(!model.canReviewCleanup)
                        .help(hero.disabledReason ?? "Review the selected caches.")
                }
            case .none: EmptyView()
            }
        }
    }

    private var checkButton: some View {
        Button(String(localized: "caches.action.check", defaultValue: "Check caches", table: "Caches", bundle: RoomCopy.bundle)) {
            model.scan()
        }
        .roomScreenPrimary(accent)
        .disabled(!model.canScan)
    }

    private var startingPlaces: some View {
        let groups = model.checkLocations
        return VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.row) {
                Text("Where Room looks").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                Text(isStore ? "Store" : "Direct")
                    .font(RoomTokens.Typography.micro)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoomTokens.Surface.track, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.field))
                Spacer()
                if !isStore {
                    Text("Full Disk Access is optional").font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            if groups.isEmpty {
                Text("Room checks only the folders you allow.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.vertical, RoomTokens.Space.row)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        locationRow(group)
                        if group.id != groups.last?.id { Rectangle().fill(RoomTokens.Surface.line).frame(height: 1) }
                    }
                }
            }
            if !isStore, model.isDeepScan {
                Text("The check can also find other cache locations.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .padding(.top, RoomTokens.Space.tight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

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

    private var comparison: some View {
        RoomBeforeAfterView(sources: model.sources, selection: model.selection, format: format)
            .frame(minWidth: 264, maxWidth: .infinity, alignment: .topLeading)
            .padding(RoomTokens.Space.group)
            .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoomTokens.Space.inner) {
                    sourceFilter.fixedSize()
                    selectionCount
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    sourceFilter
                    selectionCount
                }
            }
            ForEach(rows) { source in
                RoomCachesRow(source: source, displayedBytes: displayedBytes(source), selected: model.selection.contains(source.id),
                    canSelect: model.hasReport && !model.isWorking && !model.isScanning && !source.isPartial && source.isAvailable,
                    focus: $focusedSource, format: format, select: { model.toggleSelection(id: source.id) },
                    inspect: { inspect(source) }, reveal: { model.reveal(source: source) },
                    neverSuggest: source.isAvailable && model.ignoreStore != nil ? { neverSuggest(source) } : nil)
            }
            if rows.isEmpty { Text("No sources in this view.").font(RoomTokens.Typography.caption) }
        }
        .onKeyPress(.upArrow) { moveFocus(-1) }
        .onKeyPress(.downArrow) { moveFocus(1) }
        .frame(minWidth: 270, maxWidth: .infinity, alignment: .topLeading)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

    private func displayedBytes(_ source: RoomSource) -> Int64 {
        switch filter {
        case .clearable: source.isAvailable ? source.eligibleBytes : source.bytes
        case .kept: max(0, source.bytes - source.eligibleBytes)
        case .all: source.bytes
        }
    }

    private var sourceFilter: some View {
        Picker("Sources", selection: $filter) {
            ForEach(Filter.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectionCount: some View {
        if model.hasReport {
            let available = model.sources.filter(\.isAvailable).count
            let text = "\(model.selection.count) of \(available) selected"
            Text(RoomCachesVisibility.figure(text, hidden: hidden))
                .accessibilityLabel(hidden ? "Selection count hidden" : text)
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func moveFocus(_ delta: Int) -> KeyPress.Result {
        guard let focusedSource, let index = rows.firstIndex(where: { $0.id == focusedSource }) else { return .ignored }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.focusedSource = rows[min(max(0, index + delta), rows.count - 1)].id
        }
        return .handled
    }

    private func moved(_ receipt: RoomActivity, entry: RoomMakeRoomEntry?) -> some View {
        let canRestore = RoomMakeRoomCopy.footerWord(entry, receiptCanRestore: receipt.canRestore) == nil
        let present = entry?.stillInTrashBytes ?? receipt.bytes
        let caption = entry.map { RoomMakeRoomCopy.headline($0, format: format) } ?? "Moved \(format(receipt.bytes)) to Trash."
        return HStack(spacing: RoomTokens.Space.group) {
            if present > 0, entry?.stage != .unobservable {
                HStack(spacing: RoomTokens.Space.row) {
                    let count = min(42, max(1, Int((Double(present) / 200_000_000).rounded())))
                    Canvas { context, _ in
                        let dots = Path { path in
                            for dot in 0..<count {
                                path.addEllipse(in: CGRect(x: (dot % 10) * 6, y: (dot / 10) * 6, width: 4, height: 4))
                            }
                        }
                        context.stroke(dots, with: .color(RoomTokens.Ink.secondary), lineWidth: 1)
                    }
                    .frame(width: 62, height: 28)
                    .accessibilityHidden(true)
                    Text("In Trash \(format(present))")
                        .accessibilityLabel(hidden ? "In Trash, size hidden" : "In Trash \(format(present))")
                }
                    .font(RoomTokens.Typography.section).padding(.horizontal, 12).frame(height: 30)
                    .overlay {
                        Capsule().stroke(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: contrast == .increased ? 1.5 : 1, dash: [4, 3]))
                    }
            } else if let entry, entry.stage == .emptied, entry.observedGain > 0 {
                Image(systemName: "checkmark.circle").foregroundStyle(accent.text)
                    .font(RoomTokens.Typography.figure).accessibilityHidden(true)
            }
            Text(caption).font(RoomTokens.Typography.section)
            Spacer()
            if canRestore { Button("Restore") { restore(receipt) }.roomSecondary().disabled(model.isWorking || model.isScanning) }
            Button("Open Trash", action: model.openTrash).roomSecondary()
        }
        .padding(RoomTokens.Space.group)
        .overlay {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.group).strokeBorder(RoomTokens.Surface.line2)
        }
        .transition(.opacity)
    }

    private func format(_ bytes: Int64) -> String {
        RoomCachesVisibility.figure(RoomFormat.bytes(bytes), hidden: hidden)
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
