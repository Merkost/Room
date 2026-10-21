#if !ROOM_APP_STORE
import AppKit
import Darwin
import Foundation
import Observation
import RoomCore

struct MemoryBundleIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

struct MemoryApplicationIdentity: Equatable, Sendable {
    let pid: Int32
    let bundleIdentifier: String
    let bundlePath: String
    let launchDate: Date
    let bundleIdentity: MemoryBundleIdentity
}

/// A value snapshot also used by fixture tests; no test needs a real running app.
struct MemoryRunningApplication {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let launchDate: Date?
    let bundleIdentity: MemoryBundleIdentity?
    let isRegular: Bool
    let isTerminated: Bool
    let icon: NSImage?
}

struct MemoryApplication: Identifiable {
    var id: Int32 { identity.pid }
    let identity: MemoryApplicationIdentity
    let name: String
    let bundleURL: URL
    /// Exact main-process RSS only. Helpers are not guessed or added to this value.
    let residentBytes: Int64?
    let icon: NSImage?
}

struct MemoryQuitReview: Identifiable {
    let id: UUID
    let applications: [MemoryApplication]
    let scannedAt: Date?
    var count: Int { applications.count }
    var residentBytes: Int64 { applications.reduce(0) { $0 + ($1.residentBytes ?? 0) } }
    var unmeasuredCount: Int { applications.filter { $0.residentBytes == nil }.count }
}

enum MemoryQuitStatus: String {
    case accepted, pending, refused, closed, changed
}

struct MemoryQuitResult: Identifiable {
    let id: Int32
    let name: String
    var status: MemoryQuitStatus
    var message: String
}

enum MemoryQuitRequestOutcome {
    case accepted, refused, changed
}

@Observable
@MainActor
final class MemoryActionsModel {
    private(set) var applications: [MemoryApplication] = []
    private(set) var selection: Set<Int32> = []
    private(set) var isApplying = false
    private(set) var results: [MemoryQuitResult] = []
    private(set) var statusMessage: String?

    @ObservationIgnored private let applicationProvider: @MainActor () -> [MemoryRunningApplication]
    @ObservationIgnored private let quitRequester: @MainActor (MemoryApplicationIdentity) -> MemoryQuitRequestOutcome
    @ObservationIgnored private let settle: @MainActor () async -> Void
    @ObservationIgnored private let currentPID: Int32
    @ObservationIgnored private let currentBundleIdentifier: String?
    @ObservationIgnored private var latestReport: MemoryReport?
    @ObservationIgnored private var pendingReviewID: UUID?
    @ObservationIgnored private var requestedIdentities: [Int32: MemoryApplicationIdentity] = [:]

    var selectedCount: Int { selection.count }
    var selectedResidentBytes: Int64 { selectedApplications.reduce(0) { $0 + ($1.residentBytes ?? 0) } }
    var selectedUnmeasuredCount: Int { selectedApplications.filter { $0.residentBytes == nil }.count }
    private var selectedApplications: [MemoryApplication] { applications.filter { selection.contains($0.id) } }

    init() {
        applicationProvider = Self.runningApplications
        quitRequester = Self.requestNormalQuit
        settle = { try? await Task.sleep(for: .milliseconds(700)) }
        currentPID = getpid()
        currentBundleIdentifier = Bundle.main.bundleIdentifier
    }

    init(applicationProvider: @escaping @MainActor () -> [MemoryRunningApplication],
         quitRequester: @escaping @MainActor (MemoryApplicationIdentity) -> MemoryQuitRequestOutcome,
         settle: @escaping @MainActor () async -> Void = { }, currentPID: Int32 = 1,
         currentBundleIdentifier: String? = "local.room.tests") {
        self.applicationProvider = applicationProvider
        self.quitRequester = quitRequester
        self.settle = settle
        self.currentPID = currentPID
        self.currentBundleIdentifier = currentBundleIdentifier
    }

