import Foundation
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Launch-at-login state, read from the system rather than stored in settings.
struct LaunchAtLogin {
    let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
    }

    /// Registered, including when macOS is still waiting for the user to approve it.
    var isEnabled: Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    /// The item is registered but blocked until approved in System Settings > Login Items.
    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    /// Registers or unregisters the app; returns a user-facing error message on failure.
    func setEnabled(_ enabled: Bool) -> String? {
        guard enabled != isEnabled else { return nil }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return nil
        } catch {
            let action = enabled ? "turn on" : "turn off"
            return "Couldn't \(action) launch at login: \(error.localizedDescription)"
        }
    }
}
