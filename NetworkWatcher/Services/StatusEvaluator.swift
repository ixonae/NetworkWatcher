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
}

enum StatusAlert: Equatable {
    case mismatch(ip: String, networkName: String)
    case unconfigured(ip: String, networkName: String)
    case restored(ip: String, networkName: String)
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

    func evaluate(ip: String, activeIdentifiers: [String], alertState: AlertState) -> StatusEvaluation {
        let matchedNetwork = NetworkManager.network(forActiveIdentifiers: activeIdentifiers, in: networks)
        let networkName = matchedNetwork?.networkIdentifier
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

    private func matched(_ status: IPStatus, ip: String, networkName: String, alertState: AlertState) -> StatusEvaluation {
        var newState = alertState
        newState.mismatchAcknowledged = false
        let alert: StatusAlert? = alertState.mismatchAcknowledged && !muteAlerts
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
        let newState = AlertState(mismatchAcknowledged: true, acknowledgedNetwork: networkName)
        return StatusEvaluation(status: .mismatch, alert: muteAlerts ? nil : alert, alertState: newState)
    }
}
