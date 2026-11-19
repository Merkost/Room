import AppKit
import SwiftUI

@MainActor
struct RoomAboutSettingsView: View {
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
        let madeRoom = RoomMadeRoom.summary(activities: model.activity)
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
                        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                            Text("Made by Konstantin Merenkov, Android & KMP developer.")
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: RoomTokens.Space.tight) {
                                Link("merkost.com", destination: links.developer)
                                if let support = links.support {
                                    Text("·").foregroundStyle(.secondary)
                                    Link("Support", destination: support)
                                        .accessibilityIdentifier("RoomSupportLink")
                                }
                                if let privacy = links.privacy {
                                    Text("·").foregroundStyle(.secondary)
                                    Link("Privacy", destination: privacy)
                                        .accessibilityIdentifier("RoomPrivacyLink")
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(RoomTokens.Typography.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let summary = madeRoom {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.inner) {
                        RoomMaskable(RoomFormat.bytes(summary.bytes)).font(RoomTokens.Typography.madeRoom)
                            .fixedSize()
                            .contentTransition(.numericText(value: Double(summary.bytes)))
                            .animation(motion.animation(RoomTokens.Motion.standard, fallback: nil), value: summary.bytes)
                        RoomMaskable(summary.caption).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
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
                    Text("Reviewed cache moves stay recoverable in Trash until you empty it.")
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
