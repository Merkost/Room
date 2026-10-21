import SwiftUI

/// A short introduction. Folder grants remain contextual inside Room, after this sheet closes.
struct RoomOnboardingView: View {
    let onFinish: () -> Void
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var introductionGlass
    @State private var page = 0

    private var allowsMotion: Bool { motionEnabled && !reduceMotion }
    private var pageAnimation: Animation? {
        allowsMotion ? .spring(response: 0.35, dampingFraction: 1) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 9) {
                RoomMark()
                    .fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: 25, height: 25)
                    .accessibilityHidden(true)
                Text("Room").font(RoomType.heading(16))
                Spacer()
                Text("\(page + 1) of 2")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .accessibilityLabel("Introduction, step \(page + 1) of 2")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(page == 0 ? "Room to breathe." : "Always in your hands.")
                    .font(RoomType.heading(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(page == 0
                     ? "See what’s taking space. Choose what to clear."
                     : "Scan first. Access and changes stay under your control.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if page == 0 {
                    overview
                        .transition(contentTransition)
                } else {
                    safeguards
                        .transition(contentTransition)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 240)

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("RoomOnboardingSkip")

                if page > 0 {
                    Button("Back") { move(to: 0) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("RoomOnboardingBack")
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<2) { index in
                        Capsule()
                            .fill(page == index ? Color.primary.opacity(0.65) : Color.primary.opacity(0.16))
                            .frame(width: 18, height: 6)
                            .scaleEffect(x: page == index ? 1 : 0.35, y: 1)
                    }
                }
                .accessibilityHidden(true)

                Spacer()

                Button {
                    if page == 0 { move(to: 1) } else { onFinish() }
                } label: {
                    HStack(spacing: 12) {
                        Text(page == 0 ? "Continue" : "Get started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.60, green: 0.79, blue: 0.91))
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(page == 0 ? "RoomOnboardingContinue" : "RoomOnboardingFinish")
            }
            .font(.system(size: 13))
        }
        .padding(32)
        .frame(width: 620, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(pageAnimation, value: page)
        .transaction { transaction in
            if !allowsMotion { transaction.disablesAnimations = true }
        }
    }

    private var overview: some View {
        VStack(spacing: 20) {
            RoomStorageVisual(selectionCount: 0, isScanning: false, motionEnabled: motionEnabled)
                .scaleEffect(1.1)
                .frame(height: 170)
            HStack(spacing: 30) {
                Label("Caches", systemImage: "internaldrive")
                Label("Memory", systemImage: "memorychip")
                Label("Disk Map", systemImage: "square.grid.2x2")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Read-only storage discovery, memory insight, and a visual disk map")
    }

    private var safeguards: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                safeguard("access", symbol: "folder.badge.plus", title: "Choose folder access",
                          detail: "Pick a folder inside Room. macOS manages system permissions.")
                safeguard("cleanup", symbol: "trash", title: "Review every cleanup",
                          detail: "Selected caches move to Trash with a recovery record.")
                #if ROOM_APP_STORE
                safeguard("memory", symbol: "memorychip", title: "Understand memory",
                          detail: "See pressure, compression, and swap with local suggestions.")
                #else
                safeguard("memory", symbol: "memorychip", title: "Memory without surprises",
                          detail: "Choose apps for a normal quit; their unsaved-work prompts remain.")
                #endif
            }
        }
    }

    private func safeguard(_ id: String, symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffect(reduceTransparency ? .identity : .regular,
                     in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffectID(id, in: introductionGlass)
        .glassEffectTransition(allowsMotion ? .materialize : .identity)
        .accessibilityElement(children: .combine)
    }

    private var contentTransition: AnyTransition {
        allowsMotion ? .opacity.combined(with: .offset(y: 8)) : .opacity
    }

    private func move(to nextPage: Int) {
        withAnimation(pageAnimation) { page = nextPage }
    }
}
