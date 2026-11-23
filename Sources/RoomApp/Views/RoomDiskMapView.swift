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
    @Environment(\.openSettings) private var openSettings
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var privacy
    @Environment(\.roomMotion) private var motion
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
            let isWide = geometry.size.width >= RoomTokens.Map.inspectorBreakpoint
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                controls(isWide: isWide)
                if let blueprint = model.blueprint,
                   insights.isScanningDisk || (blueprint.phase == .stopped && insights.diskReport?.cancelled == true &&
                       layout == .map && model.levelPath.isEmpty) {
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
                        .roomPanelArrival(enabled: model.blueprint?.phase == .done)
                } else {
                    folderStart
                }
            }
            .padding([.horizontal, .bottom], RoomTokens.Space.group)
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
        .onChange(of: model.levelPath) { _, path in
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
        .sheet(isPresented: $showsIssues) {
            RoomScanIssuesSheet(issues: insights.diskReport?.issues.map { hidden ? "Path hidden" : "\($0.url.path): \($0.message)" } ?? [])
        }
        .sheet(isPresented: $showsOther) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                Text("Other").font(RoomTokens.Typography.title)
                if let other = otherDetails {
                    Text(hidden ? "Size hidden" : "\(other.itemCount.formatted()) small items · \(other.isPartial ? "≥ " : "")\(RoomFormat.bytes(other.allocatedBytes))")
                }
                Text("These items were measured together. Open a mapped folder to see its retained items.")
                    .foregroundStyle(RoomTokens.Ink.secondary)
                Button("Done") { showsOther = false }.keyboardShortcut(.defaultAction)
            }
            .padding(RoomTokens.Space.breath1)
        }
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
        if showsMap, let level = model.level {
            HStack(spacing: RoomTokens.Space.row) {
                RoomBreadcrumbs(trail: model.trail, hidden: hidden) {
                    step(to: $0, animated: NSApp.currentEvent?.type == .leftMouseUp)
                }
                if !hidden {
                    Text("\(level.isPartial ? "≥ " : "")\(RoomFormat.bytes(level.allocatedBytes)) · hidden files included")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
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

    private func viewActions(isWide: Bool) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            if showsMap, model.current != nil, !insights.isScanningDisk {
                Picker("Disk Map view", selection: $layout) {
                    Text(Display.map.rawValue).tag(Display.map)
                    Text(Display.largest.rawValue).tag(Display.largest)
                    if model.canCompare { Text(Display.compare.rawValue).tag(Display.compare) }
                }
                .pickerStyle(.segmented).labelsHidden()
                let inspectorVisible = isWide ? !hidesWideInspector : showsInspector
                Button {
                    toggleInspector(isWide: isWide)
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(inspectorVisible ? accent.text : RoomTokens.Ink.secondary)
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(inspectorVisible ? "Hide inspector" : "Show inspector")
                    .help(inspectorVisible ? "Hide inspector" : "Show inspector")
                Button(rescanTitle, action: insights.rescanDisk)
                    .buttonStyle(.borderless)
                    .disabled(!insights.canRescanDisk)
                    .accessibilityIdentifier("RoomDiskScanButton")
            } else if insights.isScanningDisk {
                Button("Stop", action: insights.cancelDiskScan).roomSecondary()
            }
            folders
            if let savedViews, !showsFolderStart || !savedViews.visible.isEmpty {
                viewsMenu(savedViews)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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
                    .roomScreenPrimary(accent)
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
                    Label("Choose Folder…", systemImage: "folder")
                }
                .roomScreenPrimary(accent)
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
            if layout != .compare, hasItems { RoomMapKindControl(node: level, hidden: hidden, filter: $filter) }
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    if layout != .compare, !hasItems {
                        emptyMap(level)
                        readout(visible, hint: false)
                    } else if layout == .map {
                        RoomMapViewport(level: visible, selection: model.selectedPath, hidden: hidden,
                                        generation: mapGeneration,
                                        step: mapStep?.destination == level.relativePath ? mapStep : nil,
                                        onHoverItem: { pointer.item = $0 },
                                        activate: activate, preview: quickLook, reveal: reveal)
                            .frame(minHeight: RoomTokens.Map.minimumHeight)
                        readout(visible, hint: true)
                    } else if layout == .compare, let compared = model.comparison {
                        RoomCompareOverlay(earlier: compared.earlier, current: level, earlierDate: compared.date, hidden: hidden) {
                            layout = .map
                        }
                        .frame(minHeight: RoomTokens.Map.minimumHeight)
                    } else {
                        RoomLargestTable(level: visible, hidden: hidden) { activate($0, false, false) }
                        readout(visible, hint: false)
                    }
                }
                .roomPanelChange(layout)
                if isWide && !hidesWideInspector { wideInspector }
            }
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
                               detail: hidden ? "Size hidden" : blueprint.counter(files: { $0.formatted() }, bytes: RoomFormat.bytes))
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
        HStack(spacing: RoomTokens.Space.row) {
            RoomMapContextReadout(level: level, pointer: pointer, selectedPath: model.selectedPath,
                                  hidden: hidden, showsHint: hint)
            if let date = model.changedAt, date > model.current?.scannedAt ?? .distantPast {
                Text("Changed since this scan").foregroundStyle(RoomTokens.Ink.secondary)
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
        let previous = filtered(prior)
        let selection = model.selectedPath
        let generation = mapGeneration + 1
        var opened = false
        withAnimation(motion.animation(RoomTokens.Motion.page)) {
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
