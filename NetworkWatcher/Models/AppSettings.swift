import Foundation

enum AlertStyle: String, Codable, CaseIterable {
    case notification
    case popup

    var label: String {
        switch self {
        case .notification: return "Notification"
        case .popup: return "Popup window"
        }
    }

    /// The style actually used: notifications fall back to popups until they are allowed,
    /// so an alert is never silently dropped.
    static func effective(preferred: AlertStyle, notificationsAllowed: Bool) -> AlertStyle {
        preferred == .notification && !notificationsAllowed ? .popup : preferred
    }
}

struct AppSettings: Codable {
    /// Allowed check intervals, in seconds.
    static let checkIntervalRange = 5...3600

    var checkIntervalSeconds: Int = 60
    var showIPInMenuBar: Bool = false
    var allowUnconfiguredNetworks: Bool = false
    var muteAlerts: Bool = false
    var ipLookupURL: String = "https://api.ipify.org?format=text"
    var alertStyle: AlertStyle = .notification

    /// IPv4-only endpoints: dual-stack services return an IPv6 address when one is available,
    /// which would not match the IPv4 rules most networks are configured with.
    static let predefinedURLs: [(name: String, url: String)] = [
        ("ipify (IPv4)", "https://api.ipify.org?format=text"),
        ("icanhazip (IPv4)", "https://ipv4.icanhazip.com"),
        ("ident.me (IPv4)", "https://4.ident.me"),
    ]

    /// Former dual-stack presets, mapped to their IPv4-only replacements.
    static let legacyPresetURLs: [String: String] = [
        "https://icanhazip.com": "https://ipv4.icanhazip.com",
        "https://ifconfig.me/ip": "https://4.ident.me",
    ]

    enum CodingKeys: String, CodingKey {
        // Old data may also contain "launchAtLogin"; it is ignored (SMAppService is the source of truth).
        case checkIntervalSeconds, showIPInMenuBar
        case allowUnconfiguredNetworks, muteAlerts, ipLookupURL, alertStyle
    }

    init() {}

    static func isValidInterval(_ seconds: Int) -> Bool {
        checkIntervalRange.contains(seconds)
    }

    static func clampedInterval(_ seconds: Int) -> Int {
        min(max(seconds, checkIntervalRange.lowerBound), checkIntervalRange.upperBound)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkIntervalSeconds = Self.clampedInterval(try container.decodeIfPresent(Int.self, forKey: .checkIntervalSeconds) ?? 60)
        showIPInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showIPInMenuBar) ?? false
        allowUnconfiguredNetworks = try container.decodeIfPresent(Bool.self, forKey: .allowUnconfiguredNetworks) ?? false
        muteAlerts = try container.decodeIfPresent(Bool.self, forKey: .muteAlerts) ?? false
        let storedURL = try container.decodeIfPresent(String.self, forKey: .ipLookupURL) ?? "https://api.ipify.org?format=text"
        ipLookupURL = Self.legacyPresetURLs[storedURL] ?? storedURL
        // Decoded leniently so an unknown value from a newer version falls back to the default.
        let storedStyle = try container.decodeIfPresent(String.self, forKey: .alertStyle)
        alertStyle = storedStyle.flatMap(AlertStyle.init(rawValue:)) ?? .notification
    }
}

/// What a settings update requires from the running checks.
struct SettingsChange: Equatable {
    /// The check interval changed (or this is the first update), so the timer must be rescheduled.
    var restartTimer: Bool
    /// The lookup service changed, so a fresh lookup is needed.
    var recheck: Bool
    /// A rule-affecting option changed, so the last IP should be re-evaluated.
    var reevaluate: Bool
    /// Notifications were just chosen (or are in use at launch), so ask for permission.
    var requestNotificationPermission = false

    static func between(_ old: AppSettings?, _ new: AppSettings) -> SettingsChange {
        let wantsNotifications = new.alertStyle == .notification
        guard let old else {
            return SettingsChange(
                restartTimer: true, recheck: false, reevaluate: false,
                requestNotificationPermission: wantsNotifications
            )
        }
        return SettingsChange(
            restartTimer: old.checkIntervalSeconds != new.checkIntervalSeconds,
            recheck: old.ipLookupURL != new.ipLookupURL,
            reevaluate: old.allowUnconfiguredNetworks != new.allowUnconfiguredNetworks,
            requestNotificationPermission: wantsNotifications && old.alertStyle != new.alertStyle
        )
    }
}
