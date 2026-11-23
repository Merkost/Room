import Foundation

nonisolated enum RoomCopyLint {
    struct Finding: Equatable, Sendable { let key: String; let rule: String }

    /// Keys allowed to say "Made … of room": only the ledger's stage-2 path (16 §5).
    static let stage2Keys: Set<String> = ["make.stage2", "make.stage2.line", "make.partly", "week.made", "history.header",
                                          "settings.about.made"]
    static let bannedWords = ["Clean", "Delete", "Free up"]

    static func lint(_ catalogue: [String: String]) -> [Finding] {
        var out: [Finding] = []
        for (key, value) in catalogue.sorted(by: { $0.key < $1.key }) {
            if value.range(of: #"\bMade\b.*\bof room\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               !stage2Keys.contains(key) { out.append(.init(key: key, rule: "made-outside-stage2")) }
            for word in bannedWords where value.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
                out.append(.init(key: key, rule: "banned:\(word)"))
            }
            if value.contains("!") { out.append(.init(key: key, rule: "exclamation")) }
            if value.contains("(s)") { out.append(.init(key: key, rule: "plural-by-parenthesis")) }
            let specifiers = value.matches(of: /%(\d+\$)?(@|d|lld|ld)/).count
            let positional = value.matches(of: /%\d+\$/).count
            if specifiers > 1, positional != specifiers { out.append(.init(key: key, rule: "non-positional-specifiers")) }
        }
        return out
    }
}
