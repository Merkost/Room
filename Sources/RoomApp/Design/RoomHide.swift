import AppKit
import Observation
import SwiftUI

@Observable @MainActor
final class RoomHideControl {
    static let preferenceKey = "RoomHideSizes"
    static let shared = RoomHideControl()
    private(set) var state: RoomHideState
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hold = RoomHidePeek()
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = RoomHideState(isOn: defaults.bool(forKey: Self.preferenceKey))
    }

    func toggle() {
        cancelPeek()
        state.isOn.toggle()
        defaults.set(state.isOn, forKey: Self.preferenceKey)
    }

    func beginPress() {
        guard hold.pressedAt == nil else { return }
        _ = hold.press(at: Date())
        guard state.isOn else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(Int(RoomPure.peekHoldMS))) }
            catch { return }
            guard let self, self.hold.holdElapsed(at: Date(), isOn: self.state.isOn) == .beginPeek else { return }
            self.state.isPeeking = true
        }
    }

    func endPress() {
        timer?.cancel()
        switch hold.release(at: Date()) {
        case .toggle: toggle()
        case .endPeek: state.isPeeking = false
        case .none, .beginPeek: break
        }
    }

    func cancelPeek() {
        timer?.cancel()
        _ = hold.cancel()
        state.isPeeking = false
    }
}

private struct RoomHideKey: EnvironmentKey {
    static let defaultValue = RoomHideState.off
}

extension EnvironmentValues {
    var roomHide: RoomHideState {
        get { self[RoomHideKey.self] }
        set { self[RoomHideKey.self] = newValue }
    }
}

struct RoomHideRoot: ViewModifier {
    var control: RoomHideControl = .shared

    func body(content: Content) -> some View {
        content.environment(\.roomHide, control.state)
    }
}

struct RoomMaskable: View {
    let text: String
    let kind: RoomMaskKind
    let spoken: String
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @State private var started: Date?

    init(_ text: String, kind: RoomMaskKind = .figure, spoken: String? = nil) {
        self.text = text
        self.kind = kind
        self.spoken = spoken ?? text
    }

    var body: some View {
        Group {
            if let started, motion.isFull, !hide.isPeeking {
                TimelineView(.animation) { context in
                    Text(verbatim: animatedText(elapsed: context.date.timeIntervalSince(started) * 1000))
                }
            } else {
                Text(verbatim: RoomHideMask.display(text, kind: kind, hide: hide))
            }
        }
        .monospacedDigit()
        .accessibilityLabel(RoomHideSpeech.value(spoken, hide: hide))
        .onChange(of: hide.isOn) { _, _ in
            let duration = RoomHideMask.duration(text, kind: kind, fullMotion: motion.isFull)
            started = duration > 0 ? Date() : nil
        }
        .onChange(of: hide.isPeeking) { _, _ in started = nil }
        .task(id: started) {
            guard started != nil else { return }
            do {
                let delay = RoomHideMask.duration(text, kind: kind, fullMotion: motion.isFull)
                try await Task.sleep(for: .milliseconds(Int64(delay)))
            } catch { return }
            started = nil
        }
    }

    private func animatedText(elapsed: Double) -> String {
        let total = RoomHideMask.maskableCount(text, kind: kind)
        let visible = RoomHideMask.maskedCharacters(elapsedMS: elapsed, total: total, fullMotion: motion.isFull)
        return RoomPure.mask(text, first: hide.isOn ? visible : total - visible, lettersToo: kind == .name)
    }
}

struct RoomGlobalHideButton: View {
    let control: RoomHideControl
    let globalCoverage: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let hidden = control.state.isOn
        HStack(spacing: RoomTokens.Space.tight) {
            Image(systemName: hidden ? "eye.slash" : "eye")
            Text(hidden ? "hide.button.on" : "hide.button", bundle: RoomCopy.bundle)
        }
        .font(RoomTokens.Typography.body)
        .padding(.horizontal, RoomTokens.Space.row)
        .frame(minHeight: RoomTokens.Sidebar.minimumTarget)
        .contentShape(Rectangle())
        .focusable()
        .focused($focused)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in control.beginPress() }
            .onEnded { _ in control.endPress() })
        .onKeyPress(.space, phases: .down) { _ in control.beginPress(); return .handled }
        .onKeyPress(.space, phases: .up) { _ in control.endPress(); return .handled }
        .onChange(of: focused) { _, focused in if !focused { control.cancelPeek() } }
        .onDisappear { control.cancelPeek() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            control.cancelPeek()
        }
        .help(globalCoverage ? "Hide sizes and names. Hold to peek." : "Hide sizes on Overview.")
        .accessibilityLabel(globalCoverage ? "Hide sizes and names" : "Hide sizes on Overview")
        .accessibilityValue(hidden ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { control.toggle() }
    }
}
