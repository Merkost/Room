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

    var body: some View {
        let presentation = hero
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            if model.isAfterRestore {
                headline(presentation, symbol: "arrow.clockwise") {
                    Text("Check again after restoring").font(RoomTokens.Typography.lead)
                }
            } else if model.isScanning {
                if model.totalBytes > 0 { headline(presentation) { figures(presentation) } }
                scanStatus
                    .roomPanelArrival()
            } else if model.isPartialScan && model.totalBytes == 0 {
                RoomEmptyFeedback(title: "Check incomplete",
                    message: "Start a new check to measure caches.", symbol: "magnifyingglass", prominent: true) {
                    startAction
                }
            } else if model.hasReport && model.clearableBytes == 0 {
                if model.movedReceipt == nil || !model.sources.isEmpty || !model.protectedSources.isEmpty {
                    completedFeedback(presentation)
                }
            } else if model.hasReport || model.isPartialScan {
                headline(presentation) { figures(presentation) }
            } else {
                startPanel
            }
            #if ROOM_APP_STORE
            if let batch = model.npmBatch, batch.isBatch {
                HStack(spacing: RoomTokens.Space.inner) {
                    Label(batch.hasMore ? "npm totals reflect this batch" : "Last npm batch",
                          systemImage: "shippingbox")
                        .font(RoomTokens.Typography.body)
                    Spacer(minLength: 0)
                    if batch.hasMore {
                        Button(action: model.continueNPM) {
                            Label("Next npm Batch", systemImage: "arrow.right")
                        }
                        .roomSecondary()
                        .disabled(!model.canContinueNPM)
                        .accessibilityIdentifier("RoomCachesNextNPMBatch")
                    }
                }
                .help("npm sizes and selections apply to the current batch.")
            }
            #endif
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
                .roomPanelChange(model.isScanning)
            } else if !model.isScanning && !model.hasReport && !model.isPartialScan && !model.isAfterRestore {
                startingPlaces
            }
            if !model.scanIssues.isEmpty {
                Button(action: showScanNotes) {
                    Label("Scan notes", systemImage: "list.bullet.clipboard")
                }
                .roomLink(accent)
            }
            if let undo {
                HStack {
                    Text("Room won’t suggest \(undo.name) again.")
                    Button("Undo") { restoreSuggestion(undo) }.roomLink(accent)
                        .disabled(model.isScanning || model.isWorking)
                }
                .font(RoomTokens.Typography.caption)
                .roomPanelArrival()
            }
        }
        .foregroundStyle(RoomTokens.Ink.graphite)
        .task(id: undo) {
            guard undo != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            undo = nil
        }
    }

    private var startPanel: some View {
        let title: String
        let message: String
        if model.cachesCheckStore.check != nil {
            title = "Check caches again"
            message = needsFolderApproval
                ? "Choose a folder to see which caches you can clear now."
                : "Run a fresh check to see which caches you can clear now."
        } else {
            title = "Find caches you can clear"
            message = needsFolderApproval
                ? "Choose a folder to check, then review what can move to Trash."
                : "Check for temporary files, then review what can move to Trash."
        }
        return RoomStartPanel(title: title, message: message, artwork: .caches) {
            startAction
        }
    }

    @ViewBuilder
    private func completedFeedback(_ hero: RoomCachesHero) -> some View {
        if model.measuredSourceCount > 0 && model.readableSourceCount == 0 {
            RoomEmptyFeedback(title: "Room couldn’t read the caches",
                message: "Check folder access and try again.", symbol: "folder.badge.questionmark", prominent: true) {
                primary(hero)
            }
        } else if !model.sources.isEmpty || !model.protectedSources.isEmpty {
            RoomEmptyFeedback(title: "Nothing ready to clear",
                message: "The items from this check stay in place.", symbol: "shield", prominent: true) {
                Button(action: showKept) {
                    Label("What stays", systemImage: "shield")
                }
                .roomSecondary()
            }
        } else {
            RoomEmptyFeedback(title: model.hasPartialMeasurements ? "No caches measured" : "No caches found",
                message: model.hasPartialMeasurements
                    ? "This check covered only part of the available locations."
                    : "Room found no cache files in the locations it checked.",
                symbol: model.hasPartialMeasurements ? "tray" : "checkmark.circle", prominent: true) {
                startAction
            }
        }
    }

    private var scanStatus: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.inner) {
                cacheIcon("magnifyingglass")
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text("Checking caches…")
                        .font(RoomTokens.Typography.title)
                        .accessibilityHeading(.h1)
                    if model.scanLocationCount > 0 {
                        let completed = model.scannedLocationCount
                        let total = model.scanLocationCount
                        RoomMaskable(String(localized: "\(completed) of \(total) locations checked"))
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: model.cancelScan) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .roomSecondary()
            }
            if let progress = model.scanProgress, model.scanLocationCount > 0, !hidden {
                ProgressView(value: progress)
                    .tint(accent.fill)
                    .accessibilityLabel("Cache check progress")
            }
        }
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        .accessibilityIdentifier("RoomCachesScanStatus")
    }

    private func cacheIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(RoomTokens.Typography.lead)
            .foregroundStyle(accent.text)
            .frame(width: RoomTokens.Space.breath2, height: RoomTokens.Space.breath2)
            .background(accent.wash, in: .rect(cornerRadius: RoomTokens.Radius.card))
            .accessibilityHidden(true)
    }

    private func headline<Summary: View>(_ hero: RoomCachesHero, symbol: String = "tray.full",
                                         @ViewBuilder summary: () -> Summary) -> some View {
        let content = HStack(spacing: RoomTokens.Space.inner) {
            cacheIcon(symbol)
            summary()
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: RoomTokens.Space.group) {
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
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private func figures(_ hero: RoomCachesHero) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: RoomTokens.Space.breath1) {
            if let bytes = hero.heroBytes {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text(hero.heroLabel).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    metric(format(bytes, hero: true), number: RoomTokens.Typography.hero, unit: RoomTokens.Typography.counter)
                        .roomNumericTransition(format(bytes, hero: true), enabled: !model.isScanning)
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
                Button(action: showKept) {
                    Label("What stays", systemImage: "shield")
                }
                .roomLink(accent)
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
        if model.isAfterRestore || model.isPartialScan {
            startAction
        } else {
            switch hero.primary {
            case .check, .checkAgain:
                checkButton
            case .chooseFolderAndCheck:
                chooseFolderButton
            case .review(let bytes):
                if model.movedReceipt == nil || bytes > 0 {
                    Button(action: review) {
                        Label(bytes > 0 ? "Review \(format(bytes))" : "Review", systemImage: "checklist")
                    }
                    .roomScreenPrimary(accent).disabled(!model.canReviewCleanup) // one-filled: exclusive with Check (hero.primary switch)
                    .help(hero.disabledReason ?? "Review the selected caches.")
                }
            case .none: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var startAction: some View {
        if needsFolderApproval { chooseFolderButton } else { checkButton }
    }

    private var chooseFolderButton: some View {
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
        .roomScreenPrimary(accent) // one-filled: exclusive with Check (Store folder approval)
        .disabled(!model.canScan)
    }

    private var checkButton: some View {
        Button(action: model.scan) {
            Label(String(localized: "caches.action.check", defaultValue: "Check caches", table: "Caches",
                bundle: RoomCopy.bundle), systemImage: "magnifyingglass")
        }
        .roomScreenPrimary(accent)
        .disabled(!model.canScan)
    }

    @ViewBuilder
    private var startingPlaces: some View {
        let groups = model.checkLocations
        if !groups.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    if !isStore {
                        Text(model.isDeepScan
                            ? "Full checks can find more locations. Full Disk Access is optional."
                            : "Full Disk Access is optional.")
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            locationRow(group)
                            if group.id != groups.last?.id { Rectangle().fill(RoomTokens.Surface.line).frame(height: 1) }
                        }
                    }
                }
                .padding(.top, RoomTokens.Space.row)
            } label: {
                Label("Where Room looks", systemImage: "folder")
                    .font(RoomTokens.Typography.section)
                    .accessibilityHeading(.h2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RoomTokens.Space.group)
            .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        }
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
        RoomBeforeAfterView(sources: model.sources, selectedBytes: model.selectedBytes(for:), format: format)
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
            VStack(spacing: RoomTokens.Space.row) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, source in
                    RoomCachesRow(source: source, displayedBytes: displayedBytes(source), selected: model.selection.contains(source.id),
                        partiallySelected: model.partiallySelectedSource(source.id),
                        canSelect: model.canEditSelection && source.isAvailable,
                        focus: $focusedSource, format: format, select: { model.toggleSelection(id: source.id) },
                        inspect: { inspect(source) }, reveal: { model.reveal(source: source) },
                        neverSuggest: source.isAvailable && model.ignoreStore != nil ? { neverSuggest(source) } : nil)
                        .transition(cacheRemoval(index: index))
                }
            }
            .animation(motion.isFull && !hidden && model.movedReceiptID != nil ? RoomTokens.Motion.standard : nil,
                       value: model.movedReceiptID)
            .transaction(value: hide) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            if rows.isEmpty, model.hasReport, !(filter == .clearable && model.clearableBytes == 0) {
                RoomEmptyFeedback(title: filter == .kept ? "No kept caches in this list" : "No matching caches",
                    message: "Show all cache sources from this check.", symbol: "line.3.horizontal.decrease.circle") {
                    Button("Show all") { filter = .all }
                        .roomSecondary()
                }
            }
        }
        .onKeyPress(.upArrow) { moveFocus(-1) }
        .onKeyPress(.downArrow) { moveFocus(1) }
        .frame(minWidth: 270, maxWidth: .infinity, alignment: .topLeading)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

    private func cacheRemoval(index: Int) -> AnyTransition {
        guard motion.isFull, !hidden else { return .identity }
        let delay = Double(min(index, RoomTokens.Motion.maxStaggered - 1)) * RoomTokens.Motion.stagger
        return .asymmetric(insertion: .identity,
            removal: .offset(y: -RoomTokens.Space.row).combined(with: .opacity)
                .animation(RoomTokens.Motion.standard.delay(delay)))
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
        if model.hasReport, model.clearableBytes > 0 {
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
            if canRestore {
                Button { restore(receipt) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .roomSecondary()
                    .disabled(model.isWorking || model.isScanning)
            }
            Button(action: model.openTrash) { Label("Open Trash", systemImage: "trash") }.roomSecondary()
        }
        .padding(RoomTokens.Space.group)
        .overlay {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.group).strokeBorder(RoomTokens.Surface.line2)
        }
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
