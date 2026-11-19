import SwiftUI

struct RoomCachesView: View {
    let model: RoomViewModel
    let review: () -> Void
    let inspect: (RoomSource) -> Void
    let showKept: () -> Void
    let showScanNotes: () -> Void
    let restore: (RoomActivity) -> Void

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var filter = Filter.clearable
    @FocusState private var focusedSource: String?

    private enum Filter: String, CaseIterable {
        case clearable = "Clearable", kept = "Kept", all = "All"
    }

    private var rows: [RoomSource] {
        switch filter {
        case .clearable: model.hasReport && !model.isPartialScan ? model.sources.filter(\.isAvailable) : model.sources
        case .kept: model.sources.filter { $0.bytes > $0.eligibleBytes || !$0.heldReasons.isEmpty }
        case .all: model.sources
        }
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
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text("Caches").font(RoomTokens.Typography.section).accessibilityHeading(.h1)
                Text(subtitle)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            if model.isAfterRestore {
                Text("Check again to see which caches are available.").font(RoomTokens.Typography.lead)
            } else if model.hasReport || model.isPartialScan {
                figures(presentation)
            } else if model.cachesCheckStore.check == nil {
                Text("Make a little room.").font(RoomTokens.Typography.figure)
                Text("Room checks places where apps keep files they can download or build again.")
                    .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
            }
            if !model.isScanning { primary(presentation) }
            if let receipt = model.movedReceipt { moved(receipt) }
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
        }
        .foregroundStyle(RoomTokens.Ink.graphite)
    }

    private var subtitle: String {
        if model.isScanning { return "Checking…" }
        if model.isAfterRestore { return "Put back · check again" }
        if model.movedReceipt != nil { return "Just now" }
        if model.isPartialScan { return "Stopped" }
        return model.cachesCheckStore.check?.caption(now: Date(), calendar: .current) ?? "Never checked"
    }

    private func figures(_ hero: RoomCachesHero) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            if let bytes = hero.heroBytes {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text(hero.heroLabel).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                    Text(format(bytes)).font(RoomTokens.Typography.hero.monospacedDigit())
                        .contentTransition(motion.isFull ? .numericText() : .identity)
                        .animation(motion.isFull ? .easeOut(duration: RoomTokens.Motion.count) : nil, value: bytes)
                }
            } else if !hero.lowerBound {
                Text(hero.heroLabel).font(RoomTokens.Typography.lead)
            }
            if let found = hero.foundBytes {
                statistic("Caches found", bytes: found, lowerBound: hero.lowerBound)
            }
            if let kept = hero.keptBytes {
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
            Text("\(lowerBound ? "≥ " : "")\(format(bytes))").font(RoomTokens.Typography.figure.monospacedDigit())
        }
    }

    @ViewBuilder
    private func primary(_ hero: RoomCachesHero) -> some View {
        if model.isAfterRestore {
            Button("Check caches", action: { model.scan() }).roomPrimary(accent).disabled(!model.canScan)
        } else {
            switch hero.primary {
            case .check, .checkAgain:
                Button("Check caches", action: { model.scan() }).roomPrimary(accent).disabled(!model.canScan)
            case .chooseFolderAndCheck:
                Button("Choose Folder & Check") {
                    #if ROOM_APP_STORE
                    model.chooseStoreFolder(scanAfterApproval: true)
                    #else
                    model.scan()
                    #endif
                }
                .roomPrimary(accent).disabled(!model.canScan)
            case .review(let bytes):
                if model.movedReceipt == nil || bytes > 0 {
                    Button(bytes > 0 ? "Review \(format(bytes))" : "Review", action: review)
                        .roomPrimary(accent).disabled(!model.canReviewCleanup)
                        .help(hero.disabledReason ?? "Review the selected caches.")
                }
            case .none: EmptyView()
            }
        }
    }

    private var startingPlaces: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text("Where Room looks").font(RoomTokens.Typography.section)
            ForEach(model.checkLocations, id: \.self) { path in
                Text(path).font(RoomTokens.Typography.caption.monospaced())
                    .foregroundStyle(RoomTokens.Ink.secondary).textSelection(.enabled)
            }
        }
    }

    private var comparison: some View {
        RoomBeforeAfterView(sources: model.sources, selection: model.selection, format: format)
            .frame(minWidth: 264, maxWidth: .infinity, alignment: .topLeading)
            .padding(RoomTokens.Space.group)
            .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack {
                Text("Sources").font(RoomTokens.Typography.section)
                Spacer()
                Picker("Sources", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            if model.hasReport {
                Text("\(model.selection.count) of \(model.sources.filter(\.isAvailable).count) selected")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            ForEach(rows) { source in
                RoomCachesRow(source: source, selected: model.selection.contains(source.id),
                    canSelect: model.hasReport && !model.isWorking && !model.isScanning && !source.isPartial && source.isAvailable,
                    focus: $focusedSource, format: format, select: { model.toggleSelection(id: source.id) },
                    inspect: { inspect(source) }, reveal: { model.reveal(source: source) })
            }
            if rows.isEmpty { Text("No sources in this view.").font(RoomTokens.Typography.caption) }
        }
        .onKeyPress(.upArrow) { moveFocus(-1) }
        .onKeyPress(.downArrow) { moveFocus(1) }
        .frame(minWidth: 270, maxWidth: .infinity, alignment: .topLeading)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
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

    private func moved(_ receipt: RoomActivity) -> some View {
        HStack(spacing: RoomTokens.Space.group) {
            Text("In Trash \(format(receipt.bytes))")
                .font(RoomTokens.Typography.section).padding(.horizontal, 12).frame(height: 30)
                .overlay {
                    Capsule().stroke(RoomTokens.Surface.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            Text("Moved \(format(receipt.bytes)) to Trash.").font(RoomTokens.Typography.section)
            Spacer()
            if receipt.canRestore { Button("Restore") { restore(receipt) }.roomSecondary() }
            Button("Open Trash", action: model.openTrash).roomSecondary()
        }
        .padding(RoomTokens.Space.group)
        .overlay {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.group).strokeBorder(RoomTokens.Surface.line2)
        }
        .transition(.opacity)
    }

    private func format(_ bytes: Int64) -> String { RoomFormat.overviewBytes(bytes) }
}
