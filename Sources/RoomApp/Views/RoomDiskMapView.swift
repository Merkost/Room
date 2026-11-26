import AppKit
import QuickLook
import RoomCore
import SwiftUI

struct RoomDiskMapView: View {
    @Bindable var insights: RoomInsightsModel
    var rooms: RoomRoomsModel? = nil
    var savedViews: RoomSavedViewsStore? = nil
    var savedViewDisplay: RoomSavedViewDisplay? = nil
    var openSavedView: (UUID) -> Void = { _ in }
    var canInspectCacheSource: (URL) -> Bool = { _ in false }
    var inspectCacheSource: (URL) -> Void = { _ in }
    var cleanupAction: (RoomMapCleanupTarget) -> RoomMapCleanupAction? = { _ in nil }
    var activateCleanup: (RoomMapCleanupTarget) -> Void = { _ in }
    /// Disk Map folder moves (Direct). nil: no ticks.
    var folderTrash: RoomFolderTrashModel? = nil
    var folderMoved: (FolderTrashReceipt) -> Void = { _ in }
    @Environment(\.openSettings) private var openSettings
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var privacy
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomScreenInsets) private var screenInsets
    private var hidden: Bool { privacy.masksNow }
    @State private var layout: Display = .map
    @State private var filter: String?
    @State private var showsInspector = false
    @State private var hidesWideInspector = false
    @State private var showsIssues = false
    @State private var showsOther = false
    @State private var otherDetails: RoomTreeNode.OtherGroup?
    @State private var previewURL: URL?
    @State private var previewScope: URL?
    @State private var mapGeneration = 0
    @State private var mapStep: RoomMapStep?
    @State private var pointer = RoomMapPointer()
    @State private var draftView: SavedViewDraft?
    @State private var selection = RoomMapSelection()
    @State private var folderReview: RoomFolderTrashModel.Review?
    @State private var protectionNote: String?
    @State private var zoomAnchor = UnitPoint.center
    @State private var zoomInward = true

    private struct SavedViewDraft: Identifiable {
        let id = UUID()
        let root: RoomTreeLocation
        let path: String
        let mode: RoomSavedViewMode
        let kind: StorageKind?
        let name: String
    }

    private var showsMap: Bool { savedViewDisplay?.showsMap ?? true }
    private var showsFolderStart: Bool { showsMap && model.current == nil && !insights.isScanningDisk }

    private enum Display: String, CaseIterable { case map = "Map", largest = "Largest 20", compare = "Compare" }
    private var model: RoomDiskMapModel { insights.diskMap }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - screenInsets.leading - screenInsets.trailing
            let isWide = contentWidth >= RoomTokens.Map.inspectorBreakpoint
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                if showsMap, let level = model.level, let words = diskWords(level) {
                    RoomHeadlineView(headline: words.headline,
                                     compact: contentWidth < RoomTokens.Screen.compactBreakpoint)
                        .padding(.top, RoomTokens.Screen2.headlineTop)
                    Text(words.supporting)
                        .font(RoomTokens.Screen2.supporting)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .padding(.bottom, RoomTokens.Space.row)
                }
                controls(isWide: isWide)
                if let blueprint = model.blueprint,
                   insights.isScanningDisk || (blueprint.phase == .stopped && insights.diskReport?.cancelled == true &&
                       layout == .map && model.levelPath.isEmpty) {
                    if insights.isScanningDisk, let total = blueprint.topLevelTotal, total > 0 {
                        RoomScanSegments(done: blueprint.measuredCount, total: total)
                    }
                    blueprintDetail(blueprint, isWide: isWide)
                } else if let savedViewDisplay, !savedViewDisplay.showsMap {
                    savedViewPlaceholder(savedViewDisplay)
                } else if let level = model.level {
                    if model.hasLostAccess { accessNotice }
                    if savedViewDisplay?.result == .rootOnly {
                        Label("The saved folder is no longer in this map. Showing its root.", systemImage: "folder")
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                    details(level, isWide: isWide)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .roomPanelArrival(enabled: model.blueprint?.phase == .done)
                } else {
                    folderStart
                }
                if showsMap, let level = model.level, !insights.isScanningDisk {
                    footer(level)
                }
            }
            .padding(screenInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: insights.diskInspectorRequest) { _, _ in
                toggleInspector(isWide: isWide)
            }
            .onChange(of: isWide ? !hidesWideInspector : showsInspector, initial: true) { _, visible in
                insights.setDiskInspectorVisible(visible)
            }
            .onChange(of: isWide) { _, wide in if wide { showsInspector = false } }
            .onChange(of: insights.diskComparisonRequest) { _, _ in
                if model.canCompare { layout = .compare }
            }
            .inspector(isPresented: $showsInspector) {
                inspector
                    .inspectorColumnWidth(RoomTokens.Map.inspectorWidth)
            }
        }
        .background(RoomTokens.Surface.canvas)
        .quickLookPreview($previewURL)
        .onChange(of: hidden) { _, value in
            if value { previewURL = nil }
        }
        .onChange(of: previewURL) { _, current in
            if current == nil { releasePreviewScope() }
        }
        .onDisappear { releasePreviewScope() }
        .task { if savedViewDisplay == nil { await insights.restoreDiskMap() } }
        .task(id: savedViewDisplay?.requestID) {
            guard let display = savedViewDisplay, display.showsMap else { return }
            roomWithoutMotion {
                layout = display.view.mode == .map ? .map : .largest
                filter = display.view.kind?.rawValue
            }
        }
        .task { await insights.observeTreeChanges() }
        .onChange(of: model.current) { _, _ in
            // A rescan or another map: ticks only survive for rooms that are still here.
            selection.keep(only: Set(model.level?.children.map(\.relativePath) ?? []))
        }
        .onChange(of: hidden) { _, _ in protectionNote = nil }
        .onChange(of: insights.isScanningDisk) { _, scanning in
            // Ticks belong to the sizes on screen; a rescan, even a stopped one, starts without them.
            if scanning {
                selection.clear()
                protectionNote = nil
            }
        }
        .onChange(of: model.levelPath) { _, path in
            selection.clear()
            protectionNote = nil
            filter = nil
            pointer.item = nil
            if mapStep?.destination != path { mapStep = nil }
        }
        .onChange(of: model.current?.rootID) { _, _ in
            filter = nil
            layout = .map
            mapStep = nil
        }
        .onChange(of: model.current) { _, _ in pointer.item = nil }
        .task(id: pickKey) { pickLargest() }
        .onChange(of: filter) { _, _ in pointer.item = nil }
        .onChange(of: layout) { _, _ in
            mapStep = nil
            pointer.item = nil
        }
        .onChange(of: model.canCompare) { _, available in
            if !available, layout == .compare { layout = .map }
        }
        .onChange(of: motion.isFull) { _, _ in roomWithoutMotion { mapStep = nil } }
        .sheet(item: $draftView) { draft in
            RoomSavedViewNameEditor(title: "Save View", action: "Save", name: draft.name) { name in
                guard insights.savedViewLocation() == draft.root else { return false }
                return savedViews?.add(name: name, root: draft.root, nodePath: draft.path, kind: draft.kind,
                                       mode: draft.mode) != nil
            }
        }
        .sheet(item: $folderReview) { review in
            if let folderTrash {
                RoomFolderReviewSheet(review: review, model: folderTrash) { receipt in
                    selection.clear()
                    if let receipt { folderMoved(receipt) }
                }
            }
        }
        .sheet(isPresented: $showsIssues) {
            RoomScanIssuesSheet(issues: insights.diskReport?.issues.map { hidden ? "Path hidden" : "\($0.url.path): \($0.message)" } ?? [])
        }
        .sheet(isPresented: $showsOther) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                Text("Other").font(RoomTokens.Typography.title)
                if let other = otherDetails {
                    Text(hidden ? "Size hidden" : "\(other.itemCount.formatted()) small items · \(other.isPartial ? "≥ " : "")\(RoomFormat.gb(other.allocatedBytes))")
                }
                Text("These items were measured together. Open a mapped folder to see its retained items.")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Button("Done") { showsOther = false }.keyboardShortcut(.defaultAction)
            }
            .padding(RoomTokens.Space.breath1)
        }
    }

    private func diskWords(_ level: RoomTreeNode) -> RoomDiskMapWords? {
        guard let current = model.current else { return nil }
        return RoomDiskMapWords.make(levelName: level.name, atRoot: model.levelPath.isEmpty,
                                     rootIsHome: insights.diskMap.rootURL.map(RoomDiskMapWords.isHome) ?? false,
                                     bytes: level.allocatedBytes, partial: level.isPartial,
                                     folders: level.children.filter(\.isDirectory).count, scannedAt: current.scannedAt, now: Date())
    }

    private func controls(isWide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.inner) {
                location
                Spacer(minLength: 0)
                viewActions(isWide: isWide)
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                location
                viewActions(isWide: isWide)
            }
        }
        .frame(minHeight: RoomTokens.Map.controlsHeight)
    }

    @ViewBuilder private var location: some View {
        if showsMap, model.level != nil {
            HStack(spacing: RoomTokens.Space.row) {
                RoomBreadcrumbs(trail: model.trail, hidden: hidden) {
                    step(to: $0, animated: NSApp.currentEvent?.type == .leftMouseUp)
                }
                // The headline carries the size now (nav-v3); the crumb stays a crumb.
                if insights.canGoBackToHomeMap {
                    Button { Task { await insights.showHomeMap() } } label: {
                        Label("Back to home folder", systemImage: "house")
                            .font(RoomTokens.Typography.caption)
                    }
                    .roomSecondary(.small)
                    .fixedSize()
                    .accessibilityIdentifier("RoomDiskMapBackHome")
                }
            }
            .help(model.current.map { "Scanned \($0.scannedAt.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))" } ?? "")
        }
    }

    private var accessNotice: some View {
        HStack(spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Saved map").font(RoomTokens.Typography.section)
                Text(hidden ? "Choose the folder again to rescan." :
                     "Room lost access to \(model.current?.displayPath ?? "this folder").")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Choose Folder Again…", action: insights.chooseDiskFolder)
                .roomSecondary()
                .fixedSize()
                .disabled(!insights.canChooseDiskLocation)
        }
        .padding(RoomTokens.Space.inner)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
    }

    /// The mockup's crumb row carries nothing else, so the view switch, inspector, folders and saved views share one
    /// quiet "View" menu at its right end (keyboard and menu bar commands are unchanged). Rescan sits in the footer.
    private func viewActions(isWide: Bool) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            if insights.isScanningDisk {
                Button("Stop", action: insights.cancelDiskScan).roomQuiet(large: true)
                    .accessibilityIdentifier("RoomDiskStopButton")
            }
            Menu {
                if showsMap, model.current != nil, !insights.isScanningDisk {
                    Picker("Show", selection: $layout) {
                        Text(Display.map.rawValue).tag(Display.map)
                        Text(Display.largest.rawValue).tag(Display.largest)
                        if model.canCompare { Text(Display.compare.rawValue).tag(Display.compare) }
                    }
                    .pickerStyle(.inline)
                    let inspectorVisible = isWide ? !hidesWideInspector : showsInspector
                    Button(inspectorVisible ? "Hide Inspector" : "Show Inspector") { toggleInspector(isWide: isWide) }
                    Divider()
                }
                folders
                if let savedViews, !showsFolderStart || !savedViews.visible.isEmpty {
                    viewsMenu(savedViews)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(layout == .map ? "View" : layout.rawValue)
                    Text(verbatim: "›").foregroundStyle(RoomTokens.Ink.tertiary)
                }
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel("Disk Map view options")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var pickKey: String {
        model.levelPath + "|" + (model.current?.rootID ?? "") + "|\(model.level?.children.count ?? -1)"
    }

    /// The room being looked at: the clicked one, else the largest folder (mockup: the first room is "on").
    private func shownPick(_ level: RoomTreeNode) -> String? {
        model.selectedPath ?? level.children.filter(\.isDirectory).max { $0.allocatedBytes < $1.allocatedBytes }?.relativePath
    }

    /// Like the mockup, the largest room is the one being looked at until another is clicked.
    private func pickLargest() {
        guard model.selectedPath == nil, let first = model.level?.children.first(where: { $0.isDirectory }) else { return }
        model.select(first.relativePath)
    }

    private func toggleInspector(isWide: Bool) {
        if isWide { hidesWideInspector.toggle() }
        else { showsInspector.toggle() }
    }

    private var rescanTitle: String { model.current?.cancelled == true ? "Map Again" : "Rescan" }

    private var folders: some View {
        Menu(showsFolderStart ? "Folder Options" : "Folders") {
            if !showsFolderStart {
                Button("Choose Folder to Map…", action: insights.chooseDiskFolder)
                    .disabled(!insights.canChooseDiskLocation)
                if showsMap, model.current != nil {
                    Button(model.current?.cancelled == true ? "Map This Folder Again" : "Rescan This Folder", action: insights.rescanDisk)
                        .disabled(!insights.canRescanDisk)
                }
                if !insights.accessFolders.isEmpty {
                    Divider()
                    Menu("Open Folder") { approvedFolderButtons }
                        .disabled(!insights.canChooseDiskLocation)
                    Menu("Map Approved Folder") {
                        ForEach(insights.accessFolders) { folder in
                            Button(hidden ? "Folder" : folder.name) { insights.scanDisk(url: folder.url) }
                        }
                    }
                    .disabled(!insights.canChooseDiskLocation)
                }
                Divider()
            } else if model.pendingFolder != nil, !insights.accessFolders.isEmpty {
                Menu("Open Approved Folder") { approvedFolderButtons }
                    .disabled(!insights.canChooseDiskLocation)
                Divider()
            }
            #if !ROOM_APP_STORE
            Button("Map Home Folder", action: insights.scanHome).disabled(!insights.canChooseDiskLocation)
            Button("Map Applications", action: insights.mapApplications).disabled(!insights.canChooseDiskLocation)
            Button("Full Disk Access…", action: insights.openPrivacySettings)
            Divider()
            #endif
            Button("Manage Folder Access…") {
                insights.requestedSettingsTab = .folders
                openSettings()
            }
        }
        .accessibilityIdentifier("RoomDiskChangeFolderButton")
    }

    private var approvedFolderButtons: some View {
        ForEach(insights.accessFolders) { folder in
            Button(hidden ? "Folder" : folder.name) { insights.openDiskMap(rootURL: folder.url) }
        }
    }

    private func viewsMenu(_ store: RoomSavedViewsStore) -> some View {
        Menu("Views") {
            Button("Save View…") { prepareSavedView() }
                .disabled(!store.canAdd || !showsMap || layout == .compare || insights.savedViewLocation() == nil)
            if !store.visible.isEmpty {
                Divider()
                ForEach(store.visible) { view in
                    Button(hidden ? "Saved View" : view.name) { openSavedView(view.id) }
                        .disabled(!insights.canChooseDiskLocation)
                }
            }
        }
        .accessibilityIdentifier("RoomDiskSavedViewsMenu")
    }

    private func prepareSavedView() {
        guard layout != .compare, let root = insights.savedViewLocation(), let level = model.level else { return }
        let kind = filter.flatMap(StorageKind.init(rawValue:))
        let mode: RoomSavedViewMode = layout == .largest ? .largest : .map
        let suggested: String
        if hidden {
            suggested = "Disk Map View"
        } else if mode == .largest {
            suggested = "Largest 20 in \(level.name)"
        } else if let kind {
            suggested = "\(kind.title) in \(level.name)"
        } else {
            suggested = level.name
        }
        draftView = SavedViewDraft(root: root, path: model.levelPath, mode: mode, kind: kind,
                                   name: RoomSavedView.cleanName(String(suggested.prefix(80))) ?? "Disk Map View")
    }

    private func savedViewPlaceholder(_ display: RoomSavedViewDisplay) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            RoomMaskable(display.view.name, kind: .name)
                .font(RoomTokens.Typography.title).accessibilityHeading(.h1)
            if display.result == .needsAccess {
                Label("Folder access is needed to open this view.", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Button("Manage Folder Access…") {
                    insights.requestedSettingsTab = .folders
                    openSettings()
                }
                .roomSecondary()
            } else if display.result == .unavailable {
                Label("Room couldn’t open this view.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Button("Try Again") { openSavedView(display.view.id) }
                    .roomSecondary()
                    .disabled(!insights.canChooseDiskLocation)
            } else {
                ProgressView("Opening saved view…").controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private var folderStart: some View {
        if let pending = model.pendingFolder {
            RoomStartPanel(title: "This folder has no map yet",
                           message: hidden ? "Map this folder to see what takes up space." :
                               "Map “\(pending.lastPathComponent)” to see what takes up space.",
                           artwork: .map) {
                Button("Map This Folder") { insights.scanDisk(url: pending) }
                    .roomScreenPrimary(accent, hero: true) // one-filled: exclusive start panel, shown only before a map exists
                    .disabled(!insights.canChooseDiskLocation)
                    .accessibilityIdentifier("RoomDiskMapPendingFolder")
                Button("Choose Another Folder…", action: insights.chooseDiskFolder)
                    .roomSecondary()
                    .disabled(!insights.canChooseDiskLocation)
            }
        } else {
            RoomStartPanel(title: "See what’s taking up space",
                           message: "Map a folder, including its hidden files. Your files stay in place.",
                           artwork: .map) {
                Button(action: insights.chooseDiskFolder) {
                    Label("Choose Folder & Map…", systemImage: "magnifyingglass")
                }
                .roomScreenPrimary(accent, hero: true) // one-filled: exclusive start panel, shown only before a map exists
                .disabled(!insights.canChooseDiskLocation)
                .accessibilityIdentifier("RoomDiskChooseFolder")
                if !insights.accessFolders.isEmpty {
                    Menu("Approved Folders") { approvedFolderButtons }
                        .controlSize(.large)
                        .disabled(!insights.canChooseDiskLocation)
                        .accessibilityIdentifier("RoomDiskApprovedFolders")
                }
            }
        }
    }

    private func details(_ level: RoomTreeNode, isWide: Bool) -> some View {
        let visible = layout == .compare ? level : filtered(level)
        let hasOther = (visible.other?.allocatedBytes ?? 0) > 0
        let hasItems = hasOther || (layout == .map
            ? visible.children.contains(where: { $0.allocatedBytes > 0 })
            : !visible.children.isEmpty)
        return VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            if layout == .largest, hasItems { RoomMapKindControl(node: level, hidden: hidden, filter: $filter) }
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    if layout != .compare, !hasItems {
                        emptyMap(level)
                        readout(visible, hint: false)
                    } else if layout == .map {
                        RoomDiskRoomsView(rooms: diskRooms(level), picked: shownPick(level), selection: selection,
                                          ticksAvailable: ticksAvailable, pick: { model.select($0); protectionNote = nil },
                                          toggle: toggleTick, stepInside: { stepInside($0, from: $1) })
                            .id(level.relativePath)
                            .transition(RoomDiskZoom.transition(inward: zoomInward, anchor: zoomAnchor, motion: motion))
                            // The map takes the room the window has (no dead band under it at any height).
                            .frame(minHeight: RoomTokens.Screen2.planHeight, maxHeight: .infinity)
                            .layoutPriority(1)
                        inspectorLine(level)
                    } else if layout == .compare, let compared = model.comparison {
                        RoomCompareOverlay(earlier: compared.earlier, current: level, earlierDate: compared.date, hidden: hidden) {
                            layout = .map
                        }
                        .frame(minHeight: RoomTokens.Map.minimumHeight)
                    } else {
                        RoomLargestTable(level: visible, hidden: hidden, selection: model.selectedPath) {
                            activate($0, false, false)
                        }
                        readout(visible, hint: false)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .roomPanelChange(layout)
                if isWide && !hidesWideInspector && layout != .map { wideInspector }
            }
        }
    }

    // MARK: Room map (nav-v3)

    private var ticksAvailable: Bool { RoomFolderTrashModel.isAvailable && folderTrash != nil }

    /// Folders that are in Trash now and were moved after this map was made. Restore or a rescan brings them back.
    private var trashedPaths: Set<String> {
        guard let folderTrash, let mapped = model.current?.scannedAt else { return [] }
        return Set(folderTrash.receipts.filter { $0.date > mapped }.flatMap(\.items)
            .filter { $0.status == .trashed }.map(\.originalPath))
    }

    private static func holdsLibrary(_ node: RoomTreeNode) -> Bool {
        let ext = (node.name as NSString).pathExtension.lowercased()
        return FolderTrashEngine.libraryExtensions.contains(ext) || node.children.contains(where: holdsLibrary)
    }

    private func diskRooms(_ level: RoomTreeNode) -> [RoomDiskRoom] {
        let trashed = trashedPaths
        let visible = level.children.filter { child in
            child.allocatedBytes > 0 && !(model.url(for: child.relativePath).map { trashed.contains($0.standardizedFileURL.path) } ?? false)
        }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
        let limit = RoomDiskRoomsLayout.kept(visible.map(\.allocatedBytes), foldedBytes: level.other?.allocatedBytes ?? 0)
        var rooms = visible.prefix(max(1, limit)).map { child -> RoomDiskRoom in
            let url = model.url(for: child.relativePath)
            let protection: FolderProtection? = !child.isDirectory ? .notAFolder
                : child.isPartial ? .unverified
                : (folderTrash?.protection(for: url) ?? (Self.holdsLibrary(child) ? .containsLibrary : nil))
            let resolved = folderTrash == nil ? .unverified : protection
            let kind = child.kindBytes.max { $0.value < $1.value }.flatMap { StorageKind(rawValue: $0.key) }
            return RoomDiskRoom(room: .init(path: child.relativePath, name: child.name, bytes: child.allocatedBytes,
                                            protection: resolved),
                                kind: kind, canStepInside: child.isDirectory && child.canStepInside, isOther: false)
        }
        let folded = visible.dropFirst(max(1, limit)).reduce(Int64(0)) { $0 + $1.allocatedBytes } + (level.other?.allocatedBytes ?? 0)
        if folded > 0 {
            rooms.append(RoomDiskRoom(room: .init(path: level.relativePath + "\u{0}other", name: "Other", bytes: folded,
                                                  protection: .unverified),
                                      kind: nil, canStepInside: false, isOther: true))
        }
        return rooms
    }

    private func toggleTick(_ room: RoomDiskRoom) {
        if let protection = selection.toggle(room.room) {
            protectionNote = protection.sentence(name: hidden ? "this folder" : room.room.name)
        } else {
            protectionNote = nil
        }
    }

    private func stepInside(_ path: String, from anchor: UnitPoint) {
        zoomAnchor = anchor
        zoomInward = true
        let pointer = RoomSelectionOrigin.controlActivation == .pointer
        if pointer, let animation = motion.animation(RoomTokens.Motion.zoom, fallback: RoomTokens.Motion.fade) {
            withAnimation(animation) { _ = model.go(to: path) }
        } else {
            _ = model.go(to: path)
        }
    }

    private func placeName(_ level: RoomTreeNode) -> String {
        if model.levelPath.isEmpty, insights.diskMap.rootURL.map(RoomDiskMapWords.isHome) == true { return "your home" }
        return hidden ? "this folder" : level.name
    }

    @ViewBuilder private func inspectorLine(_ level: RoomTreeNode) -> some View {
        let rooms = diskRooms(level).map(\.room)
        HStack(spacing: RoomTokens.Space.group) {
            if !selection.isEmpty {
                RoomMaskable(selection.line(in: rooms, levelBytes: level.allocatedBytes, place: placeName(level)))
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Spacer(minLength: 0)
                Button("Clear") { selection.clear() }.roomLink(accent)
            } else if let path = shownPick(level), let room = rooms.first(where: { $0.path == path }),
                      let node = level.children.first(where: { $0.relativePath == path }) {
                let share = level.allocatedBytes > 0 ? Int((Double(room.bytes) / Double(level.allocatedBytes) * 100).rounded()) : 0
                HStack(spacing: 6) {
                    RoomMaskable(room.name, kind: .name).fontWeight(.semibold).foregroundStyle(RoomTokens.Ink.graphite)
                    RoomMaskable("\(RoomFormat.gb(room.bytes)), \(share)% of \(placeName(level))").foregroundStyle(RoomTokens.Ink.secondary)
                }
                Spacer(minLength: 0)
                if node.isDirectory && node.canStepInside {
                    Button("Step inside") { stepInside(path, from: .center) }.roomLink(accent)
                }
                Button("Show in Finder") { reveal(path) }.roomLink(accent).disabled(hidden)
                if let rooms = self.rooms, let url = model.url(for: path), node.isDirectory {
                    Button("Pin as a Room") { rooms.pin(url: url) }.roomLink(accent).disabled(!rooms.canChooseFolder)
                }
            } else {
                Text("Click a room to look at it, click again to step inside")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Spacer(minLength: 0)
            }
        }
        .font(RoomTokens.Typography.body)
        .lineLimit(1)
        .frame(minHeight: 24)
    }

    private func footer(_ level: RoomTreeNode) -> some View {
        let ticking = layout == .map && !selection.isEmpty
        let rooms = layout == .map ? diskRooms(level) : []
        let note = layout != .map ? "Room reads sizes only. Nothing moves from here"
            : protectionNote ?? (ticking ? "Nothing moves without a review"
                : ticksAvailable ? "Tick rooms to move them to Trash. ⌘-click works too" : "Room reads sizes only. Nothing moves from here")
        let noteText = Text(note).font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
        let actions = HStack(spacing: RoomTokens.Space.group) {
            // A map whose folder access is gone cannot be rescanned; the access notice above carries that action.
            if !model.hasLostAccess {
                // While rooms are ticked the row is about them; mapping elsewhere stays in View > Folders.
                if !ticking {
                    Button("Map Another Folder…", action: insights.chooseDiskFolder)
                        .roomLink(accent).font(RoomTokens.Typography.body)
                        .disabled(!insights.canChooseDiskLocation)
                        .accessibilityIdentifier("RoomDiskMapAnotherFolder")
                }
                rescanButton(quiet: ticking && ticksAvailable)
            }
            if ticksAvailable, ticking {
                let bytes = selection.bytes(in: rooms.map(\.room))
                Button("Move \(RoomCachesVisibility.figure(RoomFormat.gb(bytes), hidden: hidden)) to Trash") {
                    openFolderReview(rooms)
                }
                .roomScreenPrimary(accent)
                .disabled(folderTrash?.canMove != true)
                .accessibilityHint("Opens a review. These are your own folders, not caches")
            }
        }
        .fixedSize()
        // The note is a safety line, so a narrow window moves it above the buttons rather than cutting it.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.group) {
                noteText.lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                actions
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                noteText.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .frame(minHeight: RoomTokens.Overview.actionHeight)
        .padding(.top, RoomTokens.Space.row)
    }

    /// The screen's filled button, until rooms are ticked: then Move to Trash is, and this one steps back.
    @ViewBuilder private func rescanButton(quiet: Bool) -> some View {
        let button = Button(rescanTitle, action: insights.rescanDisk)
            .disabled(!insights.canRescanDisk)
            .accessibilityIdentifier("RoomDiskScanButton")
        if quiet {
            button.roomQuiet()
        } else {
            button.roomScreenPrimary(accent) // one-filled: exclusive with Move to Trash (quiet while rooms are ticked)
        }
    }

    private func openFolderReview(_ rooms: [RoomDiskRoom]) {
        guard let folderTrash else { return }
        let chosen = rooms.filter { selection.contains($0.id) }.compactMap { room in
            model.url(for: room.id).map { (url: $0, name: room.room.name, bytes: room.room.bytes) }
        }
        if let review = folderTrash.review(chosen) {
            folderReview = review
            // Unverifiable rooms leave the selection; the review says how many.
            for room in rooms where selection.contains(room.id) && !review.names.contains(room.room.name) {
                selection.toggle(room.room)
            }
        } else {
            protectionNote = chosen.count == 1 ? "Room could not check this folder, so it stays"
                                               : "Room could not check these folders, so they stay"
        }
    }

    private func emptyMap(_ level: RoomTreeNode) -> some View {
        let isFiltered = filter != nil
        let hasMeasuredItems = level.fileCount > 0 || !level.children.isEmpty || level.other != nil
        let title = isFiltered ? "No matching items" : level.isPartial ? "This map is incomplete" :
            hasMeasuredItems ? "No items to show" : "This folder is empty"
        let message = isFiltered ? "Clear the filter to see other measured items." :
            level.isPartial ? "Room couldn’t measure all the items in this folder." :
            hasMeasuredItems ? "The map shows items that use disk space." : "Rescan after adding files to this folder."
        return RoomEmptyFeedback(title: title, message: message,
                                 symbol: isFiltered ? "line.3.horizontal.decrease" : "folder",
                                 prominent: true) {
            if isFiltered {
                Button("Clear Filter") { filter = nil }
                    .roomSecondary()
                    .accessibilityIdentifier("RoomDiskClearFilter")
            } else if layout == .map, !level.children.isEmpty {
                Button("Show Largest 20") { layout = .largest }
                    .roomSecondary()
            }
        }
    }

    private func blueprintDetail(_ blueprint: RoomBlueprint, isWide: Bool) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                RoomBlueprintArtwork(blueprint: blueprint, hidden: hidden)
                    .equatable()
                    .frame(minHeight: RoomTokens.Map.minimumHeight)
                if blueprint.phase == .stopped {
                    Text(hidden ? "Scan stopped" : blueprint.stoppedSummary)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                if let earlier = blueprint.earlierDate, blueprint.rooms.contains(where: \.isEarlier) {
                    Text("Pending rooms show sizes from \(earlier.formatted(.dateTime.month().day())).")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                RoomMapReadout(title: "Measured so far",
                               detail: hidden ? "Size hidden" : blueprint.counter(files: { $0.formatted() }, bytes: RoomFormat.gb))
            }
            if isWide && !hidesWideInspector { wideInspector }
        }
    }

    private var wideInspector: some View {
        inspector
            .frame(width: RoomTokens.Map.inspectorWidth)
            .roomPanelArrival()
    }

    private func readout(_ level: RoomTreeNode, hint: Bool) -> some View {
        let target = cleanupTarget(in: level)
        let action = target.flatMap(cleanupAction)
        let showsCleanupTarget = action == .review || action == .empty
        return HStack(spacing: RoomTokens.Space.row) {
            RoomMapContextReadout(level: level, pointer: pointer, selectedPath: model.selectedPath,
                                  hidden: hidden, showsHint: hint, showsCleanupTarget: showsCleanupTarget)
            if let target, let action {
                RoomMapCleanupControl(action: action) { activateCleanup(target) }
            }
            if let date = model.changedAt, date > model.current?.scannedAt ?? .distantPast {
                Text("Changed since this scan")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
            } else if let date = model.current?.scannedAt {
                Text("Scanned \(date.formatted(.dateTime.month().day()))")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
            }
            if let issueCount = model.current?.issueCount, issueCount > 0, insights.diskReport != nil {
                Button(hidden ? "Read issues" : "\(issueCount) folders or items couldn’t be read") { showsIssues = true }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func cleanupTarget(in level: RoomTreeNode) -> RoomMapCleanupTarget? {
        guard !hidden, !insights.isScanningDisk, let target = model.cleanupTarget,
              RoomMapReadoutContent.node(at: target.path, inside: level) != nil else { return nil }
        return target
    }

    @ViewBuilder private var inspector: some View {
        if insights.isScanningDisk, let blueprint = model.blueprint, blueprint.phase == .scanning {
            RoomBlueprintInspector(blueprint: blueprint, hidden: hidden)
        } else {
            mapInspector
        }
    }

    private var mapInspector: some View {
        let shown = model.selectedPath.flatMap { model.current?.tree.descendant(at: $0) } ?? model.level
        let url = shown.flatMap { model.url(for: $0.relativePath) }
        let cacheSource = url.flatMap { candidate in
            insights.analysisReport?.findings.contains {
                $0.item.url.path == candidate.path && $0.disposition == .cache
            } == true && canInspectCacheSource(candidate) ? candidate : nil
        }
        return RoomMapInspector(node: shown, url: url,
            parent: model.level, pin: rooms.map { $0.pin(url:) }, showSizes: !hidden,
            isScanning: insights.isScanningDisk, analysis: insights.analysisReport, analysisStatus: insights.analysisStatus,
            isAnalyzing: insights.isAnalyzingStorage, canAnalyze: insights.canAnalyzeStorage,
            stepIn: {
                if let shown { step(to: shown.relativePath, animated: NSApp.currentEvent?.type == .leftMouseUp) }
            },
            map: { if let url = shown.flatMap({ model.url(for: $0.relativePath) }) { insights.scanDisk(url: url) } },
            rescan: { if let shown { insights.rescanMappedFolder(shown.relativePath) } },
            inspect: insights.analyzeStorage,
            inspectCacheSource: cacheSource.map { candidate in { inspectCacheSource(candidate) } })
    }

    private func activate(_ path: String, _ open: Bool, _ pointer: Bool) {
        if path.hasSuffix("\u{0}other") {
            if open {
                let parent = path.dropLast("\u{0}other".count)
                otherDetails = model.current?.tree.descendant(at: String(parent)).flatMap { filtered($0).other }
                showsOther = true
            }
            return
        }
        if open, step(to: path, animated: pointer) { return }
        model.select(path)
    }

    @discardableResult
    private func step(to path: String, animated: Bool) -> Bool {
        guard animated, layout == .map, let prior = model.level, prior.relativePath != path else {
            return model.go(to: path)
        }
        zoomInward = path.hasPrefix(prior.relativePath) && path.count > prior.relativePath.count
        if !zoomInward { zoomAnchor = .center }
        let previous = filtered(prior)
        let selection = model.selectedPath
        let generation = mapGeneration + 1
        var opened = false
        withAnimation(motion.animation(RoomTokens.Motion.zoom)) {
            opened = model.go(to: path)
            guard opened else { return }
            filter = nil
            mapGeneration = generation
            mapStep = RoomMapStep(generation: generation, previous: previous, selection: selection,
                                  destination: path, into: prior.relativePath.isEmpty || path.hasPrefix(prior.relativePath + "/"))
        } completion: {
            guard mapStep?.generation == generation else { return }
            roomWithoutMotion { mapStep = nil }
        }
        return opened
    }

    private func quickLook(_ path: String) -> Bool {
        guard !hidden, model.current?.tree.descendant(at: path)?.isDirectory == false,
              let url = model.url(for: path), let scope = insights.approvedMapScope(for: url) else { return false }
        releasePreviewScope()
        if scope.startAccessingSecurityScopedResource() { previewScope = scope }
        previewURL = url
        return true
    }

    private func releasePreviewScope() {
        previewScope?.stopAccessingSecurityScopedResource()
        previewScope = nil
    }

    private func reveal(_ path: String) {
        guard !hidden, let url = model.url(for: path), insights.approvedMapScope(for: url) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func filtered(_ node: RoomTreeNode) -> RoomTreeNode {
        guard let filter else { return node }
        func onlyKind(_ node: RoomTreeNode) -> RoomTreeNode? {
            guard let bytes = node.kindBytes[filter], bytes > 0 else { return nil }
            var filtered = node
            filtered.allocatedBytes = bytes
            filtered.children = node.children.compactMap(onlyKind)
            filtered.kindBytes = [filter: bytes]
            let measured = filtered.children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            if !node.children.isEmpty, bytes > measured {
                filtered.other = .init(itemCount: 0, allocatedBytes: bytes - measured, isPartial: node.isPartial)
            } else {
                filtered.other = nil
            }
            return filtered
        }
        var blank = node
        blank.allocatedBytes = 0
        blank.children = []
        blank.other = nil
        return onlyKind(node) ?? blank
    }
}
