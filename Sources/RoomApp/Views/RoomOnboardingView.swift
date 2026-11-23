import AppKit
import SwiftUI

struct RoomOnboardingView: View {
    let capacity: RoomVolumeCapacity?
    let isWorking: Bool
    let openPrivacySettings: () -> Void
    let onFinish: (RoomOnboardingChoice?) -> Void

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @State private var page = Page.welcome
    @State private var goesForward = true

    private enum Page: Int, CaseIterable {
        case welcome, choices

        var step: LocalizedStringKey {
            switch self {
            case .welcome: "onboarding.p1.step"
            case .choices: "onboarding.p2.step"
            }
        }
    }

    var body: some View {
        VStack(spacing: RoomTokens.Space.group) {
            ScrollView {
                switch page {
                case .welcome:
                    introduction.transition(pageTransition)
                case .choices:
                    routes.transition(pageTransition)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(RoomTokens.Space.breath1)
        .frame(width: RoomTokens.Onboarding.width, height: RoomTokens.Onboarding.height)
        .background(RoomTokens.Surface.group)
        .foregroundStyle(RoomTokens.Ink.graphite)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.breath1) {
            heading("onboarding.p1.title", subtitle: "onboarding.p1.body")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: RoomTokens.Space.group) {
                    storagePreview
                    safeguards
                        .frame(width: RoomTokens.Onboarding.supportingWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    storagePreview
                    safeguards
                }
            }
            .roomPanelArrival(from: RoomTokens.Space.row)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var storagePreview: some View {
        let plan = RoomOnboardingFlow.plan(capacityBytes: capacity?.capacityBytes, freeBytes: capacity?.freeBytes)
        return Group {
            if let plan {
                RoomDotPlanView(plan: plan, belowGoal: false, hidden: hide.masksNow,
                    displayHeight: RoomTokens.Onboarding.planHeight, staticPreview: true, selection: .constant(nil), openDiskMap: {})
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(RoomOnboardingFlow.planAccessibility(capacityBytes: plan.capacityBytes, freeBytes: plan.freeBytes,
                            hidden: hide.masksNow, format: RoomFormat.overviewBytes))
                            .accessibilityAddTraits(.isImage)
                    }
            } else {
                RoomMark().fill(accent.text, style: FillStyle(eoFill: true))
                    .frame(width: 104, height: 104)
                    .frame(maxWidth: .infinity, minHeight: RoomTokens.Onboarding.planHeight)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: RoomTokens.Onboarding.planWidth)
        .padding(RoomTokens.Space.row)
        .background(RoomTokens.Surface.canvas, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
        .overlay {
            RoundedRectangle(cornerRadius: RoomTokens.Radius.group).strokeBorder(RoomTokens.Surface.line)
        }
    }

    private var safeguards: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            safeguard("onboarding.p1.scan.title", detail: "onboarding.p1.scan", symbol: "map")
            safeguard("onboarding.p1.trash.title", detail: "onboarding.p1.trash", symbol: "arrow.uturn.backward")
            safeguard("onboarding.p1.privacy.title", detail: "onboarding.p1.privacy", symbol: "lock.shield")
        }
    }

    private func safeguard(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: RoomTokens.Space.row) {
            glyph(symbol)
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
                Text(title, bundle: RoomCopy.bundle).font(RoomTokens.Typography.section)
                Text(detail, bundle: RoomCopy.bundle)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var routes: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            heading("onboarding.p2.title", subtitle: "onboarding.p2.lead")
            routeChoices
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeChoices: some View {
        VStack(spacing: RoomTokens.Space.row) {
            #if ROOM_APP_STORE
            choice(.mapFolder, title: "onboarding.p2.map", detail: "onboarding.p2.map.store", symbol: "map")
            choice(.checkCaches, title: "onboarding.p2.caches", detail: "onboarding.p2.caches.store", symbol: "sparkles")
            #else
            choice(.mapFolder, title: "onboarding.p2.map", detail: "onboarding.p2.map.direct", symbol: "map")
            VStack(alignment: .trailing, spacing: RoomTokens.Space.tight) {
                choice(.checkCaches, title: "onboarding.p2.caches", detail: "onboarding.p2.caches.direct", symbol: "sparkles")
                Button(action: openPrivacySettings) {
                    Text("onboarding.p2.caches.permission", bundle: RoomCopy.bundle)
                        .font(RoomTokens.Typography.caption)
                }
                .roomLink(accent)
            }
            #endif
            choice(.menuBar, title: "onboarding.p2.memory", detail: "onboarding.p2.memory.detail", symbol: "memorychip")
        }
    }

    private func heading(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            Text(title, bundle: RoomCopy.bundle)
                .font(RoomTokens.Typography.hero)
                .tracking(RoomTokens.Typography.heroTracking)
                .accessibilityHeading(.h1)
            Text(subtitle, bundle: RoomCopy.bundle)
                .font(RoomTokens.Typography.lead)
                .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func choice(_ choice: RoomOnboardingChoice, title: LocalizedStringKey,
                        detail: LocalizedStringKey, symbol: String) -> some View {
        let prominent = RoomOnboardingFlow.isProminent(choice)
        let enabled = RoomOnboardingFlow.choicesEnabled(isWorking: isWorking)
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Radius.group)
        return Button { onFinish(choice) } label: {
            HStack(spacing: RoomTokens.Space.inner) {
                glyph(symbol)
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
                    Text(title, bundle: RoomCopy.bundle).font(RoomTokens.Typography.title)
                    Text(detail, bundle: RoomCopy.bundle)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: RoomTokens.Space.group)
                Image(systemName: "arrow.right")
                    .font(RoomTokens.Typography.section)
                    .foregroundStyle(prominent ? accent.text : RoomTokens.Ink.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, RoomTokens.Space.inner)
            .padding(.horizontal, RoomTokens.Onboarding.choicePadding)
            .contentShape(shape)
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.group))
        .background(prominent ? accent.wash : RoomTokens.Surface.canvas, in: shape)
        .overlay {
            shape.strokeBorder(prominent ? accent.text.opacity(0.25) : RoomTokens.Surface.line)
                .allowsHitTesting(false)
        }
        .opacity(enabled ? 1 : 0.55)
        .disabled(!enabled)
        .accessibilityIdentifier(choice.accessibilityIdentifier)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(RoomTokens.Typography.title)
            .foregroundStyle(accent.text)
            .frame(width: 34, height: 34)
            .background(accent.wash, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.row))
            .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: RoomTokens.Space.group) {
            if page == .choices {
                Button { move(to: .welcome) } label: {
                    Label {
                        Text("onboarding.p2.back", bundle: RoomCopy.bundle)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minHeight: RoomTokens.Sidebar.minimumTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("RoomOnboardingBack")
            }
            Spacer(minLength: 0)
            Button { onFinish(nil) } label: {
                Text("onboarding.p2.skip", bundle: RoomCopy.bundle)
                    .frame(minHeight: RoomTokens.Sidebar.minimumTarget)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("RoomOnboardingSkip")
            if page == .welcome {
                Button { move(to: .choices) } label: {
                    Text("onboarding.p1.continue", bundle: RoomCopy.bundle)
                }
                .roomScreenPrimary(accent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("RoomOnboardingContinue")
            }
        }
        .frame(minHeight: 36)
        .overlay { progress.allowsHitTesting(false) }
        .font(RoomTokens.Typography.body)
    }

    private var progress: some View {
        HStack(spacing: RoomTokens.Space.tight) {
            ForEach(Page.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == page ? accent.fill : RoomTokens.Surface.line2)
                    .frame(width: step == page ? 18 : 6, height: 6)
            }
        }
        .accessibilityRepresentation {
            Text(page.step, bundle: RoomCopy.bundle)
        }
    }

    private var pageTransition: AnyTransition {
        guard motion.isFull else { return .opacity }
        let offset = goesForward ? RoomTokens.Space.breath1 : -RoomTokens.Space.breath1
        return .asymmetric(insertion: .offset(x: offset).combined(with: .opacity),
                           removal: .offset(x: -offset).combined(with: .opacity))
    }

    private func move(to nextPage: Page) {
        let update = {
            goesForward = nextPage.rawValue > page.rawValue
            page = nextPage
        }
        if NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp {
            roomWithoutMotion(update)
        } else {
            withAnimation(motion.animation(RoomTokens.Motion.page), update)
        }
    }
}

private extension RoomOnboardingChoice {
    var accessibilityIdentifier: String {
        switch self {
        case .mapFolder: "RoomOnboardingMapFolder"
        case .checkCaches: "RoomOnboardingCheckCaches"
        case .menuBar: "RoomOnboardingMenuBar"
        }
    }
}
