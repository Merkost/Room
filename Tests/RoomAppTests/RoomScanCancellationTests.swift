import Foundation
import RoomCore
import Testing
@testable import RoomApp

@Suite("Scan completion cancellation") @MainActor
struct RoomScanCancellationTests {
    @Test("Stop after engine completion cannot restore eligible selections during the configuration handoff")
    func stopDuringConfigurationHandoff() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Room-ScanCompletion-" + UUID().uuidString, isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = cache.appendingPathComponent("old-owned-fixture")
        let contents = Data(repeating: 0x63, count: 8_192)
        try contents.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: file.path)
        let configuration = CacheConfiguration(roots: [CacheRoot(id: "scan-completion-fixture", title: "Owned cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: cache,
            consequence: "Owned fixture", minimumAge: 7 * 86_400)], homeDirectory: root)
        let engine = CacheEngine(configuration: configuration, activityDirectory: root.appendingPathComponent("activity"))
        let gate = ScanSnapshotGate()
        let model = RoomViewModel(engine: engine, inspectionConfigurationProvider: { engine in
            // The real engine has returned its completed report before this
            // boundary. The gate changes scheduling, never the actual policy.
            let snapshot = await engine.resolvedInspectionConfiguration()
            await gate.pauseOnce()
            return snapshot
        })

        model.scan()
        try await gate.waitUntilReached()
        #expect(model.isScanning)
        model.cancelScan()
        await gate.release()
        try await waitForScan(model)

        let source = try #require(model.sources.first)
        #expect(source.bytes > 0 && source.isPartial)
        #expect(model.inspectionConfiguration?.roots.map(\.id) == configuration.roots.map(\.id))
        #expect(model.isPartialScan && model.lastScanned == nil)
        #expect(model.selectedEntryIDs.isEmpty && model.selection.isEmpty && model.selectedBytes == 0)
        #expect(model.cleanupCandidates(for: source.id).isEmpty)
        #expect(!model.canReviewCleanup && !model.canEditSelection && model.canScan)
        #expect(model.statusMessage?.contains("Scan stopped") == true)
        model.toggleSelection(id: source.id)
        model.selectRecommended()
        #expect(model.selectedEntryIDs.isEmpty)

        model.scan()
        try await waitForScan(model)
        #expect(!model.isPartialScan && model.lastScanned != nil)
        #expect(model.selectedEntryIDs.count == 1 && model.canReviewCleanup)
        #expect(try Data(contentsOf: file) == contents)
    }

    private func waitForScan(_ model: RoomViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while model.isScanning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isScanning)
    }
}

private actor ScanSnapshotGate {
    private var reached = false
    private var released = false
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func pauseOnce() async {
        guard !reached else { return }
        reached = true
        let awaiting = waiters.values
        waiters.removeAll()
        awaiting.forEach { $0.resume(returning: true) }
        await withCheckedContinuation { continuation in
            if released { continuation.resume() }
            else { pending = continuation }
        }
    }

    func release() {
        released = true
        pending?.resume()
        pending = nil
    }

    func waitUntilReached() async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    guard await self.arrival() else { throw CancellationError() }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw ScanSnapshotGateError.timedOut
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            release()
            throw error
        }
    }

    private func arrival() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if reached { continuation.resume(returning: true) }
                else if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters[id] = continuation }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(returning: false) }
}

private enum ScanSnapshotGateError: Error { case timedOut }
