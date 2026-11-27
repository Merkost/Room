import AppKit
import RoomCore
import SwiftUI

/// What the dock offers on Developer.
nonisolated struct RoomDeveloperDock: Equatable, Sendable {
    enum Step: Equatable, Sendable { case stop, allowHome, scan(again: Bool) }
    let main: Step

    static func make(scanning: Bool, needsHome: Bool, hasResults: Bool) -> RoomDeveloperDock {
        if scanning { return RoomDeveloperDock(main: .stop) }
        if needsHome, !hasResults { return RoomDeveloperDock(main: .allowHome) }
        return RoomDeveloperDock(main: .scan(again: hasResults))
    }
}

private enum RoomDeveloperLayoutState: Equatable { case intro, firstScan, workspace }

/// Everything about developer files on one screen: no tabs and no folder step.
struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    var memoryReport: MemoryReport?
    #endif
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @State private var showingFolderPopover = false
    @State private var folderListHeight: CGFloat = 200
    @State private var width: CGFloat = 0
    @State private var expanded: Set<RoomDeveloperPage.Kind> = []
    @State private var openChip: String?
    private let confirmationPrefix = "developer/remove/"

    /// Rows a section shows before "N more".
    static let projectRows = 5
    static let sideRows = 3
    /// Below this the two columns stack.
    static let twoColumnWidth: CGFloat = 640

    private var hasResults: Bool {
        var results = model.report != nil || model.devicesReport != nil || model.storageReport != nil || model.aiToolsReport != nil
        #if !ROOM_APP_STORE
        results = results || agentWork.report != nil
        #endif
        return results
    }

    private var worktreesBytes: Int64 {
        #if ROOM_APP_STORE
        0
        #else
        agentWork.report?.items.reduce(Int64(0)) { $0 + $1.allocatedBytes } ?? 0
        #endif
    }

    private var page: RoomDeveloperPage {
        .make(headline: model.headline, worktreesBytes: worktreesBytes, projects: model.report?.projects.count ?? 0)
    }

    private var layoutState: RoomDeveloperLayoutState {
        if hasResults { return .workspace }
        return model.isScanning ? .firstScan : .intro
    }

    var body: some View {
        Group {
            switch layoutState {
            case .intro:
                RoomScreenFrame(headline: .words("Your developer files"),
                                supporting: model.needsHomeAccess
                                    ? "Allow your home folder once and Room finds your projects, devices and tool storage."
                                    : "Room finds your projects, devices, build tools and AI tools by itself. macOS may ask about Documents, Desktop and Downloads.",
                                note: "Room only reads sizes and version files", scrollsEvidence: true) {
                    foldersLine
                } action: {
                    EmptyView()
                }
                .transition(.opacity)
            case .firstScan:
                RoomScreenFrame(headline: .words("Finding your developer files"), supporting: model.progress,
                                note: "Room only reads sizes and version files") {
                    RoomScanStrip(tiles: model.scanTiles)
                        .padding(.top, RoomTokens.Space.breath2)
                } action: {
                    EmptyView()
                }
                .transition(.opacity)
            case .workspace:
                let page = page
                RoomScreenFrame(headline: page.headline, supporting: model.isScanning ? model.progress : page.supporting,
                                note: note, noteAccessory: AnyView(foldersLine), scrollsEvidence: true,
                                entersEvidence: false) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                        if model.isScanning, !model.scanTiles.isEmpty {
                            RoomScanStrip(tiles: model.scanTiles).transition(.opacity)
                        }
                        if !page.parts.isEmpty { composition(page) }
                        columns(page)
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                    .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: model.isScanning)
                } action: {
                    EmptyView()
                }
                .transition(.opacity)
            }
        }
        .animation(motion.animation(RoomTokens.Motion.fade), value: layoutState)
        .roomDock(dockMain)
        .alert("Couldn’t add that folder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(hide.masksNow ? "Choose the folder again." : model.errorMessage ?? "") }
        #if !ROOM_APP_STORE
        .sheet(isPresented: $model.showingWorktrees) { worktreesSheet }
        #endif
    }

    private var note: String? {
        model.headline.partial || model.projectSearchPartial ? "Sizes marked ≥ are lower bounds." : nil
    }

    /// One button for the whole screen.
    static func scanTitle(isScanning: Bool, hasResults: Bool) -> String {
        isScanning ? "Stop" : hasResults ? "Rescan all" : "Scan all"
    }

    private var dockMain: RoomDockAction {
        let dock = RoomDeveloperDock.make(scanning: model.isScanning, needsHome: model.needsHomeAccess, hasResults: hasResults)
        let id = "RoomDeveloperScanButton"
        switch dock.main {
        case .stop:
            return RoomDockAction(title: Self.scanTitle(isScanning: true, hasResults: hasResults), filled: false,
                                  identifier: id) { model.stop() }
        case .allowHome:
            return RoomDockAction(title: "Allow Home Folder…", symbol: "folder.badge.plus",
                                  enabled: !model.isChoosingFolder, identifier: id) { model.allowHome() }
        case .scan(let again):
            return RoomDockAction(title: Self.scanTitle(isScanning: false, hasResults: again),
                                  symbol: again ? "arrow.clockwise" : "magnifyingglass",
                                  enabled: model.canScan && !model.isChoosingFolder, identifier: id) { model.scan() }
        }
    }

    // MARK: What it is made of

    private func color(_ kind: RoomDeveloperPage.Kind) -> Color {
        switch kind {
        case .projects: RoomTokens.Kind.developer.mark
        case .devices: RoomTokens.Kind.apps.mark
        case .storage: RoomTokens.Kind.archives.mark
        case .aiTools: RoomTokens.Kind.media.mark
        case .worktrees: RoomTokens.Kind.documents.mark
        }
    }

    private func composition(_ page: RoomDeveloperPage) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(0, page.parts.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(page.parts) { part in
                        RoundedRectangle(cornerRadius: 3).fill(color(part.kind))
                            .frame(width: max(4, (proxy.size.width - gaps) * CGFloat(part.bytes) / CGFloat(max(1, page.total))))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            RoomWrappingRow(spacing: RoomTokens.Space.group) {
                ForEach(page.parts) { part in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(color(part.kind)).frame(width: 8, height: 8)
                        Text(part.kind.title)
                        RoomMaskable(RoomFormat.gb(part.bytes))
                    }
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private func columns(_ page: RoomDeveloperPage) -> some View {
        if width >= Self.twoColumnWidth {
            HStack(alignment: .top, spacing: RoomTokens.Space.breath2) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) { leftColumn(page) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) { rightColumn(page) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                leftColumn(page)
                rightColumn(page)
            }
        }
    }

    @ViewBuilder private func leftColumn(_ page: RoomDeveloperPage) -> some View {
        section(.projects, page: page, rows: RoomDeveloperLargest.projects(model.summary), limit: Self.projectRows,
                trailing: model.report.map { "\($0.projects.count) found" },
                empty: model.report == nil ? "Not read yet" : "No Gradle or Xcode projects found")
        versions
    }

    @ViewBuilder private func rightColumn(_ page: RoomDeveloperPage) -> some View {
        section(.devices, page: page, rows: RoomDeveloperLargest.devices(model.devicesReport), limit: Self.sideRows,
                empty: model.devicesReport == nil ? "Not read yet" : "No virtual devices")
        section(.storage, page: page, rows: RoomDeveloperLargest.storage(model.storageReport), limit: Self.sideRows,
                empty: model.storageReport == nil ? "Not read yet" : "No tool storage")
        section(.aiTools, page: page, rows: RoomDeveloperLargest.aiTools(model.aiToolsReport), limit: Self.sideRows,
                empty: model.aiToolsReport == nil ? "Not read yet" : "No AI tool storage")
        #if !ROOM_APP_STORE
        section(.worktrees, page: page, rows: RoomDeveloperLargest.worktrees(agentWork.report), limit: Self.sideRows,
                empty: agentWork.report == nil ? "Not read yet" : "No agent worktrees",
                action: agentWork.report?.items.isEmpty == false ? ("Review…", { model.showingWorktrees = true }) : nil)
        #endif
    }

    private func head(_ title: String, bytes: Int64?, trailing: String?, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.inner) {
            Text(title).font(RoomTokens.Screen2.listName).foregroundStyle(RoomTokens.Ink.graphite)
            if let bytes, bytes > 0 {
                RoomMaskable(RoomFormat.gb(bytes)).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary)
            }
            Spacer(minLength: RoomTokens.Space.row)
            if let trailing {
                Text(trailing).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.tertiary)
            }
            if let action {
                Button(action.0, action: action.1).roomLink(accent).font(RoomTokens.Typography.caption)
            }
        }
        .padding(.bottom, RoomTokens.Space.tight)
        .overlay(alignment: .bottom) { Rectangle().fill(RoomTokens.Surface.line).frame(height: 1) }
        .accessibilityAddTraits(.isHeader)
    }

    private func section(_ kind: RoomDeveloperPage.Kind, page: RoomDeveloperPage, rows: [RoomDeveloperLargestRow], limit: Int,
                         trailing: String? = nil, empty: String, action: (String, () -> Void)? = nil) -> some View {
        let open = expanded.contains(kind)
        let shown = RoomDeveloperList.visible(rows, expanded: open, limit: limit)
        return VStack(alignment: .leading, spacing: 2) {
            head(kind.title, bytes: page.parts.first { $0.kind == kind }?.bytes, trailing: trailing, action: action)
            if rows.isEmpty {
                Text(empty).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.tertiary)
                    .padding(.top, RoomTokens.Space.tight)
            }
            ForEach(shown.shown) { row in
                RoomEvidenceRow(name: row.name, meta: row.meta, bytes: row.bytes, barColor: color(kind),
                                nameColumn: RoomTokens.Developer.nameColumn,
                                showsBar: width < Self.twoColumnWidth || width >= RoomTokens.Developer.barsBreak) {
                    RoomThingIcon(path: row.path, name: row.name, fallback: row.glyph, project: row.project)
                }
                .padding(.horizontal, RoomTokens.Space.row)
                .roomRowHover()
                .padding(.horizontal, -RoomTokens.Space.row)
                .contextMenu {
                    if let path = row.path {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                }
            }
            if shown.hidden > 0 || open && rows.count > limit + 1 {
                Button(open ? "Show fewer" : "\(shown.hidden) more") {
                    if open { expanded.remove(kind) } else { expanded.insert(kind) }
                }
                .roomLink(accent)
                .font(RoomTokens.Typography.caption)
                .padding(.top, RoomTokens.Space.tight)
            }
        }
    }

    @ViewBuilder private var versions: some View {
        let chips = RoomDeveloperVersionChip.make(projects: model.report?.projects ?? [], summary: model.summary)
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                head("Versions", bytes: nil, trailing: "what your projects use")
                RoomWrappingRow(spacing: RoomTokens.Space.tight + 2) {
                    ForEach(chips) { chip($0) }
                }
            }
        }
    }

    private func chip(_ chip: RoomDeveloperVersionChip) -> some View {
        Button { openChip = openChip == chip.id ? nil : chip.id } label: {
            HStack(spacing: 5) {
                RoomMaskable(chip.label, kind: .name)
                Text(chip.detail).foregroundStyle(RoomTokens.Ink.secondary)
            }
            .font(RoomTokens.Typography.caption)
            .padding(.horizontal, RoomTokens.Space.row + 2)
            .padding(.vertical, 5)
            .background(RoomTokens.Surface.hover, in: .rect(cornerRadius: RoomTokens.Radius.row))
            .overlay {
                if chip.unused {
                    RoundedRectangle(cornerRadius: RoomTokens.Radius.row).strokeBorder(RoomTokens.Status.elevated, lineWidth: 1)
                }
            }
        }
        .buttonStyle(RoomPressStyle())
        .popover(isPresented: Binding(get: { openChip == chip.id }, set: { if !$0 { openChip = nil } }), arrowEdge: .bottom) {
            chipDetail(chip).padding(RoomTokens.Space.group).frame(minWidth: 200, alignment: .leading)
        }
    }

    private func chipDetail(_ chip: RoomDeveloperVersionChip) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text(chip.label).font(RoomTokens.Typography.section)
            ForEach(chip.projects, id: \.self) { RoomMaskable($0, kind: .name) }
            if chip.unused {
                Text("No project Room found asks for it.").foregroundStyle(RoomTokens.Ink.secondary)
                if let key = chip.key, let line = RoomDevUnreferenced.caption(since: model.unreferenced.since[key],
                    now: Date(), thresholdDays: unusedThreshold) {
                    Text(line).foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
            if let path = chip.path {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .roomLink(accent)
            }
        }
        .font(RoomTokens.Typography.body)
    }

    @AppStorage(RoomDevUnreferenced.preferenceKey) private var unusedThreshold = RoomDevUnreferenced.defaultThreshold

    #if !ROOM_APP_STORE
    private var worktreesSheet: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            ScrollView {
                RoomAgentWorkView(model: agentWork, memoryReport: memoryReport)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { model.showingWorktrees = false }.roomSecondary().keyboardShortcut(.cancelAction)
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(width: 720, height: 540)
    }
    #endif

    // MARK: Folders (optional)

    private var foldersLine: some View {
        HStack(spacing: RoomTokens.Space.tight) {
            Text(model.needsHomeAccess ? "Or choose single folders." : "Found on its own in your home folder.")
                .foregroundStyle(RoomTokens.Ink.secondary)
            Button("Folders…") { showingFolderPopover.toggle() }
                .roomLink(accent)
                .accessibilityIdentifier("RoomDeveloperFolders")
                .popover(isPresented: $showingFolderPopover, arrowEdge: .bottom) {
                    ScrollView {
                        folderPopover
                            .padding(RoomTokens.Space.group)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { folderListHeight = $0 }
                    }
                    // As tall as the list, up to a height that fits the smallest window; beyond that it scrolls.
                    .frame(width: 380, height: min(folderListHeight, 460))
                }
            Text("to add or skip one.").foregroundStyle(RoomTokens.Ink.secondary)
        }
        .font(RoomTokens.Typography.caption)
        .lineLimit(1)
    }

    private var folderPopover: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text("Folders Room reads").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
            ForEach(model.manualLocations, content: folderRow)
            ForEach(model.automaticLocations) { location in
                locationRow(location) {
                    Button("Skip") { model.skip(location) }
                        .roomLink(accent)
                        .disabled(model.isScanning)
                        .accessibilityLabel("Skip \(location.role.title)")
                }
            }
            if model.automaticLocations.isEmpty, model.manualLocations.isEmpty {
                Text("None yet. A scan finds them.").foregroundStyle(RoomTokens.Ink.secondary)
            }
            if !model.skippedPaths.isEmpty {
                Text("Skipped").font(RoomTokens.Typography.section).padding(.top, RoomTokens.Space.row)
                ForEach(model.skippedPaths, id: \.self) { path in
                    HStack {
                        RoomMaskable((path as NSString).abbreviatingWithTildeInPath, kind: .name)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Include") { model.include(path) }.roomLink(accent).disabled(model.isScanning)
                    }
                    .font(RoomTokens.Typography.caption)
                }
            }
            Menu("Add a folder…") {
                ForEach(RoomDeveloperFolderRole.allCases) { role in folderChoice(role) }
            }
            .roomDropdown()
            .disabled(model.isScanning || model.isChoosingFolder)
            .accessibilityIdentifier("RoomDeveloperAddFolder")
            RoomInlineUndoRows(prefix: confirmationPrefix)
        }
        .font(RoomTokens.Typography.body)
    }

    @ViewBuilder private func folderChoice(_ role: RoomDeveloperFolderRole) -> some View {
        let folders = model.reusableFolders(for: role)
        if folders.isEmpty {
            Button { model.addFolder(role: role) } label: { Label(role.title, systemImage: role.symbol) }
        } else {
            Menu {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    let name = hide.masksNow ? "Saved folder \(index + 1)"
                        : (folder.url.path as NSString).abbreviatingWithTildeInPath
                    Button { model.attach(role: role, to: folder.id) } label: {
                        Label(name, systemImage: "folder")
                    }
                    .accessibilityLabel("Use \(name) for \(role.title)")
                    .accessibilityIdentifier("RoomDeveloperReuse-\(role.id)-\(folder.id)")
                }
                Divider()
                Button { model.addFolder(role: role) } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
            } label: {
                Label(role.title, systemImage: role.symbol)
            }
        }
    }

    private func locationRow<Trailing: View>(_ location: RoomDeveloperLocation, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: location.role.symbol)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(location.role == .project ? "Project" : location.role.title)
                RoomMaskable((location.folder.url.path as NSString).abbreviatingWithTildeInPath, kind: .name)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }

    private func folderRow(_ location: RoomDeveloperLocation) -> some View {
        locationRow(location) {
            RoomInlineConfirmButton(id: confirmationPrefix + location.id, title: "Stop reading…",
                confirmTitle: "Stop reading this folder?", doneLine: "Room no longer reads this folder. Its files are untouched.",
                isAllowed: !model.isScanning, stage: { model.stageRemoval(location) },
                commit: { model.commitRemoval(location) }, undo: { model.undoRemoval(location) })
                .help("Room stops reading this folder. Nothing in it is changed or deleted. Folder access is managed in Settings.")
        }
    }
}

