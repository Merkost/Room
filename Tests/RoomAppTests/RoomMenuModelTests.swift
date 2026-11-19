import Testing
@testable import RoomApp

@Suite("Main menu policy") @MainActor
struct RoomMenuModelTests {
    typealias Menu = RoomMenuModel

    @Test(arguments: Menu.Destination.allCases)
    func contextualCommandsMatchScreen(_ destination: Menu.Destination) {
        let idle = Menu.make(.init(destination: destination, canRescan: true, window: .main))
        let refresh = idle.filter { $0.shortcut == .init("r") }
        #expect(refresh.map(\.id) == (destination.rescan.map { [$0] } ?? []))
        #expect(refresh.allSatisfy { $0.enabled })

        let running = Menu.make(.init(destination: destination, canRescan: true, isScanning: true, window: .main))
        #expect(running.filter { $0.shortcut == .init("r") }.allSatisfy { !$0.enabled })
        #expect(running.first { $0.id == .stop }?.enabled == (destination.canStop ? true : nil))
    }

    @Test func shortcutsAreUniqueAndMatchSidebar() {
        let items = Menu.make(.init(destination: .overview, canRescan: true, window: .main)).filter(\.visible)
        let keys = items.compactMap(\.shortcut)
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains(.init("r", [.shift, .command])))
        #expect(items.filter { $0.section == .go }.dropFirst(2).dropLast().map(\.title) == RoomSidebar.items.map(\.title))
        #expect(items.filter { $0.section == .go }.dropFirst(2).dropLast().map { $0.shortcut?.key } == RoomSidebar.items.map(\.shortcut))
    }

    @Test func modalAndWorkingGuards() {
        let modal = Menu.make(.init(destination: .overview, canRescan: true, window: .modal))
        #expect(!modal.contains { $0.id == .refreshOverview })
        #expect(modal.first { $0.id == .overview }?.enabled == false)
        #expect(modal.first { $0.id == .pin }?.enabled == false)
        #expect(modal.first { $0.id == .settings }?.native == true)

        let working = Menu.make(.init(destination: .disk, canRescan: true, canEnclose: true, window: .main, isWorking: true))
        #expect(working.first { $0.id == .rescanDisk }?.enabled == false)
        #expect(working.first { $0.id == .enclosing }?.enabled == false)
        #expect(working.first { $0.id == .welcome }?.enabled == false)
        #expect(working.first { $0.id == .caches }?.enabled == true)
    }

    @Test func deferredAndEditionRules() {
        let direct = Menu.make(.init(edition: .direct))
        let store = Menu.make(.init(edition: .store))
        #expect(direct == store)
        let deferred = ["Show History", "Back", "Forward", "Show Inspector", "Customise Overview…", "Hide Sidebar Labels"]
        #expect(direct.allSatisfy { !deferred.contains($0.title) })
        #expect(direct.first { $0.id == .monitor }?.enabled == true)
        #expect(Menu.make(.init(menuBarEnabled: false)).first { $0.id == .monitor }?.enabled == false)
    }
}
