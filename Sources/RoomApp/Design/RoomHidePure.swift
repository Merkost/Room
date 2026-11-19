import Foundation

/// What a masked string is: figures lose digits, names lose letters and digits; units and punctuation stay.
nonisolated enum RoomMaskKind: Sendable { case figure, name }

/// The environment value every masked view reads (`@Environment(\.roomHide)`).
nonisolated struct RoomHideState: Equatable, Sendable {
    var isOn: Bool                  // persisted as RoomHideSizes
    var isPeeking = false           // held ≥ 280 ms on the Hide button: reveal while held, never persisted
    /// What views draw: hidden only when on and not peeking.
    var masksNow: Bool { isOn && !isPeeking }
    static let off = RoomHideState(isOn: false)
}

nonisolated enum RoomHideMask {
    static func maskableCount(_ s: String, kind: RoomMaskKind) -> Int {
        s.reduce(0) { $0 + (($1.isNumber || (kind == .name && $1.isLetter)) ? 1 : 0) }
    }
    /// Characters masked `elapsedMS` after the toggle: 22 ms each, linear (PE-22). Reduce Motion: all at once.
    static func maskedCharacters(elapsedMS: Double, total: Int, fullMotion: Bool) -> Int {
        guard fullMotion else { return total }
        return min(total, max(0, Int(elapsedMS / RoomPure.hideStepMS)))
    }
    /// Unhide reverses from the right: the visible count grows by one character every 22 ms.
    static func remainingMasked(elapsedMS: Double, total: Int, fullMotion: Bool) -> Int {
        total - maskedCharacters(elapsedMS: elapsedMS, total: total, fullMotion: fullMotion)
    }
    static func duration(_ s: String, kind: RoomMaskKind, fullMotion: Bool) -> Double {
        fullMotion ? Double(maskableCount(s, kind: kind)) * RoomPure.hideStepMS : 0
    }
    /// The drawn string at rest: fully masked when Hide is on (widths unchanged: one "•" per character, tabular digits).
    static func display(_ s: String, kind: RoomMaskKind, hide: RoomHideState) -> String {
        hide.masksNow ? RoomPure.mask(s, first: .max, lettersToo: kind == .name) : s
    }
}

/// VoiceOver, help tags, tables and copy-to-clipboard: a masked value is the word "hidden", never the value (AX-4).
nonisolated enum RoomHideSpeech {
    static let hidden = "hidden"
    static func value(_ spoken: String, hide: RoomHideState) -> String { hide.masksNow ? hidden : spoken }
    /// For a labelled value: "Free, hidden" / "suby-kmp, Room, hidden" (a masked name is not spoken either).
    static func labelled(_ label: String, value: String, labelIsName: Bool, hide: RoomHideState) -> String {
        guard hide.masksNow else { return "\(label), \(value)" }
        return labelIsName ? "Room, \(hidden)" : "\(label), \(hidden)"
    }
    static func pasteboard(_ s: String, hide: RoomHideState) -> String? { hide.masksNow ? nil : s }
}

/// The Hide button's press: a tap toggles; holding ≥ 280 ms while on peeks and changes nothing (PE-23).
/// Holding while off just toggles on release (there is nothing to peek at).
nonisolated struct RoomHidePeek: Equatable, Sendable {
    enum Effect: Equatable, Sendable { case none, toggle, beginPeek, endPeek }
    private(set) var pressedAt: Date?
    private(set) var peeking = false

    mutating func press(at t: Date) -> Effect { pressedAt = t; return .none }
    /// Called by a one-shot 280 ms timer after `press`, with the Hide state at that moment.
    mutating func holdElapsed(at t: Date, isOn: Bool) -> Effect {
        // Date keeps seconds since 2001 as a Double: 280 ms after an arbitrary instant can read 279.99997 ms.
        // Half a millisecond of tolerance, so the timer that fires at 280 ms is never refused.
        guard let p = pressedAt, isOn, !peeking,
              t.timeIntervalSince(p) * 1000 >= RoomPure.peekHoldMS - 0.5 else { return .none }
        peeking = true
        return .beginPeek
    }
    mutating func release(at t: Date) -> Effect {
        defer { pressedAt = nil; peeking = false }
        if peeking { return .endPeek }
        guard pressedAt != nil else { return .none }
        return .toggle
    }
    /// Focus left the window or the button mid-hold: always end the peek, never toggle.
    mutating func cancel() -> Effect {
        defer { pressedAt = nil; peeking = false }
        return peeking ? .endPeek : .none
    }
}
