import Foundation

enum IPStatus: Equatable {
    case match
    case matchVPN
    case mismatch
    case unknown
    case noNetwork
}

/// Tracks whether the user has already been alerted about the current mismatch.
struct AlertState: Equatable {
    var mismatchAcknowledged = false
    /// Network the current mismatch alert was shown for, so moving to another bad network alerts again.
    var acknowledgedNetwork: String?
    /// Whether a mismatch alert was actually presented (not muted), so a restore is only announced
    /// for a mismatch the user was told about.
    var mismatchPresented = false
    /// Whether the user was told that location permission is needed to read the Wi-Fi name.
    var locationAlertShown = false
}

enum StatusAlert: Equatable {
    case mismatch(ip: String, networkName: String)
    case unconfigured(ip: String, networkName: String)
    case restored(ip: String, networkName: String)
    case locationPermissionNeeded
}

struct StatusEvaluation: Equatable {
    var status: IPStatus
    /// Alert to present, or nil when none is due (or alerts are muted).
    var alert: StatusAlert?
    var alertState: AlertState
}

/// Decides the menu bar status and which alert, if any, a fetched IP should produce.
struct StatusEvaluator {
    var networks: [NetworkEntry]
    var allowUnconfiguredNetworks: Bool
    var muteAlerts: Bool

    init(networks: [NetworkEntry], allowUnconfiguredNetworks: Bool, muteAlerts: Bool) {
        self.networks = networks
        self.allowUnconfiguredNetworks = allowUnconfiguredNetworks
        self.muteAlerts = muteAlerts
    }

    init(networks: [NetworkEntry], settings: AppSettings) {
        self.init(
            networks: networks,
            allowUnconfiguredNetworks: settings.allowUnconfiguredNetworks,
            muteAlerts: settings.muteAlerts
        )
    }

    /// - Parameter ssidBlockedByPermission: Wi-Fi is on but macOS hides the SSID because the app
    ///   lacks location permission, so the active identifiers are missing the Wi-Fi network.
    func evaluate(
        ip: String,
        activeIdentifiers: [String],
        alertState: AlertState,
        ssidBlockedByPermission: Bool = false
    ) -> StatusEvaluation {
        let matchedNetwork = NetworkManager.network(forActiveIdentifiers: activeIdentifiers, in: networks)

        var alertState = alertState
        if !ssidBlockedByPermission {
            alertState.locationAlertShown = false
        } else if needsSSID(matchedNetwork) {
            // Without the SSID the result would be a misleading "Unknown" network alert.
            let alert: StatusAlert? = alertState.locationAlertShown || muteAlerts ? nil : .locationPermissionNeeded
            alertState.locationAlertShown = true
            return StatusEvaluation(status: .unknown, alert: alert, alertState: alertState)
        }

        // A catch-all match is reported under the real network name, not "*".
        let networkName = matchedNetwork.flatMap { $0.isCatchAll ? nil : $0.networkIdentifier }
            ?? activeIdentifiers.first
            ?? "Unknown"

        guard let network = matchedNetwork, !network.allowedIPRanges.isEmpty else {
            if allowUnconfiguredNetworks {
                return matched(.match, ip: ip, networkName: networkName, alertState: alertState)
            }
            return mismatched(.unconfigured(ip: ip, networkName: networkName), networkName: networkName, alertState: alertState)
        }

        let result = IPValidator.validate(ip: ip, against: network.allowedIPRanges)
        if result.matched {
            return matched(result.isVPN ? .matchVPN : .match, ip: ip, networkName: networkName, alertState: alertState)
        }
        return mismatched(.mismatch(ip: ip, networkName: networkName), networkName: networkName, alertState: alertState)
    }

    /// Whether the missing SSID could change the outcome. A Wi-Fi rule takes priority over wired and
    /// catch-all ones, so unless the match is itself a Wi-Fi rule, any configured Wi-Fi rule might apply.
    private func needsSSID(_ matchedNetwork: NetworkEntry?) -> Bool {
        guard let matchedNetwork else { return true }
        return !matchedNetwork.isWiFiNetwork && networks.contains(where: \.isWiFiNetwork)
    }

    private func matched(_ status: IPStatus, ip: String, networkName: String, alertState: AlertState) -> StatusEvaluation {
        var newState = alertState
        newState.mismatchAcknowledged = false
        newState.mismatchPresented = false
        let alert: StatusAlert? = alertState.mismatchPresented && !muteAlerts
            ? .restored(ip: ip, networkName: networkName)
            : nil
        return StatusEvaluation(status: status, alert: alert, alertState: newState)
    }

    private func mismatched(_ alert: StatusAlert, networkName: String, alertState: AlertState) -> StatusEvaluation {
        let alreadyAlerted = alertState.mismatchAcknowledged && alertState.acknowledgedNetwork == networkName
        guard !alreadyAlerted else {
            return StatusEvaluation(status: .mismatch, alert: nil, alertState: alertState)
        }
        // Acknowledged even when muted, so unmuting doesn't replay an old mismatch.
        var newState = alertState
        newState.mismatchAcknowledged = true
        newState.acknowledgedNetwork = networkName
        newState.mismatchPresented = !muteAlerts
        return StatusEvaluation(status: .mismatch, alert: muteAlerts ? nil : alert, alertState: newState)
    }
}
