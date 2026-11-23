#if !ROOM_APP_STORE
import Foundation
import Observation
import UserNotifications

/// Schedules a read-only measurement while Room is open. Opening the notification only navigates.
@Observable @MainActor
final class RoomWeeklyCheckScheduler {
    static let shared = RoomWeeklyCheckScheduler()
    static let enabledKey = "RoomWeeklyCheckEnabled"
    static let thresholdKey = "RoomWeeklyThresholdGB"

    private(set) var enabled: Bool
    private(set) var permissionDenied = false
    private(set) var permissionPending = false
    var thresholdGB: Int {
        didSet {
            defaults.set(thresholdGB, forKey: Self.thresholdKey)
        }
    }

    private let defaults: UserDefaults
    private let writer: RoomStateWriter
    @ObservationIgnored private let requestPermission: () async -> Bool
    @ObservationIgnored private var source: () async -> RoomWeeklyCheckRecord? = { nil }
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var didConfigure = false
    @ObservationIgnored private let routing = RoomWeeklyNotificationRouter()

    init(defaults: UserDefaults = .standard, writer: RoomStateWriter = .shared,
         requestPermission: @escaping () async -> Bool = {
             (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
         }) {
        self.defaults = defaults
        self.writer = writer
        self.requestPermission = requestPermission
        enabled = defaults.bool(forKey: Self.enabledKey)
        let stored = defaults.object(forKey: Self.thresholdKey) as? Int
            ?? Int(RoomWeeklyCheck.defaultThresholdBytes / 1_000_000_000)
        thresholdGB = min(max(stored, RoomWeeklyCheck.thresholdRangeGB.lowerBound), RoomWeeklyCheck.thresholdRangeGB.upperBound)
    }

    func configure(source: @escaping () async -> RoomWeeklyCheckRecord?, openCaches: @escaping () -> Void) {
        self.source = source
        routing.openCaches = openCaches
        guard !didConfigure else { return }
        didConfigure = true
        guard enabled else { return }
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard let self, self.enabled else { return }
            let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            self.applyPermission(granted)
        }
    }

    func setEnabled(_ value: Bool) {
        authorizationTask?.cancel()
        if !value {
            enabled = false
            permissionPending = false
            permissionDenied = false
            defaults.set(false, forKey: Self.enabledKey)
            stop()
            return
        }

        permissionPending = true
        permissionDenied = false
        authorizationTask = Task { [weak self] in
            guard let self else { return }
            let granted = await requestPermission()
            guard !Task.isCancelled else { return }
            self.permissionPending = false
            self.applyPermission(granted)
        }
    }

    func waitForAuthorization() async { await authorizationTask?.value }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
    }

    private func applyPermission(_ granted: Bool) {
        enabled = granted
        permissionDenied = !granted
        defaults.set(granted, forKey: Self.enabledKey)
        if granted {
            UNUserNotificationCenter.current().delegate = routing
            schedule()
        } else {
            stop()
        }
    }

    private func schedule() {
        guard scheduler == nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.merkost.room.weekly-caches")
        scheduler.interval = 7 * 86_400
        scheduler.tolerance = 86_400
        scheduler.qualityOfService = .utility
        scheduler.repeats = true
        self.scheduler = scheduler
        scheduler.schedule { [weak self] complete in
            Task { @MainActor in
                await self?.run()
                complete(.finished)
            }
        }
    }

    /// With Hide on the notification says that caches grew, never by how much.
    static func title(growth: Int64, hideSizes: Bool) -> String {
        if hideSizes {
            return String(localized: "weekly.title.hidden", defaultValue: "Caches grew this week.", bundle: RoomCopy.bundle)
        }
        let template = String(localized: "weekly.title", defaultValue: "Caches grew %@ this week.", bundle: RoomCopy.bundle)
        return String.localizedStringWithFormat(template, RoomFormat.overviewBytes(growth))
    }

    private func run() async {
        guard enabled, !running else { return }
        running = true
        defer { running = false }
        guard let current = await source(), enabled, !current.partial else { return }
        let previous = await writer.store.load(RoomWeeklyCheckRecord.self, from: .weeklyCheck)
        guard enabled, !previous.isReadOnly else { return }
        writer.submit(current, to: .weeklyCheck)
        guard let growth = RoomWeeklyCheck.growthToReport(previous: previous.value, current: current,
                                    thresholdBytes: Int64(thresholdGB) * 1_000_000_000) else { return }
        let content = UNMutableNotificationContent()
        content.title = Self.title(growth: growth, hideSizes: defaults.bool(forKey: RoomHideControl.preferenceKey))
        content.body = String(localized: "weekly.body", defaultValue: "Review in Room.", bundle: RoomCopy.bundle)
        let request = UNNotificationRequest(identifier: RoomWeeklyNotificationRouter.identifier, content: content, trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request) }
        catch {
            RoomStateStore.logger.error("Could not post weekly check: \(error.localizedDescription, privacy: .private)")
        }
    }
}

@MainActor private final class RoomWeeklyNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let identifier = "room.weekly-caches"
    var openCaches: () -> Void = {}

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                               didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.identifier,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { openCaches() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                               willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
#endif
