import Foundation
import Observation
import Testing
@testable import RoomApp

@Suite("Pinned Room measurement lifecycle") @MainActor
struct RoomRoomsModelTests {
    @Test func pinMeasuresImmediatelyAndUnpinRetainsApproval() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let room = try #require(model.pinnedRoom)
        #expect(model.pinnedURL != nil && model.isMeasuring)
        #expect(model.state == .measuring(room))
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        let log = try #require(fixture.store.loadSizes()[room.id.uuidString])
        #expect(model.state == .measured(room, log))
        model.unpin()
        #expect(model.state == .empty && model.pinnedURL == nil)
        #expect(fixture.store.loadRooms().isEmpty && fixture.store.loadSizes().isEmpty)
        #expect(fixture.access.folders.count == 1)
    }

    @Test func repeatedRequestsShareOneMeasurement() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        model.measureIfNeeded()
        model.measureIfNeeded()
        #expect(await gate.count == 1)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        model.measureIfNeeded()
        #expect(await gate.count == 1)
    }

    @Test func unpinCancelsAndDiscardsACancellationResistantResult() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        model.unpin()
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(await gate.cancelledRequests == [0])
        #expect(model.state == .empty && fixture.store.loadSizes().isEmpty)
    }

    @Test func pinAddsAndWaitsForTheFirstMeasurement() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let second = fixture.root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let oldID = try #require(model.pinnedRoom?.id)
        model.pin(url: second)
        let newID = try #require(model.rooms.last?.id)
        let firstCount = await gate.count
        #expect(oldID != newID && firstCount == 1 && model.popoverRoom?.id == oldID)
        await gate.complete(0, with: .measured(fixture.point))
        await gate.waitForStarts(2)
        #expect(fixture.store.loadSizes()[oldID.uuidString]?.latest == fixture.point)
        await gate.complete(1, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(fixture.store.loadSizes()[newID.uuidString]?.latest == fixture.point)
    }

    @Test func invalidBookmarkShowsUnavailableWithoutMeasurement() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let room = RoomPinnedRoom(id: UUID(), accessFolderID: "invalid", name: "Work", order: 0)
        let payload = [["id": "invalid", "bookmark": Data([1, 2, 3]).base64EncodedString()]]
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "RoomApprovedFolderBookmarks")
        #expect(fixture.store.saveRooms([room]))
        let access = RoomFileAccess(defaults: fixture.defaults)
        let gate = RoomsMeasurementGate()
        let model = RoomRoomsModel(store: fixture.store, access: access, measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }))
        model.measureIfNeeded()
        #expect(model.state == .unavailable(room) && model.pinnedURL == nil)
        let count = await gate.count
        #expect(!model.isMeasuring && count == 0)
    }

    @Test func revokedApprovalAndMissingFolderBecomeUnavailable() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let room = try #require(model.pinnedRoom)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        try FileManager.default.removeItem(at: fixture.folder)
        #expect(model.pinnedURL == nil && model.state == .unavailable(room))
        fixture.access.forget(id: room.accessFolderID)
        model.measureIfNeeded()
        let count = await gate.count
        #expect(model.state == .unavailable(room) && count == 1)
    }

    @Test func workingSkipsMeasurementAndFreshnessExpiresAtOneHour() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let approved = try fixture.access.remember(fixture.folder)
        let accessID = try #require(fixture.access.folders.first { $0.url == approved }?.id)
        let room = RoomPinnedRoom(id: UUID(), accessFolderID: accessID, name: "Work", order: 0)
        #expect(fixture.store.saveRooms([room]))
        var log = RoomSizeLog()
        log.record(fixture.point, calendar: fixture.calendar)
        #expect(fixture.store.saveSizes([room.id.uuidString: log]))
        var working = true
        var now = fixture.point.at.addingTimeInterval(3601)
        let gate = RoomsMeasurementGate()
        let model = RoomRoomsModel(store: fixture.store, access: fixture.access,
            measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }), isWorking: { working }, now: { now }, calendar: fixture.calendar)
        model.measureIfNeeded()
        let count = await gate.count
        #expect(!model.isMeasuring && count == 0)
        working = false
        now = fixture.point.at.addingTimeInterval(3599)
        model.measureIfNeeded()
        #expect(!model.isMeasuring)
        now = now.addingTimeInterval(1)
        model.measureIfNeeded()
        await gate.waitForStarts(1)
        await gate.complete(0, with: .measured(RoomSizePoint(at: now, bytes: 9000, partial: false)))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(fixture.store.loadSizes()[room.id.uuidString]?.latest?.bytes == 9000)
    }

    @Test func partialMeasurementIsStoredAsALowerBound() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let partial = RoomSizePoint(at: fixture.point.at, bytes: 4096, partial: true)
        await gate.complete(0, with: .measured(partial))
        await roomsWaitUntil { !model.isMeasuring }
        let room = try #require(model.pinnedRoom)
        #expect(fixture.store.loadSizes()[room.id.uuidString]?.latest == partial)
        if case let .measured(_, log) = model.state { #expect(log.latest?.partial == true) }
        else { Issue.record("Expected a measured lower bound") }
    }

    @Test func cancelMeasurementKeepsPreviousDailyPoint() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        var now = fixture.point.at
        let model = RoomRoomsModel(store: fixture.store, access: fixture.access,
            measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }), now: { now }, calendar: fixture.calendar)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        now = now.addingTimeInterval(3601)
        model.measureIfNeeded()
        await gate.waitForStarts(2)
        model.cancelMeasurement()
        await gate.complete(1, with: .measured(RoomSizePoint(at: now, bytes: 16_384, partial: false)))
        await roomsWaitUntil { !model.isMeasuring }
        let room = try #require(model.pinnedRoom)
        #expect(fixture.store.loadSizes()[room.id.uuidString]?.latest == fixture.point)
    }

    @Test func startingFileWorkCancelsAnActiveMeasurementWithoutAnOpenWindow() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let working = RoomsWorkingState()
        let gate = RoomsMeasurementGate()
        let model = RoomRoomsModel(store: fixture.store, access: fixture.access,
            measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }), isWorking: { working.value },
            now: { fixture.point.at }, calendar: fixture.calendar)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        working.value = true
        await gate.waitForCancellation(0)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(fixture.store.loadSizes().isEmpty)
        working.value = false
        await Task.yield()
        #expect(await gate.count == 1)
    }

    @Test func addingAndUnpinningOneRoomPreservesOtherRooms() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let otherFolder = fixture.root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: false)
        let approved = try fixture.access.remember(otherFolder)
        let accessID = try #require(fixture.access.folders.first { $0.url == approved }?.id)
        let first = RoomPinnedRoom(id: UUID(), accessFolderID: "old-approval", name: "Old", order: 0)
        let other = RoomPinnedRoom(id: UUID(), accessFolderID: accessID, name: "Other", order: 1)
        #expect(fixture.store.saveRooms([first, other]))
        var otherLog = RoomSizeLog()
        otherLog.record(fixture.point, calendar: fixture.calendar)
        #expect(fixture.store.saveSizes([other.id.uuidString: otherLog]))
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let added = try #require(model.rooms.last)
        #expect(model.rooms.map(\.id) == [first.id, other.id, added.id])
        model.unpin(id: added.id)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(model.popoverRoom == first && fixture.store.loadRooms() == [first, other])
        #expect(fixture.store.loadSizes()[other.id.uuidString] == otherLog)
    }

    @Test func samePinSelectsExisting() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        let model = fixture.model(gate: gate)
        model.pin(url: fixture.folder)
        await gate.waitForStarts(1)
        let first = try #require(model.rooms.first)
        model.pin(url: fixture.folder)
        #expect(model.rooms == [first] && model.selectedRoomID == first.id)
        await gate.complete(0, with: .measured(fixture.point))
        await roomsWaitUntil { !model.isMeasuring }
        #expect(await gate.count == 1)
    }

    @Test func sixtyFifthRefusedBeforeRememberingAccess() throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let seeded = (0..<64).map { n in
            RoomPinnedRoom(id: UUID(), accessFolderID: "f-\(n)", name: "Room \(n)", order: n)
        }
        #expect(fixture.store.saveRooms(seeded))
        let model = fixture.model(gate: RoomsMeasurementGate())
        model.pin(url: fixture.folder)
        #expect(model.rooms == seeded)
        #expect(fixture.access.folders.isEmpty)
        #expect(model.notice == "Room keeps up to 64 Rooms. Unpin one first.")
    }

    @Test func pickerUsesPinCopyAndCancellationDoesNotCreateARoom() async throws {
        let fixture = try RoomsFixture()
        defer { fixture.remove() }
        let gate = RoomsMeasurementGate()
        var calls = 0
        let model = RoomRoomsModel(store: fixture.store, access: fixture.access,
            measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }), folderPicker: { _, message, prompt, initial in
                calls += 1
                #expect(message == "Room reads sizes here. It never changes anything in this folder.")
                #expect(prompt == "Pin" && initial != nil)
                return nil
            })
        model.chooseFolder()
        await roomsWaitUntil { calls == 1 }
        #expect(model.state == .empty && fixture.access.folders.isEmpty)
        #expect(await gate.count == 0)
    }
}

