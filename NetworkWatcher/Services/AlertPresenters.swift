import Cocoa
import UserNotifications

protocol AlertPresenter {
    func present(_ content: AlertContent)
}

/// Shows a modal NSAlert. Blocks until dismissed, so it is opt-in.
struct ModalAlertPresenter: AlertPresenter {
    func present(_ content: AlertContent) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = content.title
        alert.informativeText = [content.body, content.detail].compactMap { $0 }.joined(separator: "\n\n")
        switch content.severity {
        case .critical: alert.alertStyle = .critical
        case .warning: alert.alertStyle = .warning
        case .informational: alert.alertStyle = .informational
        }
        if content.opensLocationSettings {
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(NetworkMonitor.locationSettingsURL)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

/// Delivers alerts through Notification Center.
final class NotificationAlertPresenter: NSObject, AlertPresenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Removes delivered notifications that a newer alert has made obsolete.
    func withdraw(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func present(_ content: AlertContent) {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = content.playsSound ? .default : nil
        notification.interruptionLevel = content.severity == .critical ? .timeSensitive : .active
        notification.userInfo = ["opensLocationSettings": content.opensLocationSettings]

        let request = UNNotificationRequest(identifier: content.identifier, content: notification, trigger: nil)
        center.add(request) { error in
            if let error {
                Log.alerts.error("Failed to deliver notification \(content.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let opensLocation = response.notification.request.content.userInfo["opensLocationSettings"] as? Bool ?? false
        await MainActor.run {
            if opensLocation {
                NSWorkspace.shared.open(NetworkMonitor.locationSettingsURL)
            } else {
                openSettings()
            }
        }
    }
}
