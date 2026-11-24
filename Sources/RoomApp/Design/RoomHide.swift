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

/// A figure or name that Hide can mask. Toggling Hide dissolves the digits to bullets in 150 ms (a brief blur and a
/// cross-fade of the glyphs in place); geometry never moves. Reduce Motion keeps the cross-fade and drops the blur.
struct RoomMaskable: View {
    let text: String
    let kind: RoomMaskKind
    let spoken: String
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomNumericRoll) private var rolls

    init(_ text: String, kind: RoomMaskKind = .figure, spoken: String? = nil) {
        self.text = text
        self.kind = kind
        self.spoken = spoken ?? text
    }

    private enum Dissolve: CaseIterable { case rest, soft, clear }

    var body: some View {
        Text(verbatim: RoomHideMask.display(text, kind: kind, hide: hide))
            .monospacedDigit()
            .contentTransition(rolls && !hide.masksNow ? .numericText() : .opacity)
            .animation(hide.isPeeking ? nil : RoomTokens.Motion.fade, value: hide.isOn)
            .phaseAnimator(Dissolve.allCases, trigger: motion.isFull && !hide.isPeeking ? hide.isOn : nil) { content, phase in
                content.blur(radius: phase == .soft ? RoomHideMask.dissolveBlur : 0)
            } animation: { _ in
                .timingCurve(RoomTokens.Motion.fadeCurve, duration: RoomHideMask.dissolveDuration / 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RoomHideSpeech.value(spoken, hide: hide))
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
            if hidden {
                Text("hide.button.on", bundle: RoomCopy.bundle)
            } else {
                Text("hide.button", bundle: RoomCopy.bundle)
            }
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
        .accessibilityAddTraits(hidden ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("RoomHide")
        .accessibilityAction(.default) { control.toggle() }
    }
}
