#if ROOM_APP_STORE
import Foundation
import RoomCore
import Testing
@testable import RoomApp

@Suite("Store read-grant scan invalidation") @MainActor
struct RoomStoreGrantRevocationTests {
    @Test("A forgotten actual read bookmark fences late scan configuration and permits a fresh approved scan")
    func forgetDuringConfigurationHandoff() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Room-StoreRevocation-" + UUID().uuidString, isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = cache.appendingPathComponent("old-owned-fixture")
        let contents = Data(repeating: 0x72, count: 8_192)
        try contents.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: file.path)
        let defaultsName = "Room-StoreRevocation-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        // Real read-only bookmark encoding/resolution, isolated to this fixture.
        // No native write approval, shared preferences or user paths are used.
        let access = RoomFileAccess(defaults: defaults)
        _ = try access.remember(cache)
        let approvedID = try #require(access.folders.first?.id)
        let configuration = CacheConfiguration(roots: [CacheRoot(id: "revocation-fixture", title: "Owned cache",
            subtitle: "Owned fixture", symbol: "shippingbox", category: "developer", url: cache,
            consequence: "Owned fixture", minimumAge: 7 * 86_400)], homeDirectory: root)
        let engine = CacheEngine(configuration: configuration, activityDirectory: root.appendingPathComponent("activity"))
        let gate = RevocationSnapshotGate()
        let model = RoomViewModel(engine: engine, access: access, inspectionConfigurationProvider: { engine in
            let snapshot = await engine.resolvedInspectionConfiguration()
            await gate.pauseOnce()
            return snapshot
        })
        model.scan()
        let oldWorker = try #require(model.scanTask)
        try await gate.waitUntilReached()
        #expect(model.isScanning && model.sources.contains { $0.bytes > 0 })

        access.forget(id: approvedID)
        model.storeAccessChanged()
        #expect(!model.isScanning && model.scanTask == nil && model.canScan)
        #expect(model.sources.isEmpty && model.protectedSources.isEmpty)
        #expect(model.inspectionConfiguration == nil && model.resultsScope == nil && model.lastScanned == nil)
        #expect(model.selectedEntryIDs.isEmpty && model.selection.isEmpty && model.selectedBytes == 0)
        #expect(!model.canReviewCleanup && !model.canEditSelection)
        #expect(model.storeReviewLocations.isEmpty && model.storeGrantedPaths.isEmpty)
        let resetRevision = model.configurationRevision
        let resetStatus = model.statusMessage
        await gate.release()
        await oldWorker.value
        // Awaiting the actual invalidated task proves its completion is drained;
        // an arbitrary yield or delay cannot establish this negative result.
        #expect(model.configurationRevision == resetRevision)
        #expect(model.statusMessage == resetStatus)
        #expect(model.sources.isEmpty && model.inspectionConfiguration == nil)
        #expect(model.totalBytes == 0 && model.clearableBytes == 0 && model.selectedEntryIDs.isEmpty)
        #expect(model.resultsScope == nil && model.isPartialScan && model.lastScanned == nil)
        #expect(!model.isScanning && model.canScan && !model.canReviewCleanup)

        _ = try access.remember(cache)
        model.scan()
        let freshWorker = try #require(model.scanTask)
        await freshWorker.value
        #expect(!model.isScanning && !model.isPartialScan && model.lastScanned != nil)
        #expect(model.inspectionConfiguration?.roots.map(\.id) == configuration.roots.map(\.id))
        #expect(model.selectedEntryIDs.count == 1 && model.canReviewCleanup)
        #expect(!model.canRunStoreCleanup && model.storeGrantedPaths.isEmpty)
        #expect(try Data(contentsOf: file) == contents)
        #expect(await engine.history().isEmpty)
    }
}

private actor RevocationSnapshotGate {
    private var reached = false
    private var released = false
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func pauseOnce() async {
        guard !reached else { return }
        reached = true
        let awaiting = Array(waiters.values)
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
                    throw RevocationGateError.timedOut
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

private enum RevocationGateError: Error { case timedOut }
#endif
