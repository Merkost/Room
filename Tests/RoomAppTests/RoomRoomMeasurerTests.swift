import Foundation
import Synchronization
import Testing
@testable import RoomApp

@Suite("Read-only Room measurer")
struct RoomRoomMeasurerTests {
    @Test func injectedMeasurementRunsWithBalancedApprovedScopes() async {
        let started = Mutex<[URL]>([])
        let stopped = Mutex<[URL]>([])
        let url = URL(fileURLWithPath: "/fixture/Work")
        let ancestor = URL(fileURLWithPath: "/fixture")
        let point = RoomSizePoint(at: Date(), bytes: 8192, partial: true)
        let measurer = RoomRoomMeasurer(measure: { selected in
            #expect(selected == url)
            #expect(pthread_main_np() == 0)   // measured off the main thread
            return .measured(point)
        }, beginScope: { selected in started.withLock { $0.append(selected) }; return true },
           endScope: { selected in stopped.withLock { $0.append(selected) } })
        #expect(await measurer.measure(url: url, approvedScopes: [ancestor, url]) == .measured(point))
        #expect(Set(started.withLock { $0 }) == [ancestor, url])
        #expect(Set(stopped.withLock { $0 }) == [ancestor, url])
    }

    @Test func inactiveScopeIsNeverStopped() async {
        let stops = Mutex(0)
        let measurer = RoomRoomMeasurer(measure: { _ in .unavailable }, beginScope: { _ in false },
            endScope: { _ in stops.withLock { $0 += 1 } })
        #expect(await measurer.measure(url: URL(fileURLWithPath: "/fixture")) == .unavailable)
        #expect(stops.withLock { $0 } == 0)
    }

    @Test func missingFolderIsUnavailableInsteadOfAZeroSize() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(await RoomRoomMeasurer().measure(url: missing) == .unavailable)
    }

    @Test func diskMapIssuesProduceAPartialReadOnlyMeasurement() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/Room-Measurer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.bin")
        let data = Data(repeating: 0x52, count: 8192)
        try data.write(to: source)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("linked-file"), withDestinationURL: source)
        let measurement = await RoomRoomMeasurer().measure(url: directory)
        guard case let .measured(point) = measurement else { Issue.record("Expected a measured lower bound"); return }
        #expect(point.bytes > 0 && point.partial)
        #expect(try Data(contentsOf: source) == data)
    }
}
