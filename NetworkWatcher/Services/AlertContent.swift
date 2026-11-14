import Foundation

/// Text and presentation details for a status alert, shared by the popup and notification presenters.
struct AlertContent: Equatable {
    enum Severity: Equatable {
        case critical
        case warning
        case informational
    }

    /// Stable per alert kind, so a repeat replaces the previous notification instead of stacking.
    let identifier: String
    let title: String
    let body: String
    /// Extra guidance shown in the popup, where there is room for it.
    let detail: String?
    let severity: Severity
    /// The primary action opens Location Services instead of the app's settings.
    let opensLocationSettings: Bool

    var playsSound: Bool { severity != .informational }

    /// Earlier alerts made obsolete by this one (a restore withdraws the mismatch it resolves).
    var supersedes: [String] {
        identifier == Self.restoredID ? [Self.mismatchID, Self.unconfiguredID] : []
    }

    static let mismatchID = "ip-mismatch"
    static let unconfiguredID = "unconfigured-network"
    static let restoredID = "ip-restored"
    static let locationID = "location-permission"

    init(_ alert: StatusAlert) {
        switch alert {
        case let .mismatch(ip, networkName):
            identifier = Self.mismatchID
            title = "IP Address Mismatch"
            body = "Your external IP (\(ip)) does not match the expected range for \"\(networkName)\"."
            detail = "If this is unexpected, check that the allowed IP list for this network is correct in Settings."
            severity = .critical
            opensLocationSettings = false
        case let .unconfigured(ip, networkName):
            identifier = Self.unconfiguredID
            title = "Unconfigured Network"
            body = "\"\(networkName)\" (external IP \(ip)) has no allowed IPs configured."
            detail = "You can add this network and its expected IPs in Settings, or enable \"Allow unconfigured networks\" in General settings to skip this warning."
            severity = .warning
            opensLocationSettings = false
        case let .restored(ip, networkName):
            identifier = Self.restoredID
            title = "IP Address Restored"
            body = "Your external IP (\(ip)) on \"\(networkName)\" now matches the expected range."
            detail = nil
            severity = .informational
            opensLocationSettings = false
        case .locationPermissionNeeded:
            identifier = Self.locationID
            title = "Location Access Needed"
            body = "macOS only reveals the Wi-Fi network name to apps with location access, so Network Watcher can't tell which network you're on."
            detail = "Allow Network Watcher in Privacy & Security > Location Services."
            severity = .warning
            opensLocationSettings = true
        }
    }
}
