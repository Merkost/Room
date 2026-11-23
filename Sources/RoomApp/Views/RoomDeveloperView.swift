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
    @State private var showingFolders = false
    @State private var showingNotes = false
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

    var body: some View {
        Group {
            switch layoutState {
            case .intro: intro.transition(.opacity)
            case .firstScan: firstScan.transition(.opacity)
            case .workspace: workspace.transition(.opacity)
            }
        }
        .animation(motion.animation(RoomTokens.Motion.fade), value: layoutState)
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

    // MARK: Before the first scan

    private var intro: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            startPrompt
            Text("Room only reads sizes and version files. Nothing is moved or deleted.")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            folderControls(quiet: true)
            otherViews
        }
        .frame(maxWidth: RoomTokens.Space.measure, alignment: .leading)
        .padding(.top, RoomTokens.Space.breath2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startPrompt: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text("See which build tools are taking your disk.")
                .font(RoomTokens.Typography.figure)
                .accessibilityHeading(.h2)
            Text("Room finds the Gradle, Xcode and Android versions your projects use, and the ones nothing points to.")
                .font(RoomTokens.Typography.lead)
                .foregroundStyle(RoomTokens.Ink.secondary)
            Button {
                if model.canScan { model.scan() } else { model.addFolder(role: .project) }
            } label: {
                Text(model.canScan ? "Scan" : "Choose projects folder…")
            }
            .roomPrimary(accent)
            .disabled(model.isScanning || model.isChoosingFolder)
            .accessibilityIdentifier("RoomDeveloperScanButton")
        }
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

    private var firstScan: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Text("Reading your folders…")
                .font(RoomTokens.Typography.figure)
                .accessibilityHeading(.h2)
            scanningRow
            Button("Stop") { model.stop() }
                .roomSecondary()
                .accessibilityIdentifier("RoomDeveloperScanButton")
        }
        .frame(maxWidth: RoomTokens.Space.measure, alignment: .leading)
        .padding(.top, RoomTokens.Space.breath2)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var workspace: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
            if showsResourceActions {
                if model.headline.hasAnyData {
                    RoomDeveloperHeader(headline: model.headline) { scanControls }
                } else {
                    HStack { Spacer(minLength: 0); scanControls }
                }
            }
            tabs
            sectionContent.roomPanelChange(section)
        }
    }

    private var tabs: some View {
        HStack(spacing: RoomTokens.Space.group) {
            Picker("Developer view", selection: $model.section) {
                ForEach(visibleSections, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("RoomDeveloperSectionPicker")
            let hidden = RoomDeveloperTabRules.hidden(availability, current: section)
            if !hidden.isEmpty {
                Menu("More views") {
                    ForEach(hidden, id: \.self) { other in
                        Button { model.section = other } label: { Label(other.startLink, systemImage: other.symbol) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(RoomTokens.Typography.caption)
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .animation(motion.animation(RoomTokens.Motion.fade), value: visibleSections)
    }

    private var scanControls: some View {
        HStack(spacing: RoomTokens.Space.row) {
            if section == .aiTools || section == .devices {
                Menu {
                    ForEach(section == .aiTools ? RoomDeveloperFolderRole.aiRoles : RoomDeveloperFolderRole.deviceRoles) { role in
                        Button { model.addFolder(role: role) } label: {
                            Label(role.title, systemImage: role.symbol)
                        }
                    }
                } label: {
                    Label(section == .aiTools ? "Choose Tool Folder…" : "Choose Device Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(model.isScanning || model.isChoosingFolder)
                .accessibilityIdentifier(section == .aiTools ? "RoomDeveloperChooseAITool" : "RoomDeveloperChooseDeviceFolder")
            } else if section != .storage {
                Button { model.addFolder(role: .project) } label: {
                    Label("Projects Folder…", systemImage: "folder.badge.plus")
                }
                .roomSecondary()
                .disabled(model.isScanning || model.isChoosingFolder)
                .accessibilityIdentifier("RoomDeveloperAddFolder")
            }

            scanButton
        }
    }

    @ViewBuilder private var scanButton: some View {
        let first = !model.isScanning && sectionReport == nil
        let button = Button {
            if model.isScanning { model.stop() } else { model.scan() }
        } label: {
            Label(model.isScanning ? "Stop" : sectionReport == nil ? "Scan" : "Rescan",
                  systemImage: model.isScanning ? "stop.fill" : "arrow.clockwise")
        }
        .disabled(!model.isScanning && !model.canScan)
        .accessibilityIdentifier("RoomDeveloperScanButton")
        if first { button.roomPrimary(accent) } else { button.roomSecondary() }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .rooms, .matrix, .devices, .storage, .aiTools:
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                review
                if section != .aiTools || !model.sectionLocations.isEmpty { folderControls(quiet: false) }
            }
        #if !ROOM_APP_STORE
        case .worktrees:
            RoomAgentWorkView(model: agentWork, memoryReport: memoryReport)
        #endif
        }
    }

    private func folderControls(quiet: Bool) -> some View {
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
                                Button(role.title) { model.addFolder(role: role) }
                            }
                        }
                        .disabled(model.isScanning || model.isChoosingFolder)
                    }
                }
                .padding(.top, RoomTokens.Space.inner)
            } label: {
                HStack(spacing: RoomTokens.Space.row) {
                    Label("Folders Room reads", systemImage: "folder")
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
        .padding(quiet ? 0 : RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(quiet ? Color.clear : RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
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
            if !model.isScanning { startPrompt }
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
                    : "Scan your chosen folders to see their virtual devices.")
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
                        Button { model.addFolder(role: role) } label: {
                            Label(role.title, systemImage: role.symbol)
                        }
                    }
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(model.isScanning || model.isChoosingFolder)
                .fixedSize()
            }, content: {
            if let report = model.storageReport, !report.storageResources.isEmpty {
                RoomDeveloperRowList(items: RoomDeveloperList.bySize(report.storageResources,
                    bytes: \.allocatedBytes, name: { $0.runtime?.name ?? $0.kind.title })) { resource in
                    toolStorageRow(resource)
                }
            } else if !model.isScanning {
                Text(model.storageReport == nil
                    ? "Choose a tool folder, then scan it."
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
