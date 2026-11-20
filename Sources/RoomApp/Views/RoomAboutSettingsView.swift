import AppKit
import SwiftUI

@MainActor
struct RoomAboutSettingsView: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @Bindable var model: RoomViewModel
    @Bindable var insights: RoomInsightsModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.roomMotion) private var motion
    private let information = RoomAboutInformation()
    private let links = RoomAppLinks()

    private var version: String {
        #if ROOM_APP_STORE
        information.versionLabel + " · Mac App Store edition"
        #else
        information.versionLabel
        #endif
    }

    var body: some View {
        let madeRoom = model.makeRoomStore?.summary.header(format: { RoomCachesVisibility.bytes($0, hidden: hidden) },
            month: { $0.formatted(.dateTime.month(.wide).year()) })
        Form {
            Section {
                HStack(alignment: .top, spacing: RoomTokens.Space.breath1) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: RoomTokens.Settings.appIconSize, height: RoomTokens.Settings.appIconSize)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                            Text("Room").font(RoomTokens.Typography.aboutHeading)
                                .accessibilityAddTraits(.isHeader)
                            Text(version).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                                .accessibilityIdentifier("RoomAboutVersion")
                        }
                        Text("Room to breathe. Storage, clearly.")
                            .font(RoomTokens.Typography.aboutTagline)
                        Link(destination: links.website) {
                            HStack(spacing: RoomTokens.Space.row) {
                                Text("Merkost").font(RoomTokens.Typography.bodyStrong)
                                Text("room.merkost.dev").foregroundStyle(RoomTokens.Ink.secondary)
                                Image(systemName: "arrow.up.right")
                                    .font(RoomTokens.Typography.caption)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityIdentifier("RoomAboutWebsite")
                        HStack(spacing: RoomTokens.Space.inner) {
                            Link("GitHub", destination: links.sourceCode)
                                .accessibilityIdentifier("RoomAboutGitHub")
                            if let support = links.support {
                                Link("Support", destination: support)
                                    .accessibilityIdentifier("RoomSupportLink")
                            }
                            if let privacy = links.privacy {
                                Link("Privacy", destination: privacy)
                                    .accessibilityIdentifier("RoomPrivacyLink")
                            }
                        }
                        .font(RoomTokens.Typography.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let summary = madeRoom {
                Section {
                    RoomMaskable(summary).font(RoomTokens.Typography.caption)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }

            Section {
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    Button("Welcome to Room") {
                        insights.requestedWelcome = true
                        openWindow(id: "room")
                        NSApp.activate()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RoomReplayOnboarding")
                    Text("History shows what moved to Trash and which items Room can restore.")
                        .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Trash") { model.openTrash() }.buttonStyle(.glass)
                }
            }
        }
        .formStyle(.grouped).scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .animation(motion.animation(RoomTokens.Motion.settle), value: madeRoom != nil)
        .modifier(RoomHideRoot())
        .task { await model.refreshHistory() }
    }
}
