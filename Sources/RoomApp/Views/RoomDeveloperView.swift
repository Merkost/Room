import AppKit
import RoomCore
import SwiftUI

enum RoomDeveloperSection: String, CaseIterable {
    case rooms = "Rooms", matrix = "Matrix", devices = "Devices", storage = "Storage", aiTools = "AI Tools"
    #if !ROOM_APP_STORE
    case worktrees = "Worktrees"
    #endif

    var symbol: String {
        switch self {
        case .rooms: "square.stack.3d.up"
        case .matrix: "tablecells"
        case .devices: "iphone.gen3"
        case .storage: "internaldrive"
        case .aiTools: "sparkles"
        #if !ROOM_APP_STORE
        case .worktrees: "point.3.connected.trianglepath.dotted"
        #endif
        }
    }

    /// What the quiet links on the start page call the view.
    var startLink: String {
        switch self {
        case .rooms: "Project tools"
        case .matrix: "Version matrix"
        case .devices: "Virtual devices"
        case .storage: "Tool storage"
        case .aiTools: "AI tool storage"
        #if !ROOM_APP_STORE
        case .worktrees: "Agent worktrees"
        #endif
        }
    }
}

/// What the dock offers on Developer.
nonisolated struct RoomDeveloperDock: Equatable, Sendable {
    enum Step: Equatable, Sendable { case stop, chooseProjects, scan(again: Bool) }
    let main: Step

    static func make(scanning: Bool, hasFolders: Bool, hasResults: Bool) -> RoomDeveloperDock {
        if scanning { return RoomDeveloperDock(main: .stop) }
        if !hasFolders, !hasResults { return RoomDeveloperDock(main: .chooseProjects) }
        return RoomDeveloperDock(main: .scan(again: hasResults))
    }
}

private enum RoomDeveloperLayoutState: Equatable { case intro, firstScan, workspace }

struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    var memoryReport: MemoryReport?
    #endif
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    private var section: RoomDeveloperSection { model.section }
    @State private var showingFolderPopover = false
    @State private var showingNotes = false
    @State private var showingDetail = false
    private let confirmationPrefix = "developer/remove/"

    private var availability: RoomDeveloperAvailability {
        var result = model.availability
        #if !ROOM_APP_STORE
        result.worktrees = agentWork.report != nil
        #endif
        return result
    }

    private var visibleSections: [RoomDeveloperSection] { RoomDeveloperTabRules.visible(availability, current: section) }

    private var layoutState: RoomDeveloperLayoutState {
        if !visibleSections.isEmpty { return .workspace }
        return model.isScanning ? .firstScan : .intro
    }

    private var words: RoomDeveloperWords {
        let headline = model.headline
        var input = RoomDeveloperWords.Input()
        input.projectsBytes = headline.parts.first { $0.kind == .inUse }.map(\.bytes).map { $0 + headline.unreferenced } ?? headline.unreferenced
        input.unreferencedBytes = headline.unreferenced
        input.projects = model.report?.projects.count ?? 0
        input.versions = model.report?.toolchains.count ?? 0
        input.devicesBytes = headline.parts.first { $0.kind == .devices }?.bytes ?? 0
        input.devices = (model.devicesReport?.androidDevices.count ?? 0) + (model.devicesReport?.simulatorDevices.count ?? 0)
        input.storageBytes = headline.parts.first { $0.kind == .toolStorage }?.bytes ?? 0
        input.aiBytes = headline.parts.first { $0.kind == .aiTools }?.bytes ?? 0
        input.aiTools = model.aiToolsReport?.aiStorageResources.count ?? 0
        #if !ROOM_APP_STORE
        input.worktreesBytes = agentWork.report?.items.reduce(Int64(0)) { $0 + $1.allocatedBytes } ?? 0
        input.worktrees = agentWork.report?.items.count ?? 0
        #endif
        input.partial = headline.partial
        return RoomDeveloperWords.make(section: section.rawValue, input)
    }

    var body: some View {
        Group {
            switch layoutState {
            case .intro:
                RoomScreenFrame(headline: .words("Your build tools"),
                                supporting: "Room finds the Gradle, Xcode and Android versions your projects use, and the ones nothing points to.",
                                note: "Room only reads sizes and version files", scrollsEvidence: true) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                        foldersButton
                        otherViews
                    }
                } action: {
                    EmptyView()
                }
                .transition(.opacity)
            case .firstScan:
                RoomScreenFrame(headline: .words("Reading your folders"), supporting: model.progress,
                                note: "Room only reads sizes and version files") {
                    RoomScanStrip(tiles: model.scanTiles)
                        .padding(.top, RoomTokens.Space.breath2)
                } action: {
                    EmptyView()
                }
                .transition(.opacity)
            case .workspace:
                let words = words
                RoomScreenFrame(headline: words.headline, supporting: model.isScanning ? model.progress : words.supporting,
                                note: section == .storage ? "Builds can always be made again" : "Room only reads sizes; nothing here moves",
                                scrollsEvidence: true, entersEvidence: false) {
                    VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                        if model.isScanning, !model.scanTiles.isEmpty {
                            RoomScanStrip(tiles: model.scanTiles).transition(.opacity)
                        }
                        HStack(alignment: .top, spacing: RoomTokens.Space.group) {
                            RoomDeveloperTabs(selected: section, values: tabValues) { model.section = $0 }
                            if !isWorktrees { foldersButton }
                        }
                        sectionContent.roomPanelChange(section)
                    }
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
        .sheet(isPresented: $showingNotes) {
            RoomScanIssuesSheet(issues: sectionReport?.issues.map {
                hide.masksNow ? "A resource could not be read." : "\($0.url.path): \($0.message)"
            } ?? [])
        }
    }

    /// Each room's size once it has been read (the same figure the headline shows for it).
    private var tabValues: [RoomDeveloperSection: String] {
        var worktreesBytes: Int64 = 0
        #if !ROOM_APP_STORE
        worktreesBytes = agentWork.report?.items.reduce(Int64(0)) { $0 + $1.allocatedBytes } ?? 0
        #endif
        return Dictionary(uniqueKeysWithValues: availability.sectionsWithData.map {
            ($0, RoomDeveloperFormat.whole(model.headlineBytes(for: $0, worktreesBytes: worktreesBytes)))
        })
    }

    private var sectionReport: DeveloperResourcesReport? {
        switch section {
        case .devices: model.devicesReport
        case .storage: model.storageReport
        case .aiTools: model.aiToolsReport
        default: model.report
        }
    }

    /// Worktrees are read from saved folders and agent locations, so that page has no folder choice of its own.
    private var isWorktrees: Bool {
        #if ROOM_APP_STORE
        false
        #else
        section == .worktrees
        #endif
    }

    private var hasResults: Bool { !availability.sectionsWithData.isEmpty }

    /// One button for the whole screen, worded the same on every section.
    static func scanTitle(isScanning: Bool, hasResults: Bool) -> String {
        isScanning ? "Stop" : hasResults ? "Rescan all" : "Scan all"
    }

    // MARK: Before the first scan

    private var dockMain: RoomDockAction {
        let dock = RoomDeveloperDock.make(scanning: model.isScanning, hasFolders: model.hasScannableFolders, hasResults: hasResults)
        let id = "RoomDeveloperScanButton"
        switch dock.main {
        case .stop:
            return RoomDockAction(title: Self.scanTitle(isScanning: true, hasResults: hasResults), filled: false,
                                  identifier: id) { model.stop() }
        case .chooseProjects:
            return RoomDockAction(title: "Choose projects folder…", symbol: "folder.badge.plus",
                                  enabled: !model.isChoosingFolder, identifier: id) { model.addFolder(role: .project) }
        case .scan(let again):
            return RoomDockAction(title: Self.scanTitle(isScanning: false, hasResults: again),
                                  symbol: again ? "arrow.clockwise" : "magnifyingglass",
                                  enabled: model.canScan && !model.isChoosingFolder, identifier: id) { model.scan() }
        }
    }

    /// Every folder control in one place: what Developer reads, and how to add to or remove from it.
    private var foldersButton: some View {
        Button { showingFolderPopover.toggle() } label: {
            HStack(spacing: RoomTokens.Space.tight) {
                Image(systemName: "folder")
                Text("Folders")
                if !model.sectionLocations.isEmpty {
                    RoomMaskable(model.sectionLocations.count.formatted()).foregroundStyle(RoomTokens.Ink.secondary)
                }
                Image(systemName: "chevron.down").font(RoomTokens.Typography.micro).foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .buttonStyle(RoomDropdownStyle(chevron: false))
        .fixedSize()
        .accessibilityIdentifier("RoomDeveloperFolders")
        .popover(isPresented: $showingFolderPopover, arrowEdge: .bottom) {
            folderPopover
                .padding(RoomTokens.Space.group)
                .frame(width: 360, alignment: .leading)
        }
    }

    private var folderPopover: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text("Folders Room reads").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
            if section == .aiTools || section == .devices {
                Menu {
                    ForEach(section == .aiTools ? RoomDeveloperFolderRole.aiRoles : RoomDeveloperFolderRole.deviceRoles) { role in
                        folderChoice(role)
                    }
                } label: {
                    Label(section == .aiTools ? "Choose Tool Folder…" : "Choose Device Folder…", systemImage: "folder.badge.plus")
                }
                .roomDropdown()
                .disabled(model.isScanning || model.isChoosingFolder)
                .accessibilityIdentifier(section == .aiTools ? "RoomDeveloperChooseAITool" : "RoomDeveloperChooseDeviceFolder")
            } else if section != .storage {
                // Saved-folder reuse (#1): a menu when there is a saved folder to pick, else a button.
                folderChoice(.project, title: "Projects Folder…", symbol: "folder.badge.plus")
                    .roomDropdown(chevron: !model.reusableFolders(for: .project).isEmpty)
                    .disabled(model.isScanning || model.isChoosingFolder)
                    .accessibilityIdentifier("RoomDeveloperAddFolder")
            }
            ForEach(model.sectionLocations, content: folderRow)
            if section != .aiTools {
                ForEach(model.folderSuggestions) { suggestion in
                    let action = Self.suggestionAction(for: suggestion.role)
                    HStack {
                        Label(suggestion.role.title, systemImage: suggestion.role.symbol)
                        Spacer()
                        Button(action) { model.useSuggestion(suggestion) }
                            .disabled(model.isScanning || model.isChoosingFolder)
                            .accessibilityLabel("\(action) \(suggestion.role.title)")
                    }
                }
                Menu("Choose another folder…") {
                    ForEach(model.selectableFolderRoles) { role in
                        folderChoice(role)
                    }
                }
                .roomDropdown()
                .disabled(model.isScanning || model.isChoosingFolder)
            }
            RoomInlineUndoRows(prefix: confirmationPrefix)
        }
        .font(RoomTokens.Typography.body)
    }

    private var otherViews: some View {
        HStack(spacing: RoomTokens.Space.group) {
            Text("Or look at")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            ForEach(RoomDeveloperSection.allCases.filter { $0 != .rooms && $0 != .matrix }, id: \.self) { other in
                Button(other.startLink) { model.section = other }
                    .roomLink(accent)
                    .font(RoomTokens.Typography.caption)
            }
        }
    }

    private var scanningRow: some View {
        HStack(spacing: RoomTokens.Space.row) {
            ProgressView().controlSize(.small)
            Text(model.progress)
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: After the first scan

    /// Each room leads with its largest things (mockup), and keeps the full review one click away in More detail.
    private var largest: [RoomDeveloperLargestRow] {
        switch section {
        case .rooms: RoomDeveloperLargest.projects(model.summary)
        case .matrix: RoomDeveloperLargest.toolchains(model.report)
        case .devices: RoomDeveloperLargest.devices(model.devicesReport)
        case .storage: RoomDeveloperLargest.storage(model.storageReport)
        case .aiTools: RoomDeveloperLargest.aiTools(model.aiToolsReport)
        #if !ROOM_APP_STORE
        case .worktrees: RoomDeveloperLargest.worktrees(agentWork.report)
        #endif
        }
    }

    private var emptyLine: String {
        #if !ROOM_APP_STORE
        if section == .worktrees {
            if agentWork.report == nil { return model.isScanning ? "Not read yet" : "Scan all to look for agent worktrees" }
            return "No agent worktrees found"
        }
        #endif
        if !model.hasFoldersForSection {
            switch section {
            case .rooms, .matrix: return "Choose a projects folder to fill this page"
            case .devices: return "Choose a device folder to fill this page"
            case .storage: return "Choose a tool folder to fill this page"
            default: return "Choose an AI tool folder to fill this page"
            }
        }
        if sectionReport == nil { return model.isScanning ? "Not read yet" : "Scan all to fill this page" }
        return switch section {
        case .rooms: "No project builds found yet"
        case .matrix: "No toolchains found yet"
        case .devices: "No virtual devices in the chosen folders"
        case .storage: "No tool storage in the chosen folders"
        case .aiTools: "No recognised AI tool storage found"
        #if !ROOM_APP_STORE
        case .worktrees: "No agent worktrees found"
        #endif
        }
    }

    @ViewBuilder private var sectionContent: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            RoomDeveloperLargestList(rows: largest, empty: emptyLine)
            DisclosureGroup("More detail", isExpanded: $showingDetail) {
                Group {
                    switch section {
                    case .rooms, .matrix, .devices, .storage, .aiTools:
                        review
                    #if !ROOM_APP_STORE
                    case .worktrees:
                        RoomAgentWorkView(model: agentWork, memoryReport: memoryReport)
                    #endif
                    }
                }
                .padding(.top, RoomTokens.Space.row)
            }
            .font(RoomTokens.Typography.body)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .roomEnter(2 + min(largest.count, RoomDeveloperLargest.limit))
        }
    }

    @ViewBuilder private func folderChoice(_ role: RoomDeveloperFolderRole, title: String? = nil, symbol: String? = nil) -> some View {
        let folders = model.reusableFolders(for: role)
        if folders.isEmpty {
            Button { model.addFolder(role: role) } label: {
                Label(title ?? role.title, systemImage: symbol ?? role.symbol)
            }
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
                Label(title ?? role.title, systemImage: symbol ?? role.symbol)
            }
        }
    }

    private func folderRow(_ location: RoomDeveloperLocation) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: location.role.symbol)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(location.role.title)
                RoomMaskable(location.folder.name, kind: .name)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
                    .help(hide.masksNow ? "Folder name hidden" : location.folder.url.path)
            }
            Spacer(minLength: 0)
            RoomInlineConfirmButton(id: confirmationPrefix + location.id, title: "Stop reading…",
                confirmTitle: "Stop reading this folder?", doneLine: "Room no longer reads this folder. Its files are untouched.",
                isAllowed: !model.isScanning, stage: { model.stageRemoval(location) },
                commit: { model.commitRemoval(location) }, undo: { model.undoRemoval(location) })
                .help("Room stops reading this folder. Nothing in it is changed or deleted. Folder access is managed in Settings.")
        }
    }

    @ViewBuilder private var review: some View {
        if model.isScanning { scanningRow.padding(.horizontal, RoomTokens.Space.inner) }
        if section == .storage {
            toolStorage
        } else if section == .aiTools {
            RoomDeveloperAIStorageView(report: model.aiToolsReport, hasFolders: !model.sectionLocations.isEmpty)
        } else if section == .devices {
            deviceInventory
        } else if model.report == nil {
            if !model.isScanning {
                Text("Choose a projects folder, then Scan all to see what each project uses.")
                    .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
            }
        } else {
            switch section {
            case .rooms:
                if let summary = model.summary {
                    RoomDeveloperRoomsView(summary: summary, unreferenced: model.unreferenced)
                }
            case .matrix:
                if let summary = model.summary {
                    RoomDeveloperMatrixView(summary: summary)
                }
            case .devices, .storage, .aiTools:
                EmptyView()
            #if !ROOM_APP_STORE
            case .worktrees:
                EmptyView()
            #endif
            }
        }
        if let report = sectionReport, report.isPartial || !report.issues.isEmpty {
            HStack(spacing: RoomTokens.Space.row) {
                if report.isPartial {
                    Label(report.cancelled ? "Stopped · partial results" : "Partial results. Sizes marked ≥ are lower bounds.",
                          systemImage: "info.circle")
                }
                Spacer(minLength: 0)
                if !report.issues.isEmpty {
                    Button { showingNotes = true } label: {
                        RoomMaskable("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")")
                    }
                    .roomLink(accent)
                }
            }
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Ink.secondary)
        }
    }

    @ViewBuilder private var deviceInventory: some View {
        if let report = model.devicesReport {
            if model.sectionLocations.contains(where: { $0.role == .android }) {
                RoomDeveloperDevicesTable(devices: report.androidDevices)
            }
            if model.sectionLocations.contains(where: { $0.role == .simulators }) {
                RoomDeveloperSimulatorDevices(devices: report.simulatorDevices)
            }
        } else if !model.isScanning {
            RoomDeveloperGroup(title: "Virtual devices") {
                Text(model.sectionLocations.isEmpty
                    ? "Choose an Android virtual device folder or a Simulator Devices folder."
                    : "Scan all to see the virtual devices in your chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private var toolStorage: some View {
        RoomDeveloperGroup(title: "Tool storage", caption: model.sectionLocations.contains(where: { $0.role == .simulatorRuntimes })
            ? "Runtime sizes include standalone bundles and backing images, including Xcode exports. Manage installed runtimes in Xcode Settings → Components." : nil,
            trailing: {
                Menu {
                    ForEach(RoomDeveloperFolderRole.storageRoles) { role in
                        folderChoice(role)
                    }
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .roomDropdown()
                .disabled(model.isScanning || model.isChoosingFolder)
            }, content: {
            if let report = model.storageReport, !report.storageResources.isEmpty {
                RoomDeveloperRowList(items: RoomDeveloperList.bySize(report.storageResources,
                    bytes: \.allocatedBytes, name: { $0.runtime?.name ?? $0.kind.title })) { resource in
                    toolStorageRow(resource)
                }
            } else if !model.isScanning {
                Text(model.storageReport == nil
                    ? "Choose a tool folder, then Scan all."
                    : "No tool storage found in the chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        })
    }

    private func toolStorageRow(_ resource: DeveloperStorageResource) -> some View {
        let title = resource.runtime?.name ?? resource.kind.title
        let kindLine = resource.runtime?.build.map { "\(resource.kind.title) · \($0)" }
        return RoomDeveloperRow(title: title, masksTitle: resource.runtime != nil, subtitle: kindLine ?? resource.url.path,
                                subtitleKind: kindLine == nil ? .name : .figure,
                                bytes: resource.allocatedBytes, partial: resource.isPartial,
                                finderURL: resource.url, help: resource.kind.detail)
    }

    static var suggestionAction: String {
        #if ROOM_APP_STORE
        "Choose…"
        #else
        "Use"
        #endif
    }

    static func suggestionAction(for role: RoomDeveloperFolderRole) -> String {
        role.requiresFolderPicker ? "Choose…" : suggestionAction
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

private struct RoomDeveloperDevicesTable: View {
    let devices: [AndroidVirtualDeviceResource]
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @State private var selected: String?

    var body: some View {
        RoomDeveloperGroup(title: "Android devices") {
            if devices.isEmpty {
                Text("No Android devices found in the chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            } else {
                deviceTable
                Group {
                    if let device = devices.first(where: { $0.id == selected }) {
                        deviceEvidence(device)
                    }
                }.roomPanelChange(selected)
            }
        }
    }

    private var deviceTable: some View {
        Table(RoomDeveloperList.bySize(devices, bytes: \.allocatedBytes, name: \.displayName), selection: $selected) {
            TableColumn("Name") { RoomMaskable($0.displayName, kind: .name) }.width(min: 110, ideal: 150)
            TableColumn("API") { RoomMaskable($0.apiLevel ?? "—") }.width(min: 36, ideal: 42)
            TableColumn("ABI") { Text($0.abi ?? "—") }.width(min: 50, ideal: 65)
            TableColumn("Size") { RoomMaskable(RoomDeveloperFormat.whole($0.allocatedBytes, partial: $0.isPartial)).monospacedDigit() }
            TableColumn("Last used") { device in
                Text(device.lastUsedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—").help(device.lastUseNote)
            }
            TableColumn("Status") { Text($0.activity.state == .observedUse ? "In use" : "—") }
        }
        .frame(minHeight: 224)
    }

    private func deviceEvidence(_ device: AndroidVirtualDeviceResource) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack(spacing: RoomTokens.Space.row) {
                RoomMaskable(device.displayName, kind: .name).font(RoomTokens.Typography.section)
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([device.url])
                } label: {
                    Label("Show in Finder", systemImage: "arrow.up.forward.app")
                }
                .roomLink(accent)
            }
            Text(device.lastUseNote)
            if !hide.masksNow {
                ForEach(device.evidence) { item in
                    Text(item.label + " · " + item.uncertainty).textSelection(.enabled)
                }
            }
        }
        .font(RoomTokens.Typography.caption)
        .foregroundStyle(RoomTokens.Ink.secondary)
        .padding(RoomTokens.Space.inner)
        .background(RoomTokens.Surface.hover, in: .rect(cornerRadius: RoomTokens.Radius.row))
    }
}

private struct RoomDeveloperSimulatorDevices: View {
    let devices: [SimulatorDeviceResource]
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        RoomDeveloperGroup(title: "Apple simulators", caption: devices.isEmpty ? "No Apple simulators found in the chosen folders."
            : "Sizes cover each device’s apps and data. Xcode manages shared simulator runtimes separately.") {
            RoomDeveloperRowList(items: RoomDeveloperList.bySize(devices, bytes: \.allocatedBytes, name: \.displayName)) { device in
                RoomDeveloperRow(title: device.displayName, subtitle: Self.runtimeLabel(device.runtimeIdentifier), subtitleKind: .figure,
                                 bytes: device.allocatedBytes, partial: device.isPartial, finderURL: device.url)
            }
        }
    }

    private static func runtimeLabel(_ identifier: String?) -> String {
        guard let identifier else { return "Runtime unknown" }
        let name = identifier.dropFirst("com.apple.CoreSimulator.SimRuntime.".count)
        let parts = name.split(separator: "-", maxSplits: 1)
        guard let platform = parts.first, parts.count == 2 else { return String(name) }
        let displayPlatform = platform == "xrOS" ? "visionOS" : String(platform)
        return displayPlatform + " " + parts[1].replacingOccurrences(of: "-", with: ".")
    }
}
