import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomCommandBarTests {
    private var items: [RoomCommandBar.Item] {
        var values = RoomSidebarValue.Input()
        values.freeBytes = 64_000_000_000
        return RoomCommandBar.items(values: values, developerRooms: ["Rooms", "Matrix", "Devices", "Storage", "AI Tools", "Worktrees"])
    }

    @Test func emptyQueryShowsTheSevenPlaces() {
        let results = RoomCommandBar().results(in: items)
        #expect(results.map(\.title) == ["Overview", "Disk Map", "Caches", "Developer", "Memory", "History", "Settings"])
        #expect(results.first?.value == .size("64 GB"), "values go through the formatter and Hide masks them in the view")
    }

    @Test func typingFiltersPlacesRoomsAndActions() {
        var bar = RoomCommandBar()
        bar.type("dev")
        let titles = bar.results(in: items).map(\.title)
        #expect(titles.first == "Developer")
        #expect(titles.contains("Developer, Matrix"))
        #expect(titles.count <= RoomCommandBar.maxResults)
        bar.type("make")
        #expect(bar.results(in: items).map(\.title) == ["Make room"])
        #expect(bar.results(in: items).first?.target == .action(.makeRoom))
        bar.type("HIDE")
        #expect(bar.results(in: items).map(\.target) == [.action(.hideSizes)], "case does not matter")
        bar.type("zzz")
        #expect(bar.results(in: items).isEmpty)
        #expect(bar.chosen(in: []) == nil)
    }

    @Test func arrowsMoveTheHighlightWithinTheList() {
        var bar = RoomCommandBar()
        let results = bar.results(in: items)
        bar.move(-1, count: results.count)
        #expect(bar.highlight == 0)
        bar.move(1, count: results.count)
        bar.move(1, count: results.count)
        #expect(bar.chosen(in: results)?.target == .place(.clean))
        for _ in 0..<20 { bar.move(1, count: results.count) }
        #expect(bar.highlight == results.count - 1)
        bar.type("c")
        #expect(bar.highlight == 0, "typing resets the highlight")
    }

    @Test func goToHasCommandK() {
        let items = RoomMenuModel.make(.init(destination: .overview, window: .main))
        #expect(items.first { $0.id == .goTo }?.shortcut == .init("k"))
    }
}
