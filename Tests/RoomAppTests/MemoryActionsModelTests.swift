#if !ROOM_APP_STORE
import Foundation
import Testing
@testable import RoomCore
@testable import RoomApp

@Suite("Reviewed normal app quit requests") @MainActor
struct MemoryActionsModelTests {
    @Test("Only regular user applications with complete identities are offered")
    func eligibilityProtectsSystemAndRoom() {
        let snapshots = [
            fixtureApp(pid: 11),
            fixtureApp(pid: 99, identifier: "example.other", name: "Current process"),
            fixtureApp(pid: 12, identifier: "local.room.tests", name: "Another Room"),
            fixtureApp(pid: 13, identifier: "example.room", name: "Room"),
            fixtureApp(pid: 14, identifier: "com.apple.finder", name: "Finder", path: "/Applications/Finder.app"),
            fixtureApp(pid: 15, identifier: "example.system", name: "System App", path: "/System/Applications/System App.app"),
            fixtureApp(pid: 16, identifier: "example.helper", name: "Helper", path: "/Applications/Parent.app/Contents/Frameworks/Helper.app"),
            fixtureApp(pid: 17, identifier: "example.accessory", regular: false),
            fixtureApp(pid: 18, identifier: "example.closed", terminated: true),
            fixtureApp(pid: 19, identifier: "example.unknown", launchDate: nil),
            MemoryRunningApplication(pid: 20, name: "Missing bundle identity", bundleIdentifier: "example.missing",
                bundleURL: URL(fileURLWithPath: "/Applications/Missing.app"), launchDate: Date(), bundleIdentity: nil,
                isRegular: true, isTerminated: false, icon: nil)
        ]
        let eligible = MemoryActionsModel.eligibleApplications(snapshots, report: nil,
            currentPID: 99, currentBundleIdentifier: "local.room.tests")
        #expect(eligible.map(\.id) == [11])
    }

    @Test("Duplicate bundle instances and PIDs do not create duplicate selectable rows")
    func deduplication() {
        let first = fixtureApp(pid: 11)
        let duplicatePID = fixtureApp(pid: 11, identifier: "example.duplicate")
        let duplicateBundle = fixtureApp(pid: 12)
        let other = fixtureApp(pid: 13, identifier: "example.second", name: "Second", path: "/Applications/Second.app")
        let eligible = MemoryActionsModel.eligibleApplications([first, duplicatePID, duplicateBundle, other], report: nil,
            currentPID: 99, currentBundleIdentifier: "local.room.tests")
        #expect(Set(eligible.map(\.id)) == [11, 13])
    }

    @Test("Helper-dominated samples still offer user apps without invented RSS")
    func helpersDoNotHideAppsOrBecomeAppRAM() {
        let report = fixtureMemoryReport(processes: [MemoryProcess(id: 500, name: "Helper", residentBytes: 8_000_000)])
        let eligible = MemoryActionsModel.eligibleApplications([fixtureApp(pid: 11)], report: report,
            currentPID: 99, currentBundleIdentifier: "local.room.tests")
        #expect(eligible.count == 1)
        #expect(eligible.first?.residentBytes == nil)
        let measured = MemoryActionsModel.eligibleApplications([fixtureApp(pid: 11)],
            report: fixtureMemoryReport(processes: [MemoryProcess(id: 11, name: "Main", residentBytes: 1234)]),
            currentPID: 99, currentBundleIdentifier: "local.room.tests")
        #expect(measured.first?.residentBytes == 1234)
        let laterLaunch = MemoryActionsModel.eligibleApplications(
            [fixtureApp(pid: 11, launchDate: Date(timeIntervalSince1970: 200))],
            report: fixtureMemoryReport(processes: [MemoryProcess(id: 11, name: "Prior process", residentBytes: 1234)]),
            currentPID: 99, currentBundleIdentifier: "local.room.tests")
        #expect(laterLaunch.first?.residentBytes == nil)
    }