@MainActor private struct RoomsFixture {
    let root: URL
    let folder: URL
    let suite: String
    let defaults: UserDefaults
    let access: RoomFileAccess
    let store: RoomRoomsStore
    let calendar = Calendar(identifier: .gregorian)
    let point = RoomSizePoint(at: Date(timeIntervalSince1970: 1_794_876_000), bytes: 8192, partial: false)

    init() throws {
        suite = "RoomRoomsTests-" + UUID().uuidString
        defaults = try #require(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite, isDirectory: true)
        folder = root.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        access = RoomFileAccess(defaults: defaults)
        store = RoomRoomsStore(directory: root.appendingPathComponent("State", isDirectory: true))
    }

    func model(gate: RoomsMeasurementGate) -> RoomRoomsModel {
        RoomRoomsModel(store: store, access: access, measurer: RoomRoomMeasurer(measure: { await gate.measure($0) }),
            now: { point.at }, calendar: calendar)
    }

    func remove() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}

@Observable @MainActor private final class RoomsWorkingState {
    var value = false
}

private actor RoomsMeasurementGate {
    private var requests: [CheckedContinuation<RoomRoomMeasurement, Never>?] = []
    private var cancellationNotices: Set<Int> = []
    private(set) var cancelledRequests: [Int] = []
    var count: Int { requests.count }

    func measure(_ url: URL) async -> RoomRoomMeasurement {
        let index = requests.count
        let result: RoomRoomMeasurement = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in requests.append(continuation) }
        } onCancel: {
            Task { await self.noteCancellation(index) }
        }
        if Task.isCancelled { cancelledRequests.append(index) }
        return result
    }

    func waitForStarts(_ count: Int) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while requests.count < count, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(requests.count >= count)
    }

    func waitForCancellation(_ index: Int) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !cancellationNotices.contains(index), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(cancellationNotices.contains(index))
    }

    private func noteCancellation(_ index: Int) { cancellationNotices.insert(index) }

    func complete(_ index: Int, with result: RoomRoomMeasurement) {
        guard requests.indices.contains(index) else { Issue.record("Measurement did not start"); return }
        let request = requests[index]
        requests[index] = nil
        request?.resume(returning: result)
    }
}

@MainActor private func roomsWaitUntil(_ condition: () -> Bool) async {
    // Sleep, do not yield: the measurer runs at utility priority and starves under load (a yield loop spins the CPU it waits for).
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(condition())
}
