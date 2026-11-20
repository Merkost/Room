import Observation
import ServiceManagement

@MainActor
protocol RoomLoginItem {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct SMAppServiceLoginItem: RoomLoginItem {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@Observable
@MainActor
final class RoomLoginItemModel {
    private(set) var enabled = false
    private(set) var requiresApproval = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let service: any RoomLoginItem

    var approvalHint: String? {
        requiresApproval ? "Allow Room in System Settings › General › Login Items." : nil
    }

    init(service: any RoomLoginItem = SMAppServiceLoginItem()) {
        self.service = service
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refreshStatus()
        } catch {
            // Show what the system says, not what was asked: a failed unregister leaves Room opening at login.
            self.enabled = service.status == .enabled
            requiresApproval = service.status == .requiresApproval
            errorMessage = "Room couldn't change this. Try again in System Settings."
        }
    }

    func refreshStatus() {
        let status = service.status
        enabled = status == .enabled
        requiresApproval = status == .requiresApproval
        errorMessage = nil
    }

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
