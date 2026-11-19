import AppKit
import RoomCore
import SwiftUI

enum RoomDeveloperSection: String, CaseIterable {
    case rooms = "Rooms", matrix = "Matrix", devices = "Devices"
    #if !ROOM_APP_STORE
    case worktrees = "Worktrees"
    #endif
}

struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    #if !ROOM_APP_STORE
    @Bindable var agentWork: AgentWorkModel
    var memoryReport: MemoryReport?
    #endif
    @Environment(\.roomHide) private var hide
    @State private var section = RoomDeveloperSection.rooms
    @State private var showingNotes = false
    private let confirmationPrefix = "developer/remove/"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Developer").font(RoomType.heading(24))
                    if let root = model.projectRootLabel {
                        HStack(spacing: 4) {
                            RoomMaskable((model.report?.projects.count ?? 0).formatted())
                            Text("projects in")
                            RoomMaskable(root, kind: .name).lineLimit(1).truncationMode(.middle)
                        }.font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Projects Folder…") { model.addFolder(role: .project) }
                    .roomSecondary().disabled(model.isScanning || model.isChoosingFolder)
                    .accessibilityIdentifier("RoomDeveloperAddFolder")
                Button(model.isScanning ? "Stop" : "Rescan") {
                    if model.isScanning { model.stop() } else { model.scan() }
                }
                .roomSecondary().disabled(!model.canScan)
                .accessibilityIdentifier("RoomDeveloperScanButton")
            }
            Picker("Developer view", selection: $section) {
                ForEach(RoomDeveloperSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .accessibilityIdentifier("RoomDeveloperSectionPicker")

            switch section {
            case .rooms, .matrix, .devices:
                review
            #if !ROOM_APP_STORE
            case .worktrees:
                RoomAgentWorkView(model: agentWork, memoryReport: memoryReport)
            #endif
            }
        }
        .alert("Couldn’t add that folder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(hide.masksNow ? "Choose the folder again." : model.errorMessage ?? "") }
        .sheet(isPresented: $showingNotes) {
            RoomScanIssuesSheet(issues: model.report?.issues.map {
                hide.masksNow ? "A resource could not be read." : "\($0.url.path): \($0.message)"
            } ?? [])
        }
    }

    @ViewBuilder private var review: some View {
        if !model.locations.isEmpty || !model.folderSuggestions.isEmpty {
            DisclosureGroup("Folders in this review") {
                VStack(spacing: 9) {
                    ForEach(model.locations) { location in
                        HStack {
                            Label(location.role.title, systemImage: location.role.symbol)
                            RoomMaskable(location.folder.name, kind: .name).lineLimit(1).foregroundStyle(.secondary)
                                .help(hide.masksNow ? "Folder name hidden" : location.folder.url.path)
                            Spacer()
                            RoomInlineConfirmButton(id: confirmationPrefix + location.id, title: "Remove…",
                                confirmTitle: "Remove from Developer?", doneLine: "Folder removed from Developer",
                                isAllowed: !model.isScanning, stage: { model.stageRemoval(location) },
                                commit: { model.commitRemoval(location) }, undo: { model.undoRemoval(location) })
                                .help("Folder access is managed in Settings.")
                        }
                    }
                    ForEach(model.folderSuggestions) { suggestion in
                        HStack {
                            Label(suggestion.role.title, systemImage: suggestion.role.symbol)
                            Spacer()
                            Button(Self.suggestionAction) { model.useSuggestion(suggestion) }
                                .disabled(model.isScanning || model.isChoosingFolder)
                                .accessibilityLabel("\(Self.suggestionAction) \(suggestion.role.title)")
                        }
                    }
                    Menu("Choose another folder…") {
                        ForEach(RoomDeveloperFolderRole.allCases.filter { $0 != .project }) { role in
                            Button(role.title) { model.addFolder(role: role) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.isScanning || model.isChoosingFolder)
                }.padding(.top, 9)
            }
        }
        RoomInlineUndoRows(prefix: confirmationPrefix)
        if model.isScanning {
            ProgressView(model.progress).controlSize(.small)
        }
        switch section {
        case .rooms:
            if let summary = model.summary {
                RoomDeveloperRoomsView(summary: summary, unreferenced: model.unreferenced)
            } else { emptyReview }
        case .matrix:
            if let summary = model.summary {
                RoomDeveloperMatrixView(summary: summary)
            } else { emptyReview }
        case .devices:
            if let report = model.report {
                RoomDeveloperDevicesTable(devices: report.androidDevices)
            } else { emptyReview }
        #if !ROOM_APP_STORE
        case .worktrees:
            EmptyView()
        #endif
        }
        if let report = model.report, report.isPartial || !report.issues.isEmpty {
            HStack {
                if report.isPartial {
                    Text(report.cancelled ? "Stopped · partial results" : "Partial results")
                }
                Spacer()
                if !report.issues.isEmpty {
                    Button { showingNotes = true } label: {
                        RoomMaskable("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")")
                    }.buttonStyle(.plain)
                }
            }.font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyReview: some View {
        Text(model.locations.isEmpty ? "Choose the folders you want Room to read." : "Rescan to see measurements from these folders.")
            .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }

    static var suggestionAction: String {
        #if ROOM_APP_STORE
        "Choose…"
        #else
        "Use"
        #endif
    }
}

private struct RoomDeveloperDevicesTable: View {
    let devices: [AndroidVirtualDeviceResource]
    @Environment(\.roomHide) private var hide
    @State private var selected: String?

    var body: some View {
        if devices.isEmpty {
            Text("No Android devices found in the chosen folders.")
                .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 15) {
                Table(devices, selection: $selected) {
                    TableColumn("Name") { RoomMaskable($0.displayName, kind: .name) }.width(min: 120, ideal: 150)
                    TableColumn("API") { RoomMaskable($0.apiLevel ?? "—") }.width(min: 36, ideal: 42)
                    TableColumn("ABI") { Text($0.abi ?? "—") }.width(min: 50, ideal: 65)
                    TableColumn("Size") { RoomMaskable(($0.isPartial ? "≥ " : "") + RoomFormat.bytes($0.allocatedBytes)) }
                    TableColumn("Last used") { device in
                        Text(device.lastUsedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—").help(device.lastUseNote)
                    }
                    TableColumn("Status") { Text($0.activity.state == .observedUse ? "In use" : "—") }
                }.frame(minHeight: 240)
                if let device = devices.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 7) {
                        RoomMaskable(device.displayName, kind: .name).font(RoomTokens.Typography.section)
                        Text(device.lastUseNote)
                        if !hide.masksNow {
                            ForEach(device.evidence) { item in
                                Text(item.label + " · " + item.uncertainty).textSelection(.enabled)
                            }
                        }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([device.url]) }
                    }
                    .font(RoomTokens.Typography.caption).frame(width: 180, alignment: .leading)
                }
            }
        }
    }
}
