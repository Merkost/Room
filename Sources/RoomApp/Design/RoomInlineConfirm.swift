import Foundation

/// PE-27 inline confirm for Room's own records (remove a folder approval, forget a Room, clear the ignore list,
/// forget history, delete a saved view, reset Overview). Never for Move to Trash.
/// D-FND-7: the second press STAGES the change (the record stops being used at once) and it is COMMITTED when the
/// 8 s Undo line ends, the window closes, or Room quits. Undo cancels the stage; nothing irreversible happened yet.
nonisolated struct RoomInlineConfirm: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case armed(until: Date)        // the button shows its confirm ("Remove access to ~/Projects?") for 4 s
        case staged(until: Date)       // the row is gone; "Room no longer reads ~/Projects. Undo" for 8 s
    }
    enum Effect: Equatable, Sendable { case none, arm, stage, commit, undo, disarm }

    static let armed: TimeInterval = 4      // RoomTokens.Motion.confirmArmed
    static let undo: TimeInterval = 8       // RoomTokens.Motion.undoWindow
    private(set) var phase: Phase = .idle

    mutating func press(at t: Date) -> Effect {
        switch phase {
        case .idle: phase = .armed(until: t.addingTimeInterval(Self.armed)); return .arm
        case .armed(let until):
            guard t < until else { phase = .armed(until: t.addingTimeInterval(Self.armed)); return .arm }
            phase = .staged(until: t.addingTimeInterval(Self.undo)); return .stage
        case .staged: return .none                              // the row is gone; nothing to press
        }
    }
    /// One timer fires at the phase deadline (no polling).
    mutating func tick(at t: Date) -> Effect {
        switch phase {
        case .armed(let until) where t >= until: phase = .idle; return .disarm
        case .staged(let until) where t >= until: phase = .idle; return .commit
        default: return .none
        }
    }
    /// Esc or a click elsewhere disarms an armed button; it never affects a staged change (Undo is the way back).
    mutating func escape() -> Effect {
        if case .armed = phase { phase = .idle; return .disarm }
        return .none
    }
    mutating func undoPressed(at t: Date) -> Effect {
        guard case .staged(let until) = phase, t < until else { return .none }
        phase = .idle; return .undo
    }
    /// Window closing, navigation away, app termination: a staged change is committed, an armed one disarmed.
    mutating func flush() -> Effect {
        switch phase {
        case .idle: return .none
        case .armed: phase = .idle; return .disarm
        case .staged: phase = .idle; return .commit
        }
    }
}