    func refresh(from report: MemoryReport?) {
        guard !isApplying else { return }
        latestReport = report
        let running = applicationProvider()
        reconcileRequests(running)
        let previous = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0.identity) })
        applications = Self.eligibleApplications(running, report: report,
            currentPID: currentPID, currentBundleIdentifier: currentBundleIdentifier)
        let unchanged = Set(applications.filter { previous[$0.id] == $0.identity }.map(\.id))
        let refreshedSelection = selection.intersection(unchanged)
        if refreshedSelection != selection { pendingReviewID = nil }
        selection = refreshedSelection
    }

    func toggleSelection(id: Int32) {
        guard !isApplying, applications.contains(where: { $0.id == id }) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        pendingReviewID = nil
    }

    func clearSelection() {
        guard !isApplying else { return }
        selection = []
        pendingReviewID = nil
    }

    func review() -> MemoryQuitReview? {
        guard !isApplying else { return nil }
        refresh(from: latestReport)
        guard !selectedApplications.isEmpty else {
            statusMessage = "Choose a running app, then review it before requesting a quit."
            return nil
        }
        let review = MemoryQuitReview(id: UUID(), applications: selectedApplications, scannedAt: latestReport?.scannedAt)
        pendingReviewID = review.id
        return review
    }

    func apply(review: MemoryQuitReview) async {
        guard !isApplying, pendingReviewID == review.id,
              Set(review.applications.map(\.id)) == selection else {
            statusMessage = "The selection changed. Review it again before requesting a quit."
            return
        }
        isApplying = true
        pendingReviewID = nil
        results = []
        requestedIdentities = [:]
        defer { isApplying = false }
        for target in review.applications {
            let eligible = Self.eligibleApplications(applicationProvider(), report: latestReport,
                currentPID: currentPID, currentBundleIdentifier: currentBundleIdentifier)
            guard eligible.contains(where: { $0.identity == target.identity }) else {
                results.append(MemoryQuitResult(id: target.id, name: target.name, status: .changed,
                    message: "This app exited, restarted, or changed since review. No quit was requested."))
                continue
            }
            // The production requester revalidates once more without yielding,
            // then calls only NSRunningApplication.terminate().
            switch quitRequester(target.identity) {
            case .accepted:
                requestedIdentities[target.id] = target.identity
                results.append(MemoryQuitResult(id: target.id, name: target.name, status: .accepted,
                    message: "The normal quit request was sent. The app may ask you to save work."))
            case .refused:
                results.append(MemoryQuitResult(id: target.id, name: target.name, status: .refused,
                    message: "The quit request was not accepted. Check the app before trying again."))
            case .changed:
                results.append(MemoryQuitResult(id: target.id, name: target.name, status: .changed,
                    message: "The running app no longer matches the reviewed app. No quit was requested."))
            }
        }
        selection = []
        await settle()
        let running = applicationProvider()
        reconcileRequests(running)
        let requested = results.filter { $0.status == .pending || $0.status == .closed }.count
        statusMessage = requested > 0
            ? "Requested \(requested) \(requested == 1 ? "app" : "apps") to quit normally. RAM is measured separately; no savings are assumed."
            : "No quit request was accepted. Your apps remain under your control."
        applications = Self.eligibleApplications(running, report: latestReport,
            currentPID: currentPID, currentBundleIdentifier: currentBundleIdentifier)
    }

    private func reconcileRequests(_ running: [MemoryRunningApplication]) {
        for index in results.indices where results[index].status == .accepted || results[index].status == .pending {
            guard let identity = requestedIdentities[results[index].id] else { continue }
            if running.contains(where: { Self.identity(of: $0) == identity && !$0.isTerminated }) {
                results[index].status = .pending
                results[index].message = "Quit requested. The app is still open; check it for an unsaved-work dialog."
            } else {
                results[index].status = .closed
                results[index].message = "The reviewed app is no longer running. RAM changes are measured by a fresh scan."
            }
        }
    }

    static func eligibleApplications(_ running: [MemoryRunningApplication], report: MemoryReport?,
                                     currentPID: Int32, currentBundleIdentifier: String?) -> [MemoryApplication] {
        let residentByPID = Dictionary((report?.processes ?? []).map { ($0.id, $0.residentBytes) }, uniquingKeysWith: max)
        var seenPIDs = Set<Int32>(), seenBundles = Set<String>()
        return running.sorted { $0.pid < $1.pid }.compactMap { snapshot in
            guard snapshot.pid > 0, snapshot.pid != currentPID, snapshot.isRegular, !snapshot.isTerminated,
                  let identity = identity(of: snapshot),
                  identity.bundleIdentifier.lowercased() != currentBundleIdentifier?.lowercased(),
                  !isProtected(identity: identity, name: snapshot.name),
                  seenPIDs.insert(snapshot.pid).inserted else { return nil }
            let bundleKey = identity.bundleIdentifier.lowercased() + "|" + identity.bundlePath
            guard seenBundles.insert(bundleKey).inserted, let bundleURL = snapshot.bundleURL else { return nil }
            // A PID in an older sample may have belonged to a previous app launch.
            let resident: Int64?
            if let report, identity.launchDate <= report.scannedAt { resident = residentByPID[snapshot.pid] }
            else { resident = nil }
            return MemoryApplication(identity: identity, name: snapshot.name, bundleURL: bundleURL,
                residentBytes: resident, icon: snapshot.icon)
        }.sorted {
            if ($0.residentBytes ?? -1) != ($1.residentBytes ?? -1) { return ($0.residentBytes ?? -1) > ($1.residentBytes ?? -1) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func identity(of snapshot: MemoryRunningApplication) -> MemoryApplicationIdentity? {
        guard let bundleIdentifier = snapshot.bundleIdentifier, !bundleIdentifier.isEmpty,
              let bundleURL = snapshot.bundleURL, bundleURL.isFileURL,
              bundleURL.pathExtension.lowercased() == "app", bundleURL.path.hasPrefix("/"),
              let launchDate = snapshot.launchDate, launchDate.timeIntervalSince1970.isFinite,
              let bundleIdentity = snapshot.bundleIdentity else { return nil }
        return MemoryApplicationIdentity(pid: snapshot.pid, bundleIdentifier: bundleIdentifier,
            bundlePath: bundleURL.path, launchDate: launchDate, bundleIdentity: bundleIdentity)
    }

    private static func isProtected(identity: MemoryApplicationIdentity, name: String) -> Bool {
        let path = identity.bundlePath
        if ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains(where: path.hasPrefix) { return true }
        if path.contains(".app/Contents/") { return true }
        let bundles: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
            "com.apple.windowserver", "com.apple.windowmanager", "com.apple.controlcenter", "com.apple.notificationcenterui",
            "com.apple.spotlight", "com.apple.securityagent", "com.apple.coreservicesuiagent", "com.apple.launchpad.launcher"]
        let names: Set<String> = ["room", "finder", "dock", "systemuiserver", "loginwindow", "windowserver", "launchd", "kernel_task"]
        return bundles.contains(identity.bundleIdentifier.lowercased()) || names.contains(name.lowercased())
    }

    private static func runningApplications() -> [MemoryRunningApplication] {
        NSWorkspace.shared.runningApplications.map(snapshot)
    }

    private static func snapshot(_ application: NSRunningApplication) -> MemoryRunningApplication {
        let bundleURL = application.bundleURL?.resolvingSymlinksInPath()
        let isRegular = application.activationPolicy == .regular
        return MemoryRunningApplication(pid: application.processIdentifier,
            name: application.localizedName ?? bundleURL?.deletingPathExtension().lastPathComponent ?? "Application",
            bundleIdentifier: application.bundleIdentifier, bundleURL: bundleURL, launchDate: application.launchDate,
            bundleIdentity: bundleURL.flatMap(bundleIdentity), isRegular: isRegular,
            isTerminated: application.isTerminated,
            icon: isRegular ? bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) } : nil)
    }

    private static func bundleIdentity(_ url: URL) -> MemoryBundleIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { return nil }
        return MemoryBundleIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    private static func requestNormalQuit(_ identity: MemoryApplicationIdentity) -> MemoryQuitRequestOutcome {
        guard let application = NSRunningApplication(processIdentifier: identity.pid),
              !application.isTerminated, application.activationPolicy == .regular,
              Self.identity(of: snapshot(application)) == identity,
              identity.pid != getpid(), identity.bundleIdentifier != Bundle.main.bundleIdentifier,
              !isProtected(identity: identity, name: application.localizedName ?? "") else { return .changed }
        return application.terminate() ? .accepted : .refused
    }
}

#else
import Observation
import RoomCore

/// Store edition keeps memory insight read-only. There is no quit implementation.
@Observable @MainActor
final class MemoryActionsModel {
    var selectedCount: Int { 0 }
    var isApplying: Bool { false }
    func refresh(from report: MemoryReport?) { }
}
#endif
