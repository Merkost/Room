import CoreGraphics
import Foundation

nonisolated struct RoomOverviewInput: Sendable {
    var capacityBytes: Int64?
    var freeBytes: Int64?
    var goalBytes: Int64?                     // nil = Use a goal off; adapter clamps enabled goal as Settings does
    var caches: RoomCachesCheck?
    var cachesInvalidatedAt: Date?            // persisted when Room starts any cache move/restore
    var now: Date
    var hidden: Bool
    var homeKinds: RoomHomeKinds? = nil
    var mapActionAvailable = false
    var mapping: RoomOverviewMapping? = nil
    var stoppedMapping = false
}

nonisolated struct RoomOverviewMapping: Equatable, Sendable {
    var files: Int
    var allocatedBytes: Int64
    var finishedKinds: [String: Int64]
}

nonisolated enum RoomOverviewState: Equatable, Sendable {
    case capacityUnreadable, firstRun, belowGoal, notMapped, mapped, mapping, mappingStopped
}

nonisolated enum RoomOverviewAction: Equatable, Sendable {
    case retryCapacity, checkCaches, makeRoom(bytes: Int64, partial: Bool), usingSpaceOnly, mapMac, stopMapping
}

nonisolated struct RoomOverviewPlanInput: Equatable, Sendable {
    let capacityBytes: Int64
    let freeBytes: Int64
    let goalBytes: Int64?                     // dashed goal outline; nil below goal or when disabled
    var homeKinds: RoomHomeKinds?
    var mapping: RoomOverviewMapping?
    var kindValues: [(String, Double)] {
        if let mapping {
            let used = capacityBytes - freeBytes
            guard mapping.finishedKinds.values.reduce(0, +) <= used else { return [] }
            return mapping.finishedKinds.sorted { $0.key < $1.key }.map { ($0.key, Double($0.value) / 1e9) }
        }
        return homeKinds?.kinds ?? []
    }
    var notMappedBytes: Int64 { max(0, capacityBytes - freeBytes - kindValues.reduce(0) { $0 + Int64(($1.1 * 1e9).rounded()) }) }
    var capacityGB: Double { Double(capacityBytes) / 1e9 }
    var gbPerDot: Double { RoomPure.gbPerDot(capacityGB: capacityGB) }
    var fitsDotBudget: Bool { capacityGB / gbPerDot <= Double(RoomPure.targetDots) }
    var freeDots: Int {
        RoomPure.dotAlloc([(key: "free", gb: Double(freeBytes) / 1e9)], unit: gbPerDot)[0].dots
    }
    var notMappedDots: Int { 0 }

    func layout(size: CGSize) -> RoomDotPlan {
        RoomDotPlan.make(capacityGB: capacityGB, freeGB: Double(freeBytes) / 1e9, kinds: kindValues, size: size)
    }
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
    var mapLinkAvailable = false

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
        if input.mapping != nil {
            action = .stopMapping
        } else if input.mapActionAvailable, fresh == nil {
            action = .mapMac
        } else if let fresh, fresh.bytes >= actionMinimumBytes {
            action = .makeRoom(bytes: fresh.bytes, partial: fresh.partial)
        } else if let fresh, !fresh.partial {
            action = .usingSpaceOnly
        } else {
            action = .checkCaches
        }
        let firstRun = action == .mapMac && recorded == nil && input.homeKinds == nil && !input.stoppedMapping
        let rawAnswer: String
        if input.mapping != nil {
            rawAnswer = String(localized: "overview.mapping.title", defaultValue: "Room is looking.")
        } else if firstRun {
            rawAnswer = String(localized: "overview.first.title", defaultValue: "Room starts by looking.")
        } else {
            rawAnswer = String(localized: "overview.answer", defaultValue: "You have \(format(free)) of room.")
        }
        let rawSentence: String
        let below = goal.map { free < $0 } ?? false
        if let mapping = input.mapping {
            let size = format(mapping.allocatedBytes)
            let files = mapping.files.formatted()
            rawSentence = String(localized: "overview.mapping.progress", defaultValue: "Measured so far: \(size) in \(files) files.")
        } else if input.stoppedMapping {
            rawSentence = String(localized: "overview.mapping.stopped", defaultValue: "Mapping stopped. The plan shows what was measured.")
        } else if firstRun {
            rawSentence = String(localized: "overview.first.say", defaultValue: "Nothing moves until you say so.")
        } else if let goal {
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
        case .mapMac:
            rawTitle = RoomOverviewCopy.mapMac
            spokenAction = rawTitle
        case .stopMapping:
            rawTitle = String(localized: "overview.mapping.stop", defaultValue: "Stop mapping")
            spokenAction = rawTitle
        case .retryCapacity:
            rawTitle = RoomOverviewCopy.retry
            spokenAction = rawTitle
        case .checkCaches:
            rawTitle = String(localized: "overview.action.check", defaultValue: "Check caches")
            spokenAction = rawTitle
        case .usingSpaceOnly:
            rawTitle = RoomOverviewCopy.usingSpace
            spokenAction = RoomOverviewCopy.usingSpaceAccessibility
        case .makeRoom(let bytes, let partial):
            let size = format(bytes)
            let displayedSize = partial ? "≥ \(size)" : size
            let spokenSize = partial ? String(localized: "overview.a11y.atLeast", defaultValue: "at least \(size)") : size
            rawTitle = String(localized: "overview.action.makeRoom", defaultValue: "Make room · \(displayedSize)")
            spokenAction = String(localized: "overview.action.makeRoom.a11y",
                defaultValue: "Make room, \(spokenSize) at last check. Opens Caches.")
        }
        let state: RoomOverviewState
        if input.mapping != nil { state = .mapping }
        else if input.stoppedMapping { state = .mappingStopped }
        else if firstRun { state = .firstRun }
        else if below { state = .belowGoal }
        else if input.homeKinds != nil { state = .mapped }
        else { state = .notMapped }
        let snapshot = Self(state: state,
                            answer: rawAnswer, sentence: rawSentence, action: action,
                            actionTitle: rawTitle, accessibilityAnswer:
                                "\(rawAnswer) \(rawSentence.replacingOccurrences(of: "≥ ", with: "at least "))",
                            accessibilityAction: spokenAction,
                            plan: .init(capacityBytes: capacity, freeBytes: free, goalBytes: below || firstRun ? nil : goal,
                                        homeKinds: input.homeKinds, mapping: input.mapping),
                            cachesCheckedAt: recorded?.at,
                            mapLinkAvailable: input.mapActionAvailable && action != .mapMac && action != .stopMapping)
        return input.hidden ? snapshot.hidingSizes() : snapshot
    }

    func hidingSizes() -> Self {
        guard state != .capacityUnreadable, state != .firstRun else { return self }
        let title: String
        let spokenAction: String
        if case .makeRoom = action {
            title = String(localized: "overview.action.makeRoom.hidden", defaultValue: "Make room")
            spokenAction = String(localized: "overview.action.makeRoom.hidden.a11y",
                                  defaultValue: "Make room. Opens Caches. Sizes hidden.")
        } else {
            title = actionTitle
            spokenAction = accessibilityAction
        }
        return Self(state: state, answer: RoomPure.mask(answer, first: .max, lettersToo: false),
                    sentence: RoomPure.mask(sentence, first: .max, lettersToo: false), action: action,
                    actionTitle: title,
                    accessibilityAnswer: String(localized: "overview.answer.hidden.a11y", defaultValue: "Free space and goal hidden."),
                    accessibilityAction: spokenAction, plan: plan, cachesCheckedAt: cachesCheckedAt,
                    mapLinkAvailable: mapLinkAvailable)
    }
}

nonisolated enum RoomOverviewCopy {
    static var mapMac: String { String(localized: "overview.action.map", defaultValue: "Map your Mac") }
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
