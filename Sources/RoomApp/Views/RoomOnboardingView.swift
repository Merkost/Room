import SwiftUI

struct RoomOnboardingView: View {
    let capacity: RoomVolumeCapacity?
    let isWorking: Bool
    let openPrivacySettings: () -> Void
    let onFinish: (RoomOnboardingChoice?) -> Void

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @State private var page = 1
    @State private var entered = false
    @State private var goesForward = true

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
            Group {
                if page == 1 { introduction.transition(pageTransition) }
                else { routes.transition(pageTransition) }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            footer
        }
        .padding(RoomTokens.Space.breath1)
        .frame(width: RoomTokens.Onboarding.width, height: RoomTokens.Onboarding.height)
        .background(RoomTokens.Surface.group)
        .foregroundStyle(RoomTokens.Ink.graphite)
        .onAppear { withAnimation(motion.animation(RoomTokens.Motion.settle)) { entered = true } }
    }

    private var introduction: some View {
        let plan = RoomOnboardingFlow.plan(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes)
        return HStack(alignment: .center, spacing: RoomTokens.Space.breath1) {
            if let plan {
                RoomDotPlanView(plan: plan, belowGoal: false, hidden: hide.masksNow,
                                displayHeight: RoomTokens.Onboarding.planHeight, staticPreview: true, openDiskMap: {})
                    .frame(width: RoomTokens.Onboarding.planWidth)
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(RoomOnboardingFlow.planAccessibility(capacityBytes: plan.capacityBytes, freeBytes: plan.freeBytes,
                            hidden: hide.masksNow, format: RoomFormat.overviewBytes))
                            .accessibilityAddTraits(.isImage)
                    }
                    .opacity(entered ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                Text("onboarding.p1.title", bundle: RoomCopy.bundle)
                    .font(RoomTokens.Typography.aboutHeading)
                    .accessibilityAddTraits(.isHeader)
                Text("onboarding.p1.body", bundle: RoomCopy.bundle)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                safeguard("onboarding.p1.scan", symbol: "map")
                safeguard("onboarding.p1.trash", symbol: "arrow.uturn.backward")
                safeguard("onboarding.p1.privacy", symbol: "checkmark")
            }
            .font(RoomTokens.Typography.body)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(entered ? 1 : 0)
            .offset(y: entered || !motion.isFull ? 0 : RoomTokens.Space.group)
            .animation(motion.animation(RoomTokens.Motion.onboardingText), value: entered)
        }
        .frame(maxWidth: .infinity)
    }

    private func safeguard(_ key: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
            Image(systemName: symbol).foregroundStyle(accent.text).accessibilityHidden(true)
            Text(key, bundle: RoomCopy.bundle)
        }
    }

    private var routes: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text("onboarding.p2.title", bundle: RoomCopy.bundle)
                .font(RoomTokens.Typography.aboutHeading).accessibilityAddTraits(.isHeader)
            Text("onboarding.p2.lead", bundle: RoomCopy.bundle)
                .font(RoomTokens.Typography.body).foregroundStyle(RoomTokens.Ink.secondary)
            VStack(spacing: 0) {
                choice(.mapFolder, title: "onboarding.p2.map", symbol: "map") {
                    #if ROOM_APP_STORE
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        Text("onboarding.p2.map.store", bundle: RoomCopy.bundle)
                        Text("onboarding.p2.map.store.reads", bundle: RoomCopy.bundle)
                    }
                    #else
                    Text("onboarding.p2.map.direct", bundle: RoomCopy.bundle)
                    #endif
                }
                Divider()
                choice(.checkCaches, title: "onboarding.p2.caches", symbol: "sparkles") {
                    #if ROOM_APP_STORE
                    Text("onboarding.p2.caches.store", bundle: RoomCopy.bundle)
                    #else
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        Text("onboarding.p2.caches.direct", bundle: RoomCopy.bundle)
                        Button(action: openPrivacySettings) {
                            Text("onboarding.p2.caches.permission", bundle: RoomCopy.bundle)
                        }
                        .roomLink(accent)
                    }
                    #endif
                }
                Divider()
                choice(.menuBar, title: "onboarding.p2.memory", symbol: "memorychip") { EmptyView() }
            }
        }
    }

    private func choice<Supporting: View>(_ choice: RoomOnboardingChoice, title: LocalizedStringKey,
                                          symbol: String, @ViewBuilder supporting: () -> Supporting) -> some View {
        HStack(alignment: .center, spacing: RoomTokens.Space.group) {
            Group {
                if RoomOnboardingFlow.isProminent(choice) {
                    choiceButton(choice, title: title, symbol: symbol).roomPrimary(accent)
                } else {
                    choiceButton(choice, title: title, symbol: symbol).roomSecondary()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            supporting()
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(RoomTokens.Space.row)
                .frame(width: RoomTokens.Onboarding.supportingWidth, alignment: .leading)
                .background(RoomTokens.Surface.canvas, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
        }
        .padding(.vertical, RoomTokens.Onboarding.choicePadding)
        .accessibilityElement(children: .contain)
    }

    private func choiceButton(_ choice: RoomOnboardingChoice, title: LocalizedStringKey, symbol: String) -> some View {
        Button {
            onFinish(choice)
        } label: {
            Label {
                Text(title, bundle: RoomCopy.bundle)
            } icon: {
                Image(systemName: symbol)
            }
        }
        .disabled(!RoomOnboardingFlow.choicesEnabled(isWorking: isWorking))
    }

    private var footer: some View {
        HStack(spacing: RoomTokens.Space.group) {
            Button { onFinish(nil) } label: { Text("onboarding.p2.skip", bundle: RoomCopy.bundle) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("RoomOnboardingSkip")
            if page == 2 {
                Button { move(to: 1) } label: { Text("onboarding.p2.back", bundle: RoomCopy.bundle) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RoomOnboardingBack")
            }
            Spacer()
            if page == 1 {
                Text("onboarding.p1.step", bundle: RoomCopy.bundle)
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
                Button { move(to: 2) } label: { Text("onboarding.p1.continue", bundle: RoomCopy.bundle) }
                    .roomPrimary(accent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("RoomOnboardingContinue")
            } else {
                Text("onboarding.p2.step", bundle: RoomCopy.bundle)
                    .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .font(RoomTokens.Typography.body)
    }

    private var pageTransition: AnyTransition {
        guard motion.isFull else { return .opacity }
        let offset = goesForward ? RoomTokens.Space.breath1 : -RoomTokens.Space.breath1
        return .asymmetric(insertion: .offset(x: offset).combined(with: .opacity),
                           removal: .offset(x: -offset).combined(with: .opacity))
    }

    private func move(to nextPage: Int) {
        goesForward = nextPage > page
        withAnimation(motion.animation(RoomTokens.Motion.page)) { page = nextPage }
    }
}
