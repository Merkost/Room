import AppKit
import RoomCore
import SwiftUI

@MainActor
struct RoomFolderAccessSettingsView: View {
    @Bindable var insights: RoomInsightsModel
    let rooms: RoomRoomsModel
    let isWorking: () -> Bool
    private let removalPrefix = "settings:access:"
    private let confirmation = RoomInlineConfirmCenter.shared
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var accessRevision = 0
    @Environment(\.roomMotion) private var motion

    private var folders: [RoomSettingsFolder] {
        var result = insights.accessFolders.map {
            RoomSettingsFolder(name: $0.name, url: $0.url, savedID: $0.id)
        }
        #if !ROOM_APP_STORE
        var paths = Set(result.map(\.id))
        for root in CacheConfiguration.standard.roots where root.scope != .singleFile {
            let path = root.url.standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue, paths.insert(path).inserted else { continue }
            result.append(RoomSettingsFolder(name: root.title, url: root.url, savedID: nil))
        }
        #endif
        return result
    }

    var body: some View {
        let folders = self.folders
        Form {
            Section {
                if folders.isEmpty && insights.unavailableAccessFolders.isEmpty {
                    Text("Choose folders Room can revisit.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                } else if !folders.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(folders) { folder in
                                VStack(spacing: 0) {
                                    RoomFolderRowHover { folderRow(folder) }
                                    if folder.id != folders.last?.id { Divider() }
                                }
                                .transition(motion.rowDisclosure)
                            }
                        }
                    }
                    .scrollDisabled(false)   // the list scrolls even though the tab itself never does
                    .frame(height: min(RoomTokens.Settings.folderListMaximumHeight,
                        CGFloat(folders.count) * RoomTokens.Settings.folderRowHeight))
                    .animation(motion.animation(RoomTokens.Motion.standard), value: folders.map(\.id))
                }
            }

            if !insights.unavailableAccessFolders.isEmpty {
                Section("Folders that need access") {
                    ForEach(insights.unavailableAccessFolders) { folder in
                        HStack(spacing: RoomTokens.Space.inner) {
                            Label(folder.name, systemImage: "folder.badge.questionmark")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if folder.url != nil {
                                Button("Renew Access…") { insights.renewAccess(to: folder) }
                                    .disabled(isWorking() || !insights.canChooseDiskLocation)
                            }
                            removeFolder(id: folder.id, name: folder.name)
                        }
                    }
                }
            }

            if !confirmation.stagedLines(prefix: removalPrefix).isEmpty {
                Section { RoomInlineUndoRows(prefix: removalPrefix) }
            }

            Section {
                HStack(spacing: RoomTokens.Space.row) {
                    Button("Add folder…") { insights.chooseAccessFolder() }
                    Spacer(minLength: 0)
                    #if ROOM_APP_STORE
                    if insights.hasRememberedHomeAccess {
                        Text("Home folder access remembered").foregroundStyle(.secondary)
                    } else {
                        Button("Remember home folder") { insights.chooseHomeAccess() }
                            .accessibilityIdentifier("RoomRememberHomeFolderButton")
                    }
                    #else
                    Button("Open Full Disk Access…") { insights.openPrivacySettings() }
                        .accessibilityIdentifier("RoomFullDiskAccessButton")
                    #endif
                }
                .buttonStyle(.glass).tint(nil)
            }

            Section {
                note("Room can look inside folders you add, including hidden files. To change anything, it asks again.")
                #if ROOM_APP_STORE
                note("One read approval covers accessible subfolders and hidden files. macOS can still protect locations; other volumes need separate approval. Changes require a reviewed write grant.")
                #endif
                if let accessNote = insights.accessNote { note(accessNote) }
            }
        }
        .formStyle(.grouped).scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { confirmation.finishAll(prefix: removalPrefix) }
        .onChange(of: controlActiveState) { _, state in
            if state == .key { accessRevision += 1 }
        }
    }

    private func folderRow(_ folder: RoomSettingsFolder) -> some View {
        let _ = accessRevision
        let status = RoomFolderAccessStatus.status(for: folder.url)
        return HStack(spacing: RoomTokens.Space.inner) {
            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                Text(folder.name).font(RoomTokens.Typography.bodyStrong).lineLimit(1)
                Text(folder.url.path).font(RoomTokens.Typography.path).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(status.text)
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                .contentTransition(.opacity)
                .animation(motion.animation(RoomTokens.Motion.standard), value: status.text)
            if status == .protectedByMacOS {
                Button("Allow…") {
                    #if ROOM_APP_STORE
                    insights.chooseAccessFolder()
                    #else
                    insights.openPrivacySettings()
                    #endif
                }
                .accessibilityLabel("Allow access to \(folder.name)")
            }
            // A saved folder can always be forgotten, readable or not (a stale or locked one most of all).
            if let savedID = folder.savedID {
                removeFolder(id: savedID, name: folder.name)
            }
        }
        .frame(minHeight: RoomTokens.Settings.folderRowHeight)
    }

    private func removeFolder(id: String, name: String) -> some View {
        let question = String(localized: "confirm.removeAccess", defaultValue: "Remove access to %@?", bundle: RoomCopy.bundle)
        let done = String(localized: "confirm.removeAccess.done", defaultValue: "Room no longer reads %@.", bundle: RoomCopy.bundle)
        return RoomInlineConfirmButton(id: removalPrefix + id, title: "Remove",
            confirmTitle: String.localizedStringWithFormat(question, name),
            doneLine: String.localizedStringWithFormat(done, name), isAllowed: !isWorking(),
            stage: {
                if rooms.rooms.contains(where: { $0.accessFolderID == id }) { rooms.cancelMeasurement() }
                insights.stageAccessRemoval(id: id)
            }, commit: { insights.forgetAccessFolder(id: id) },
            undo: { insights.undoAccessRemoval(id: id) })
    }

    private func note(_ text: String) -> some View {
        Text(text).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

nonisolated private struct RoomSettingsFolder: Identifiable {
    var id: String { url.standardizedFileURL.path }
    let name: String
    let url: URL
    let savedID: String?
}

/// A 120 ms hover wash behind a row, the only hover affordance in Settings; none under Reduce Motion's instant rule is needed
/// because it is opacity only.
@MainActor
private struct RoomFolderRowHover<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.roomMotion) private var motion

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: RoomTokens.Radius.tile, style: .continuous)
                .fill(hovering ? RoomTokens.Surface.hover : .clear).padding(.horizontal, -6))
            .onHover { hovering = $0 }
            .animation(motion.animation(RoomTokens.Motion.quick), value: hovering)
    }
}
