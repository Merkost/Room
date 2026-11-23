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
}

struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    var memoryReport: MemoryReport?
    #endif
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    private var section: RoomDeveloperSection { model.section }
    @State private var showingFolders = false
    @State private var showingNotes = false
    private let confirmationPrefix = "developer/remove/"

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
            controls
            sectionContent.roomPanelChange(section)
        }
        .alert("Couldn’t add that folder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(hide.masksNow ? "Choose the folder again." : model.errorMessage ?? "") }
        .sheet(isPresented: $showingNotes) {
            RoomScanIssuesSheet(issues: sectionReport?.issues.map {
                hide.masksNow ? "A resource could not be read." : "\($0.url.path): \($0.message)"
            } ?? [])
        }
    }

    private var sectionReport: DeveloperResourcesReport? {
        switch section {
        case .devices: model.devicesReport
        case .storage: model.storageReport
        case .aiTools: model.aiToolsReport
        default: model.report
        }
    }

    private var showsResourceActions: Bool {
        #if ROOM_APP_STORE
        true
        #else
        section != .worktrees
        #endif
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoomTokens.Space.group) {
                    workspaceHeading
                    Spacer(minLength: 0)
                    if showsResourceActions { scanControls.fixedSize() }
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    workspaceHeading
                    if showsResourceActions { scanControls }
                }
            }
            Picker("Developer view", selection: $model.section) {
                ForEach(RoomDeveloperSection.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("RoomDeveloperSectionPicker")
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.popover))
    }

    private var workspaceHeading: some View {
        let title: LocalizedStringKey = switch section {
        case .devices: "Virtual devices"
        case .aiTools: "AI tool storage"
        default: "Project tools"
        }
        return HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: [.devices, .aiTools].contains(section) ? section.symbol : "hammer")
                .foregroundStyle(accent.text)
                .frame(width: 40, height: 40)
                .background(accent.wash, in: .rect(cornerRadius: RoomTokens.Radius.card))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(title)
                    .font(RoomTokens.Typography.title)
                    .accessibilityHeading(.h2)
                if ![.devices, .storage, .aiTools].contains(section), let root = model.projectRootLabel {
                    HStack(spacing: 4) {
                        if let report = model.report {
                            RoomMaskable(report.projects.count.formatted())
                            Text(report.projects.count == 1 ? "project in" : "projects in")
                        }
                        RoomMaskable(root, kind: .name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                }
            }
        }
    }

    private var scanControls: some View {
        HStack(spacing: RoomTokens.Space.row) {
            if section == .aiTools || section == .devices {
                Menu {
                    ForEach(section == .aiTools ? RoomDeveloperFolderRole.aiRoles : RoomDeveloperFolderRole.deviceRoles) { role in
                        folderChoice(role)
                    }
                } label: {
                    Label(section == .aiTools ? "Choose Tool Folder…" : "Choose Device Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(model.isScanning || model.isChoosingFolder)
                .accessibilityIdentifier(section == .aiTools ? "RoomDeveloperChooseAITool" : "RoomDeveloperChooseDeviceFolder")
            } else if section != .storage {
                folderChoice(.project, title: "Projects Folder…", symbol: "folder.badge.plus")
                    .roomSecondary()
                    .disabled(model.isScanning || model.isChoosingFolder)
                    .accessibilityIdentifier("RoomDeveloperAddFolder")
            }

            Button {
                if model.isScanning { model.stop() } else { model.scan() }
            } label: {
                Label(model.isScanning ? "Stop" : sectionReport == nil ? "Scan" : "Rescan",
                      systemImage: model.isScanning ? "stop.fill" : "arrow.clockwise")
            }
            .roomSecondary()
            .disabled(!model.isScanning && !model.canScan)
            .accessibilityIdentifier("RoomDeveloperScanButton")
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .rooms, .matrix, .devices, .storage, .aiTools:
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                if section != .aiTools || !model.sectionLocations.isEmpty { folderControls }
                review
            }
        #if !ROOM_APP_STORE
        case .worktrees:
            RoomAgentWorkView(model: agentWork, memoryReport: memoryReport)
        #endif
        }
    }

    private var folderControls: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            DisclosureGroup(isExpanded: $showingFolders) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
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
                        .disabled(model.isScanning || model.isChoosingFolder)
                    }
                }
                .padding(.top, RoomTokens.Space.inner)
            } label: {
                HStack(spacing: RoomTokens.Space.row) {
                    Label("Scan folders", systemImage: "folder")
                        .font(RoomTokens.Typography.section)
                    if !model.sectionLocations.isEmpty {
                        RoomMaskable(model.sectionLocations.count.formatted())
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                }
            }
            RoomInlineUndoRows(prefix: confirmationPrefix)
        }
        .font(RoomTokens.Typography.body)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
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
            RoomInlineConfirmButton(id: confirmationPrefix + location.id, title: "Remove…",
                confirmTitle: "Remove from Developer?", doneLine: "Folder removed from Developer",
                isAllowed: !model.isScanning, stage: { model.stageRemoval(location) },
                commit: { model.commitRemoval(location) }, undo: { model.undoRemoval(location) })
                .help("Folder access is managed in Settings.")
        }
    }

    @ViewBuilder private var review: some View {
        if model.isScanning {
            HStack(spacing: RoomTokens.Space.row) {
                ProgressView().controlSize(.small)
                Text(model.progress)
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .padding(RoomTokens.Space.inner)
        }
        if section == .storage {
            toolStorage
        } else if section == .aiTools {
            RoomDeveloperAIStorageView(report: model.aiToolsReport, hasFolders: !model.sectionLocations.isEmpty)
        } else if section == .devices {
            deviceInventory
        } else if model.report == nil {
            if !model.isScanning { emptyReview }
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
                    Label(report.cancelled ? "Stopped · partial results" : "Partial results", systemImage: "info.circle")
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
            Text(model.sectionLocations.isEmpty
                ? "Choose an Android virtual device folder or a Simulator Devices folder."
                : "Scan your chosen folders to see their virtual devices.")
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(RoomTokens.Space.group)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
        }
    }

    private var toolStorage: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack {
                Label("Tool storage", systemImage: "internaldrive")
                    .font(RoomTokens.Typography.title)
                    .accessibilityHeading(.h2)
                Spacer(minLength: 0)
                Menu {
                    ForEach(RoomDeveloperFolderRole.storageRoles) { role in
                        folderChoice(role)
                    }
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(model.isScanning || model.isChoosingFolder)
            }
            if model.sectionLocations.contains(where: { $0.role == .simulatorRuntimes }) {
                Text("Runtime sizes include standalone bundles and backing images, including Xcode exports. Manage installed runtimes in Xcode Settings → Components.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            if let report = model.storageReport, !report.storageResources.isEmpty {
                ForEach(report.storageResources) { resource in
                    toolStorageRow(resource)
                }
            } else if !model.isScanning {
                Text(model.storageReport == nil
                    ? "Choose a tool folder, then scan it."
                    : "No tool storage found in the chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private func toolStorageRow(_ resource: DeveloperStorageResource) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: resource.kind.symbol)
                .font(RoomTokens.Typography.section)
                .foregroundStyle(accent.text)
                .frame(width: 32, height: 32)
                .background(accent.wash, in: .rect(cornerRadius: RoomTokens.Radius.row))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                if let runtime = resource.runtime {
                    RoomMaskable(runtime.name, kind: .name)
                        .font(RoomTokens.Typography.section)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                    Text(runtime.build.map { "\(resource.kind.title) · \($0)" } ?? resource.kind.title)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .help(resource.kind.detail)
                } else {
                    Text(resource.kind.title)
                        .font(RoomTokens.Typography.section)
                        .foregroundStyle(RoomTokens.Ink.graphite)
                        .help(resource.kind.detail)
                }
                RoomMaskable(resource.url.path, kind: .name)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(hide.masksNow ? "Folder path hidden" : resource.url.path)
            }
            Spacer(minLength: 0)
            RoomMaskable((resource.isPartial ? "≥ " : "") + RoomFormat.bytes(resource.allocatedBytes))
                .font(RoomTokens.Typography.figure)
                .help(resource.isPartial ? "Measured size is a lower bound" : "Allocated disk space")
        }
        .padding(RoomTokens.Space.inner)
        .background(RoomTokens.Surface.hover, in: .rect(cornerRadius: RoomTokens.Radius.row))
    }

    private var emptyReview: some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
            Image(systemName: section.symbol)
                .font(RoomTokens.Typography.figure)
                .foregroundStyle(accent.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(model.locations.isEmpty ? "Choose what to scan" : "Ready to scan")
                    .font(RoomTokens.Typography.section)
                Text(model.locations.isEmpty
                    ? "Add a projects or toolchain folder."
                    : "Scan your chosen folders.")
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
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

private extension DeveloperStorageKind {
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
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Label("Android devices", systemImage: "iphone.gen3")
                .font(RoomTokens.Typography.title)
                .accessibilityHeading(.h2)
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
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }

    private var deviceTable: some View {
        Table(devices, selection: $selected) {
            TableColumn("Name") { RoomMaskable($0.displayName, kind: .name) }.width(min: 110, ideal: 150)
            TableColumn("API") { RoomMaskable($0.apiLevel ?? "—") }.width(min: 36, ideal: 42)
            TableColumn("ABI") { Text($0.abi ?? "—") }.width(min: 50, ideal: 65)
            TableColumn("Size") { RoomMaskable(($0.isPartial ? "≥ " : "") + RoomFormat.bytes($0.allocatedBytes)) }
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
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Label("Apple simulators", systemImage: "iphone.gen3")
                .font(RoomTokens.Typography.title)
                .accessibilityHeading(.h2)
            Text(devices.isEmpty ? "No Apple simulators found in the chosen folders."
                : "Sizes cover each device’s apps and data. Xcode manages shared simulator runtimes separately.")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            LazyVStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                ForEach(devices) { device in
                    HStack(spacing: RoomTokens.Space.inner) {
                        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                            RoomMaskable(device.displayName, kind: .name)
                                .font(RoomTokens.Typography.body.weight(.semibold))
                            Text(Self.runtimeLabel(device.runtimeIdentifier))
                                .font(RoomTokens.Typography.caption)
                                .foregroundStyle(RoomTokens.Ink.secondary)
                        }
                        Spacer(minLength: 0)
                        RoomMaskable((device.isPartial ? "≥ " : "") + RoomFormat.bytes(device.allocatedBytes))
                            .monospacedDigit()
                        if !hide.masksNow {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([device.url])
                            } label: {
                                Label("Show in Finder", systemImage: "arrow.up.forward.app").labelStyle(.iconOnly)
                            }
                            .roomLink(accent)
                            .help("Show device data in Finder")
                        }
                    }
                    .padding(RoomTokens.Space.row)
                    .background(RoomTokens.Surface.hover, in: .rect(cornerRadius: RoomTokens.Radius.row))
                }
            }
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
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