    @Test("A PID reused by a new launch clears a previous selection")
    func reusedPIDClearsSelection() {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: nil)
        model.toggleSelection(id: 11)
        #expect(model.selectedCount == 1)
        state.running = [fixtureApp(pid: 11, launchDate: Date(timeIntervalSince1970: 200))]
        model.refresh(from: nil)
        #expect(model.selection.isEmpty)
        #expect(state.requests.isEmpty)
    }

    @Test("Review freezes the exact app identity and refuses a changed launch before requesting quit")
    func changedLaunchCannotReceiveReviewedRequest() async throws {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: nil)
        model.toggleSelection(id: 11)
        let review = try #require(model.review())
        state.running = [fixtureApp(pid: 11, launchDate: Date(timeIntervalSince1970: 201))]
        await model.apply(review: review)
        #expect(state.requests.isEmpty)
        #expect(model.results.first?.status == .changed)
    }

    @Test("Replacing the bundle at the same path invalidates an approved quit")
    func changedBundleCannotReceiveReviewedRequest() async throws {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: nil)
        model.toggleSelection(id: 11)
        let review = try #require(model.review())
        state.running = [fixtureApp(pid: 11, inode: 999)]
        await model.apply(review: review)
        #expect(state.requests.isEmpty)
        #expect(model.results.first?.status == .changed)
    }

    @Test("An accepted request remains pending while its exact app is still running")
    func acceptedRequestIsNotClaimedAsFreedRAM() async throws {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: fixtureMemoryReport(processes: [MemoryProcess(id: 11, name: "Main", residentBytes: 12_345)]))
        model.toggleSelection(id: 11)
        let review = try #require(model.review())
        #expect(review.residentBytes == 12_345)
        await model.apply(review: review)
        #expect(state.requests.map(\.pid) == [11])
        #expect(model.results.first?.status == .pending)
        #expect(model.statusMessage?.contains("no savings are assumed") == true)
        #expect(model.selection.isEmpty)
        await model.apply(review: review)
        #expect(state.requests.count == 1)
    }

    @Test("A refused request stays refused and a normally closed app is only marked closed")
    func requestOutcomesRemainAccurate() async throws {
        let refused = QuitFixtureState([fixtureApp(pid: 11)])
        refused.outcome = .refused
        let refusedModel = refused.model()
        refusedModel.refresh(from: nil)
        refusedModel.toggleSelection(id: 11)
        await refusedModel.apply(review: try #require(refusedModel.review()))
        #expect(refusedModel.results.first?.status == .refused)

        let closed = QuitFixtureState([fixtureApp(pid: 11)])
        closed.removeAfterRequest = true
        let closedModel = closed.model()
        closedModel.refresh(from: nil)
        closedModel.toggleSelection(id: 11)
        await closedModel.apply(review: try #require(closedModel.review()))
        #expect(closedModel.results.first?.status == .closed)
        #expect(closedModel.results.first?.message.contains("fresh scan") == true)
        #expect(closedModel.applications.isEmpty)
    }

    @Test("Unreviewed or changed selections cannot send a quit request")
    func exactReviewIsRequired() async throws {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: nil)
        model.toggleSelection(id: 11)
        let review = try #require(model.review())
        model.clearSelection()
        await model.apply(review: review)
        #expect(state.requests.isEmpty)
        #expect(model.statusMessage?.contains("Review it again") == true)
    }

    @Test("A pending save-dialog request is reconciled on the next memory refresh")
    func delayedQuitIsObservedWithoutAnotherRequest() async throws {
        let state = QuitFixtureState([fixtureApp(pid: 11)])
        let model = state.model()
        model.refresh(from: nil)
        model.toggleSelection(id: 11)
        await model.apply(review: try #require(model.review()))
        #expect(model.results.first?.status == .pending)
        state.running = []
        model.refresh(from: nil)
        #expect(model.results.first?.status == .closed)
        #expect(state.requests.count == 1)
    }
}

@MainActor
private final class QuitFixtureState {
    var running: [MemoryRunningApplication]
    var requests: [MemoryApplicationIdentity] = []
    var outcome = MemoryQuitRequestOutcome.accepted
    var removeAfterRequest = false
    init(_ running: [MemoryRunningApplication]) { self.running = running }

    func model() -> MemoryActionsModel {
        MemoryActionsModel(applicationProvider: { self.running }, quitRequester: { identity in
            self.requests.append(identity)
            if self.removeAfterRequest { self.running.removeAll { $0.pid == identity.pid } }
            return self.outcome
        }, currentPID: 99)
    }
}

@MainActor
private func fixtureApp(pid: Int32, identifier: String = "example.userapp", name: String = "User App",
                        path: String = "/Applications/User App.app", launchDate: Date? = Date(timeIntervalSince1970: 100),
                        inode: UInt64 = 11, regular: Bool = true, terminated: Bool = false) -> MemoryRunningApplication {
    MemoryRunningApplication(pid: pid, name: name, bundleIdentifier: identifier,
        bundleURL: URL(fileURLWithPath: path, isDirectory: true), launchDate: launchDate,
        bundleIdentity: MemoryBundleIdentity(device: 1, inode: inode, modifiedSeconds: 1, modifiedNanoseconds: 0,
            changedSeconds: 1, changedNanoseconds: 0), isRegular: regular, isTerminated: terminated, icon: nil)
}

@MainActor
private func fixtureMemoryReport(processes: [MemoryProcess]) -> MemoryReport {
    MemoryReport(id: UUID(), scannedAt: Date(timeIntervalSince1970: 100), totalBytes: 16_000_000,
        usedBytes: 8_000_000, availableBytes: 8_000_000, compressedBytes: 1_000_000, swapUsedBytes: 0,
        pressure: .normal, processes: processes, recommendations: [], issues: [])
}

#endif
