import Foundation

nonisolated struct RoomOverviewInput: Sendable {
    var capacityBytes: Int64?
    var freeBytes: Int64?
    var goalBytes: Int64?                     // nil = Use a goal off; adapter clamps enabled goal as Settings does
    var caches: RoomCachesCheck?
    var cachesInvalidatedAt: Date?            // persisted when Room starts any cache move/restore
    var now: Date
    var hidden: Bool
}

nonisolated enum RoomOverviewState: Equatable, Sendable {
    case capacityUnreadable, belowGoal, notMapped
}

nonisolated enum RoomOverviewAction: Equatable, Sendable {
    case retryCapacity, checkCaches, makeRoom(bytes: Int64, partial: Bool), usingSpaceOnly
}

nonisolated struct RoomOverviewPlanInput: Equatable, Sendable {
    // The measured inputs are available here before OVB-2 registers the shared drawing geometry.
    let capacityBytes: Int64
    let freeBytes: Int64
    let goalBytes: Int64?                     // dashed goal outline; nil below goal or when disabled
    var notMappedBytes: Int64 { capacityBytes - freeBytes }
    var notMappedDots: Int { 0 }
}

nonisolated struct RoomOverviewSnapshot: Equatable, Sendable {
    let state: RoomOverviewState
    let answer: String
    let sentence: String
    let action: RoomOverviewAction
    let actionTitle: String
    let accessibilityAnswer: String
    let accessibilityAction: String
    let plan: RoomOverviewPlanInput?
    let cachesCheckedAt: Date?

    static let cacheFreshness: TimeInterval = 86_400
    static let actionMinimumBytes: Int64 = 100_000_000
    static let noGoalSentenceMinimumBytes: Int64 = 1_000_000_000

    /// Adapter must distinguish absent capacity keys from a real zero free-space reading.
    static func make(_ input: RoomOverviewInput, format: (Int64) -> String) -> Self {
        guard let capacity = input.capacityBytes, let free = input.freeBytes,
              capacity > 0, free >= 0, free <= capacity else {
            let title = String(localized: "overview.capacity.title", defaultValue: "Room can't read free space right now.")
            let sentence = String(localized: "overview.capacity.say", defaultValue: "macOS didn't answer. Try again in a moment.")
            let retry = RoomOverviewCopy.retry
            return Self(state: .capacityUnreadable, answer: title, sentence: sentence,
                        action: .retryCapacity, actionTitle: retry, accessibilityAnswer: "\(title) \(sentence)",
                        accessibilityAction: retry, plan: nil, cachesCheckedAt: nil)
        }
        let goal = input.goalBytes.flatMap { $0 > 0 ? $0 : nil }
        let recorded = input.caches.flatMap { check -> RoomCachesCheck? in
            guard check.bytes >= 0, check.at <= input.now else { return nil }
            return check
        }
        let fresh = recorded.flatMap { check -> RoomCachesCheck? in
            guard input.now.timeIntervalSince(check.at) < cacheFreshness,
                  input.cachesInvalidatedAt.map({ $0 < check.at }) ?? true else { return nil }
            return check
        }
        let action: RoomOverviewAction
        if let fresh, fresh.bytes >= actionMinimumBytes {
            action = .makeRoom(bytes: fresh.bytes, partial: fresh.partial)
        } else if let fresh, !fresh.partial {
            action = .usingSpaceOnly
        } else {
            action = .checkCaches
        }
        let rawAnswer = String(localized: "overview.answer", defaultValue: "You have \(format(free)) of room.")
        let rawSentence: String
        let below = goal.map { free < $0 } ?? false
        if let goal {
            if below {
                rawSentence = String(localized: "overview.goal.below",
                    defaultValue: "\(format(goal - free)) under your \(format(goal)) goal.")
            } else if free == goal {
                rawSentence = String(localized: "overview.goal.at",
                    defaultValue: "At your \(format(goal)) goal. Nothing needs your attention.")
            } else {
                rawSentence = String(localized: "overview.goal.above",
                    defaultValue: "\(format(free - goal)) above your \(format(goal)) goal. Nothing needs your attention.")
            }
        } else if let fresh, fresh.bytes >= noGoalSentenceMinimumBytes {
            let size = "\(fresh.partial ? "≥ " : "")\(format(fresh.bytes))"
            rawSentence = String(localized: "overview.noGoal.caches", defaultValue: "\(size) of caches can go.")
        } else if let fresh, !fresh.partial {
            rawSentence = String(localized: "overview.noGoal.ok", defaultValue: "Nothing needs your attention.")
        } else {
            rawSentence = String(localized: "overview.first.say", defaultValue: "Nothing moves until you say so.")
        }
        let rawTitle: String
        let spokenAction: String
        switch action {
        case .retryCapacity:
            rawTitle = RoomOverviewCopy.retry
            spokenAction = rawTitle
        case .checkCaches:
            rawTitle = String(localized: "overview.action.check", defaultValue: "Check caches")
            spokenAction = String(localized: "overview.action.check.a11y", defaultValue: "Check caches. Opens Caches.")
        case .usingSpaceOnly:
            rawTitle = RoomOverviewCopy.usingSpace
            spokenAction = RoomOverviewCopy.usingSpaceAccessibility
        case .makeRoom(let bytes, let partial):
            if input.hidden {
                rawTitle = String(localized: "overview.action.makeRoom.hidden", defaultValue: "Make room")
                spokenAction = String(localized: "overview.action.makeRoom.hidden.a11y",
                    defaultValue: "Make room. Opens Caches. Sizes hidden.")
            } else {
                let size = format(bytes)
                let displayedSize = partial ? "≥ \(size)" : size
                let spokenSize = partial ? String(localized: "overview.a11y.atLeast", defaultValue: "at least \(size)") : size
                rawTitle = String(localized: "overview.action.makeRoom", defaultValue: "Make room · \(displayedSize)")
                spokenAction = String(localized: "overview.action.makeRoom.a11y",
                    defaultValue: "Make room, \(spokenSize) at last check. Opens Caches.")
            }
        }
        func visible(_ string: String) -> String {
            input.hidden ? String(string.map { $0.isNumber ? "•" : $0 }) : string
        }
        let spokenAnswer = input.hidden
            ? String(localized: "overview.answer.hidden.a11y", defaultValue: "Free space and goal hidden.")
            : "\(rawAnswer) \(rawSentence.replacingOccurrences(of: "≥ ", with: "at least "))"
        return Self(state: below ? .belowGoal : .notMapped,
                    answer: visible(rawAnswer), sentence: visible(rawSentence), action: action,
                    actionTitle: visible(rawTitle),
                    accessibilityAnswer: spokenAnswer,
                    accessibilityAction: spokenAction,
                    plan: .init(capacityBytes: capacity, freeBytes: free, goalBytes: below ? nil : goal),
                    cachesCheckedAt: recorded?.at)
    }
}

nonisolated enum RoomOverviewCopy {
    static var retry: String { String(localized: "common.retry", defaultValue: "Try again") }
    static var usingSpace: String {
        String(localized: "overview.action.using", defaultValue: "See what is using space")
    }
    static var usingSpaceAccessibility: String {
        String(localized: "overview.action.using.a11y", defaultValue: "See what is using space. Opens Disk Map.")
    }

    /// Generic greeting only.
    static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: String(localized: "overview.greeting.morning", defaultValue: "Good morning.")
        case 12..<18: String(localized: "overview.greeting.afternoon", defaultValue: "Good afternoon.")
        default: String(localized: "overview.greeting.evening", defaultValue: "Good evening.")
        }
    }
}
