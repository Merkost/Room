import AppKit
import RoomCore
import SwiftUI

@MainActor
struct RoomFolderAccessSettingsView: View {
    @Bindable var insights: RoomInsightsModel
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var accessRevision = 0

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
                if folders.isEmpty {
                    Text("Choose folders Room can revisit.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(folders) { folder in
                                folderRow(folder)
                                if folder.id != folders.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(height: min(RoomTokens.Settings.folderListMaximumHeight,
                        CGFloat(folders.count) * RoomTokens.Settings.folderRowHeight))
                }
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
                .buttonStyle(.glass)
            }

            Section {
                note("Room can look inside folders you add, including hidden files. To change anything, it asks again.")
                #if ROOM_APP_STORE
                note("One read approval covers accessible subfolders and hidden files. macOS can still protect locations; other volumes need separate approval. Changes require a reviewed write grant.")
                #endif
                if let accessNote = insights.accessNote { note(accessNote) }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
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
                Text(folder.url.path).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(status.text)
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
            if status.isReadable {
                if let savedID = folder.savedID {
                    Button("Remove") { insights.forgetAccessFolder(id: savedID) }
                        .accessibilityLabel("Remove access to \(folder.name)")
                }
            } else {
                Button("Allow…") {
                    #if ROOM_APP_STORE
                    insights.chooseAccessFolder()
                    #else
                    insights.openPrivacySettings()
                    #endif
                }
                .accessibilityLabel("Allow access to \(folder.name)")
            }
        }
        .frame(minHeight: RoomTokens.Settings.folderRowHeight)
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
