import Foundation

/// Go to (⌘K): places, Developer rooms and actions in one list. Pure, so filtering and the highlight are tested.
nonisolated struct RoomCommandBar: Equatable, Sendable {
    enum Action: String, CaseIterable, Sendable { case checkCaches, makeRoom, scanProjects, hideSizes }

    enum Target: Equatable, Hashable, Sendable {
        case place(RoomDestination)
        case action(Action)
    }

    struct Item: Equatable, Identifiable, Sendable {
        let target: Target
        let title: String
        let glyph: RoomGlyph
        var value: RoomPlaceValue = .none
        var id: Target { target }
    }

    static let firstLook = 7
    static let maxResults = 8

    var query = ""
    private(set) var highlight = 0

    static func items(values: RoomPlaceValue.Input) -> [Item] {
        var items = RoomPlacePlan.places.map { place in
            Item(target: .place(place), title: RoomPlacePlan.title(place), glyph: RoomPlacePlan.glyph(place),
                 value: RoomPlaceValue.make(place, values))
        }
        items += Action.allCases.map { action in
            switch action {
            case .checkCaches: Item(target: .action(action), title: "Check caches", glyph: .caches, value: .words("Action"))
            case .makeRoom: Item(target: .action(action), title: "Make room", glyph: .overview, value: .words("Action"))
            case .scanProjects: Item(target: .action(action), title: "Scan Developer", glyph: .developer, value: .words("Action"))
            case .hideSizes: Item(target: .action(action), title: "Hide sizes", glyph: .eye, value: .words("Action"))
            }
        }
        return items
    }

    /// Empty query: the seven places. Typed: up to eight titles containing the text, case- and accent-insensitive.
    func results(in items: [Item]) -> [Item] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return Array(items.prefix(Self.firstLook)) }
        return Array(items.filter { $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .prefix(Self.maxResults))
    }

    mutating func type(_ text: String) {
        query = text
        highlight = 0
    }

    mutating func move(_ delta: Int, count: Int) {
        guard count > 0 else { highlight = 0; return }
        highlight = min(count - 1, max(0, highlight + delta))
    }

    mutating func point(at index: Int, count: Int) {
        guard index >= 0, index < count else { return }
        highlight = index
    }

    func chosen(in results: [Item]) -> Item? { results.indices.contains(highlight) ? results[highlight] : nil }
}
