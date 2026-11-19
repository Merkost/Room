import AppKit
import QuickLook
import RoomCore
import SwiftUI

struct RoomDiskMapView: View {
    @Bindable var insights: RoomInsightsModel
    var rooms: RoomRoomsModel? = nil
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
    @State private var previewURL: URL?
    @State private var previewScope: URL?
    @State private var mapGeneration = 0
    @State private var mapStep: RoomMapStep?

    private enum Display: String, CaseIterable { case map = "Map", largest = "Largest 20", compare = "Compare" }
    private var model: RoomDiskMapModel { insights.diskMap }

    var body: some View {
        GeometryReader { geometry in
            let isWide = (NSApp.keyWindow?.frame.width ?? geometry.size.width) >= RoomTokens.Map.inspectorBreakpoint
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                controls(isWide: isWide)
                if let blueprint = model.blueprint,
                   insights.isScanningDisk || (blueprint.phase == .stopped && layout == .map && model.levelPath.isEmpty) {
                    blueprintDetail(blueprint, isWide: isWide)
                } else if let level = model.level {
                    if model.hasLostAccess {
                        Text(hidden ? "Room lost access to this folder." : "Room lost access to \(model.current?.displayPath ?? "this folder").")
                            .foregroundStyle(RoomTokens.Ink.secondary)
                        Button("Choose it again…", action: insights.chooseDiskFolder).roomPrimary(accent)
                    }
                    details(level, isWide: isWide)
                        .opacity(model.hasLostAccess ? 0.42 : 1)
                } else {
                    empty
                }
            }
            .padding([.horizontal, .bottom], RoomTokens.Space.group)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: insights.diskInspectorRequest) { _, _ in
                if isWide { hidesWideInspector.toggle() }
                else { showsInspector.toggle() }
            }
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
        .task { await insights.restoreDiskMap() }
        .task { await insights.observeTreeChanges() }
        .onChange(of: model.levelPath) { _, path in
            filter = nil
            if mapStep?.destination != path { mapStep = nil }
        }
        .onChange(of: model.current?.rootID) { _, _ in
            filter = nil
            layout = .map
            mapStep = nil
        }
        .onChange(of: layout) { _, _ in mapStep = nil }
        .onChange(of: model.canCompare) { _, available in
            if !available, layout == .compare { layout = .map }
        }
        .onChange(of: motion.isFull) { _, _ in roomWithoutMotion { mapStep = nil } }
        .sheet(isPresented: $showsIssues) {
            RoomScanIssuesSheet(issues: insights.diskReport?.issues.map { hidden ? "Path hidden" : "\($0.url.path): \($0.message)" } ?? [])
        }
        .sheet(isPresented: $showsOther) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                Text("Other").font(RoomTokens.Typography.title)
                if let other = model.level?.other {
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
        if model.trail.isEmpty {
            Text("Disk Map").font(RoomTokens.Typography.title).accessibilityAddTraits(.isHeader)
        } else {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                RoomBreadcrumbs(trail: model.trail, hidden: hidden) {
                    step(to: $0, animated: NSApp.currentEvent?.type == .leftMouseUp)
                }
                if let date = model.current?.scannedAt {
                    Text("Scanned \(date.formatted(.dateTime.month().day()))")
                        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
        }
    }

    private func viewActions(isWide: Bool) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            if model.current != nil, !insights.isScanningDisk {
                Picker("Disk Map view", selection: $layout) {
                    Text(Display.map.rawValue).tag(Display.map)
                    Text(Display.largest.rawValue).tag(Display.largest)
                    if model.canCompare { Text(Display.compare.rawValue).tag(Display.compare) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if !isWide {
                    Button {
                        showsInspector.toggle()
                    } label: { Label("Inspector", systemImage: "sidebar.right").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                }
                Button("Rescan", action: insights.rescanDisk)
                    .buttonStyle(.borderless)
                    .disabled(!insights.canRescanDisk)
                    .accessibilityIdentifier("RoomDiskScanButton")
            } else if insights.isScanningDisk {
                Button("Stop", action: insights.cancelDiskScan).roomSecondary()
            }
            folders
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var folders: some View {
        Menu("Folders") {
            ForEach(insights.accessFolders) { folder in
                Button(hidden ? "Folder" : folder.name) { insights.openDiskMap(rootURL: folder.url) }
            }
            Button("Add Folder…", action: insights.chooseDiskFolder)
            #if !ROOM_APP_STORE
            Button("Home", action: insights.scanHome)
            Button("Map Applications…", action: insights.mapApplications)
            Button("Full Disk Access…", action: insights.openPrivacySettings)
            #endif
            Button("Manage in Settings…") {
                insights.requestedSettingsTab = .folders
                openSettings()
            }
        }
        .accessibilityIdentifier("RoomDiskChangeFolderButton")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text(insights.accessFolders.isEmpty ? "Start with a folder." : "Choose where to map.")
                .font(RoomTokens.Typography.title)
            Text("Map a folder, including its hidden files. Your files stay in place.")
                .font(RoomTokens.Typography.lead)
                .foregroundStyle(RoomTokens.Ink.secondary)
            if let pending = model.pendingFolder {
                Button(hidden ? "Map folder" : "Map \(pending.lastPathComponent)") { insights.scanDisk(url: pending) }
                    .roomPrimary(accent)
            } else if insights.accessFolders.isEmpty {
                Button("Choose Folder…", action: insights.chooseDiskFolder).roomPrimary(accent)
            } else {
                ForEach(insights.accessFolders) { folder in
                    Button(hidden ? "Map folder" : "Map \(folder.name)") { insights.scanDisk(url: folder.url) }
                        .roomSecondary()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func details(_ level: RoomTreeNode, isWide: Bool) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                if layout == .map {
                    RoomMapKindControl(node: level, hidden: hidden, filter: $filter)
                    RoomMapViewport(level: filtered(level), selection: model.selectedPath, hidden: hidden,
                                    generation: mapGeneration,
                                    step: mapStep?.destination == level.relativePath ? mapStep : nil,
                                    activate: activate, preview: quickLook, reveal: reveal)
                        .frame(minHeight: RoomTokens.Map.minimumHeight)
                } else if layout == .compare, let compared = model.comparison {
                    RoomCompareOverlay(earlier: compared.earlier, current: level, earlierDate: compared.date, hidden: hidden) {
                        layout = .map
                    }
                        .frame(minHeight: RoomTokens.Map.minimumHeight)
                } else {
                    RoomLargestTable(level: level, hidden: hidden) { activate($0, false, false) }
                }
                readout(level)
            }
            if isWide && !hidesWideInspector { inspector.frame(width: RoomTokens.Map.inspectorWidth) }
        }
    }

    private func blueprintDetail(_ blueprint: RoomBlueprint, isWide: Bool) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                RoomMapCanvas(level: blueprint.tree(rootName: model.rootURL?.lastPathComponent ?? "Disk Map"),
                              selection: nil, hidden: hidden, pending: blueprint.earlierNames, interactive: false)
                    .frame(minHeight: RoomTokens.Map.minimumHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if blueprint.phase == .stopped {
                    Text(hidden ? "Scan stopped" : blueprint.stoppedSummary)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                if let earlier = blueprint.earlierDate, !blueprint.earlierNames.isEmpty {
                    Text("Hatched sizes are from \(earlier.formatted(.dateTime.month().day())).")
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                }
                RoomMapReadout(title: "Measured so far",
                               detail: hidden ? "Size hidden" : blueprint.counter(files: { $0.formatted() }, bytes: RoomFormat.bytes))
            }
            if isWide && !hidesWideInspector { inspector.frame(width: RoomTokens.Map.inspectorWidth) }
        }
    }

    private func readout(_ level: RoomTreeNode) -> some View {
        let shown = model.selectedPath.flatMap { model.current?.tree.descendant(at: $0) } ?? level
        return HStack(spacing: RoomTokens.Space.row) {
            RoomMapReadout(title: hidden ? "Name hidden" : shown.name, detail: hidden ? "Size hidden" :
                (shown.isPartial ? "≥ " : "") + RoomFormat.bytes(shown.allocatedBytes))
            if let date = model.changedAt, date > model.current?.scannedAt ?? .distantPast {
                Text("Changed since this scan").foregroundStyle(RoomTokens.Ink.secondary)
            }
            if let issueCount = model.current?.issueCount, issueCount > 0, insights.diskReport != nil {
                Button(hidden ? "Read issues" : "\(issueCount) folders or items couldn’t be read") { showsIssues = true }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var inspector: some View {
        let shown = model.selectedPath.flatMap { model.current?.tree.descendant(at: $0) } ?? model.level
        return RoomMapInspector(node: shown, url: shown.flatMap { model.url(for: $0.relativePath) },
            parent: model.level, pin: rooms.map { $0.pin(url:) }, showSizes: !hidden,
            isScanning: insights.isScanningDisk, analysis: insights.analysisReport, isAnalyzing: insights.isAnalyzingStorage,
            stepIn: {
                if let shown { step(to: shown.relativePath, animated: NSApp.currentEvent?.type == .leftMouseUp) }
            },
            map: { if let url = shown.flatMap({ model.url(for: $0.relativePath) }) { insights.scanDisk(url: url) } },
            rescan: { if let shown { insights.rescanMappedFolder(shown.relativePath) } },
            inspect: insights.analyzeStorage)
    }

    private func activate(_ path: String, _ open: Bool, _ pointer: Bool) {
        if path.hasSuffix("\u{0}other") {
            if open { showsOther = true }
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
        guard model.go(to: path) else { return false }
        filter = nil
        let generation = mapGeneration + 1
        withAnimation(motion.animation(RoomTokens.Motion.page)) {
            mapGeneration = generation
            mapStep = RoomMapStep(generation: generation, previous: previous, selection: selection,
                                  destination: path, into: prior.relativePath.isEmpty || path.hasPrefix(prior.relativePath + "/"))
        } completion: {
            guard mapStep?.generation == generation else { return }
            roomWithoutMotion { mapStep = nil }
        }
        return true
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