extension DeveloperStorageKind {
    var title: String {
        switch self {
        case .gradleDaemon: "Gradle Daemon Data"
        case .gradleJDKs: "Gradle JDKs"
        case .androidSystemImages: "Android System Images"
        case .simulatorDevices: "Simulator Device Data"
        case .simulatorRuntimeBundle: "Simulator Runtime Bundle"
        case .simulatorRuntimeImage: "Simulator Runtime Image"
        }
    }

    var symbol: String {
        switch self {
        case .gradleDaemon: "terminal"
        case .gradleJDKs: "shippingbox"
        case .androidSystemImages: "opticaldiscdrive"
        case .simulatorDevices: "iphone.gen3"
        case .simulatorRuntimeBundle: "shippingbox"
        case .simulatorRuntimeImage: "opticaldiscdrive"
        }
    }

    var detail: String {
        switch self {
        case .gradleDaemon: "Logs and coordination data for Gradle background processes."
        case .gradleJDKs: "JDKs managed by Gradle for builds."
        case .androidSystemImages: "Installed operating system images shared by Android virtual devices."
        case .simulatorDevices: "Installed apps and device data. Xcode manages simulator runtimes separately."
        case .simulatorRuntimeBundle: "Stand-alone package for a shared Simulator operating system."
        case .simulatorRuntimeImage: "Allocated space used by the stored disk image for a shared Simulator operating system."
        }
    }
}
