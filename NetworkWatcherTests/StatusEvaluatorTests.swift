import XCTest

final class StatusEvaluatorTests: XCTestCase {

    private let home = NetworkEntry(
        networkIdentifier: "HomeWiFi",
        allowedIPRanges: [AllowedIPEntry(range: TestIP.cidr192_24)]
    )
    private let office = NetworkEntry(
        networkIdentifier: "OfficeWiFi",
        allowedIPRanges: [AllowedIPEntry(range: TestIP.cidr10_24, isVPN: true)]
    )

    private func evaluator(
        networks: [NetworkEntry]? = nil,
        allowUnconfigured: Bool = false,
        muted: Bool = false
    ) -> StatusEvaluator {
        StatusEvaluator(
            networks: networks ?? [home, office],
            allowUnconfiguredNetworks: allowUnconfigured,
            muteAlerts: muted
        )
    }

    private let acknowledgedHome = AlertState(mismatchAcknowledged: true, acknowledgedNetwork: "HomeWiFi")

    // MARK: - Matching

    func testMatchingIPReturnsMatchWithoutAlert() {
        let result = evaluator().evaluate(ip: TestIP.private192_100, activeIdentifiers: ["HomeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .match)
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.alertState, AlertState())
    }

    func testMatchingVPNRangeReturnsMatchVPN() {
        let result = evaluator().evaluate(ip: TestIP.private10_5, activeIdentifiers: ["OfficeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .matchVPN)
        XCTAssertNil(result.alert)
    }

    // MARK: - Mismatch

    func testFirstMismatchAlertsAndAcknowledges() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: ["HomeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .mismatch)
        XCTAssertEqual(result.alert, .mismatch(ip: TestIP.dns, networkName: "HomeWiFi"))
        XCTAssertEqual(result.alertState, acknowledgedHome)
    }

    func testRepeatedMismatchOnSameNetworkDoesNotRealert() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: ["HomeWiFi"], alertState: acknowledgedHome)
        XCTAssertEqual(result.status, .mismatch)
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.alertState, acknowledgedHome)
    }

    func testMismatchOnAnotherNetworkRealerts() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: ["OfficeWiFi"], alertState: acknowledgedHome)
        XCTAssertEqual(result.alert, .mismatch(ip: TestIP.dns, networkName: "OfficeWiFi"))
        XCTAssertEqual(result.alertState.acknowledgedNetwork, "OfficeWiFi")
    }

    func testMutedMismatchAcknowledgesWithoutAlert() {
        let result = evaluator(muted: true).evaluate(ip: TestIP.dns, activeIdentifiers: ["HomeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .mismatch)
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.alertState, acknowledgedHome)
    }

    // MARK: - Restore

    func testMatchAfterMismatchShowsRestored() {
        let result = evaluator().evaluate(ip: TestIP.private192_100, activeIdentifiers: ["HomeWiFi"], alertState: acknowledgedHome)
        XCTAssertEqual(result.status, .match)
        XCTAssertEqual(result.alert, .restored(ip: TestIP.private192_100, networkName: "HomeWiFi"))
        XCTAssertFalse(result.alertState.mismatchAcknowledged)
    }

    func testMutedRestoreClearsStateWithoutAlert() {
        let result = evaluator(muted: true).evaluate(ip: TestIP.private192_100, activeIdentifiers: ["HomeWiFi"], alertState: acknowledgedHome)
        XCTAssertNil(result.alert)
        XCTAssertFalse(result.alertState.mismatchAcknowledged)
    }

    // MARK: - Unconfigured networks

    func testUnconfiguredNetworkAlertsWhenNotAllowed() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: ["CafeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .mismatch)
        XCTAssertEqual(result.alert, .unconfigured(ip: TestIP.dns, networkName: "CafeWiFi"))
        XCTAssertEqual(result.alertState.acknowledgedNetwork, "CafeWiFi")
    }

    func testUnconfiguredNetworkMatchesWhenAllowed() {
        let result = evaluator(allowUnconfigured: true).evaluate(ip: TestIP.dns, activeIdentifiers: ["CafeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.status, .match)
        XCTAssertNil(result.alert)
    }

    func testAllowedUnconfiguredAfterMismatchShowsRestored() {
        let state = AlertState(mismatchAcknowledged: true, acknowledgedNetwork: "CafeWiFi")
        let result = evaluator(allowUnconfigured: true).evaluate(ip: TestIP.dns, activeIdentifiers: ["CafeWiFi"], alertState: state)
        XCTAssertEqual(result.alert, .restored(ip: TestIP.dns, networkName: "CafeWiFi"))
    }

    func testNetworkWithEmptyRangesCountsAsUnconfigured() {
        let empty = NetworkEntry(networkIdentifier: "EmptyWiFi")
        let result = evaluator(networks: [empty]).evaluate(ip: TestIP.dns, activeIdentifiers: ["EmptyWiFi"], alertState: AlertState())
        XCTAssertEqual(result.alert, .unconfigured(ip: TestIP.dns, networkName: "EmptyWiFi"))
    }

    func testNoActiveIdentifiersUsesUnknownName() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: AlertState())
        XCTAssertEqual(result.alert, .unconfigured(ip: TestIP.dns, networkName: "Unknown"))
    }

    // MARK: - Network lookup

    func testNetworkForActiveIdentifiersReturnsFirstConfigured() {
        let result = NetworkManager.network(forActiveIdentifiers: ["CafeWiFi", "OfficeWiFi"], in: [home, office])
        XCTAssertEqual(result?.networkIdentifier, "OfficeWiFi")
    }

    func testNetworkForActiveIdentifiersReturnsNilWhenNothingMatches() {
        XCTAssertNil(NetworkManager.network(forActiveIdentifiers: ["CafeWiFi"], in: [home]))
        XCTAssertNil(NetworkManager.network(forActiveIdentifiers: [], in: [home]))
    }

    // MARK: - Exact matches beat the catch-all

    private let catchAll = NetworkEntry(
        networkIdentifier: "*",
        allowedIPRanges: [AllowedIPEntry(range: TestIP.cidr172_16)]
    )
    private let ethernet = NetworkEntry(
        networkIdentifier: "Ethernet",
        allowedIPRanges: [AllowedIPEntry(range: TestIP.cidr10_8)]
    )

    func testExactMatchOnLaterIdentifierBeatsCatchAll() {
        let result = NetworkManager.network(forActiveIdentifiers: ["CafeWiFi", "Ethernet"], in: [catchAll, ethernet])
        XCTAssertEqual(result?.networkIdentifier, "Ethernet")
    }

    func testExactMatchBeatsCatchAllRegardlessOfListOrder() {
        let before = NetworkManager.network(forActiveIdentifiers: ["Ethernet"], in: [catchAll, ethernet])
        let after = NetworkManager.network(forActiveIdentifiers: ["Ethernet"], in: [ethernet, catchAll])
        XCTAssertEqual(before?.networkIdentifier, "Ethernet")
        XCTAssertEqual(after?.networkIdentifier, "Ethernet")
    }

    func testEarlierExactMatchWins() {
        let result = NetworkManager.network(forActiveIdentifiers: ["HomeWiFi", "Ethernet"], in: [ethernet, home])
        XCTAssertEqual(result?.networkIdentifier, "HomeWiFi")
    }

    func testCatchAllUsedWhenNoExactMatch() {
        let result = NetworkManager.network(forActiveIdentifiers: ["CafeWiFi"], in: [home, catchAll])
        XCTAssertEqual(result?.networkIdentifier, "*")
    }

    func testCatchAllAppliesWithNoActiveIdentifiers() {
        XCTAssertEqual(NetworkManager.network(forActiveIdentifiers: [], in: [catchAll])?.networkIdentifier, "*")
    }

    func testUnconfiguredWiFiWithConfiguredEthernetUsesEthernetRules() {
        let result = evaluator(networks: [catchAll, ethernet])
            .evaluate(ip: TestIP.private10, activeIdentifiers: ["CafeWiFi", "Ethernet"], alertState: AlertState())
        XCTAssertEqual(result.status, .match)
    }

    func testCatchAllMismatchIsReportedUnderActiveNetworkName() {
        let result = evaluator(networks: [catchAll])
            .evaluate(ip: TestIP.dns, activeIdentifiers: ["CafeWiFi"], alertState: AlertState())
        XCTAssertEqual(result.alert, .mismatch(ip: TestIP.dns, networkName: "CafeWiFi"))
        XCTAssertEqual(result.alertState.acknowledgedNetwork, "CafeWiFi")
    }

    func testExactMatchIsReportedUnderConfiguredName() {
        let result = evaluator()
            .evaluate(ip: TestIP.dns, activeIdentifiers: ["homewifi"], alertState: AlertState())
        XCTAssertEqual(result.alert, .mismatch(ip: TestIP.dns, networkName: "HomeWiFi"))
    }

    // MARK: - Location permission

    func testBlockedSSIDWithNoMatchAsksForPermission() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: AlertState(), ssidBlockedByPermission: true)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.alert, .locationPermissionNeeded)
        XCTAssertTrue(result.alertState.locationAlertShown)
        XCTAssertFalse(result.alertState.mismatchAcknowledged)
    }

    func testPermissionAlertIsShownOnce() {
        let state = AlertState(locationAlertShown: true)
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: state, ssidBlockedByPermission: true)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertNil(result.alert)
    }

    func testMutedPermissionAlertIsSuppressedButRecorded() {
        let result = evaluator(muted: true).evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: AlertState(), ssidBlockedByPermission: true)
        XCTAssertNil(result.alert)
        XCTAssertTrue(result.alertState.locationAlertShown)
    }

    func testBlockedSSIDWithExactWiredMatchEvaluatesNormally() {
        let result = evaluator(networks: [home, ethernet])
            .evaluate(ip: TestIP.private10, activeIdentifiers: ["Ethernet"], alertState: AlertState(), ssidBlockedByPermission: true)
        XCTAssertEqual(result.status, .match)
        XCTAssertNil(result.alert)
    }

    func testBlockedSSIDWithCatchAllAndWiFiRulesAsksForPermission() {
        let result = evaluator(networks: [home, catchAll])
            .evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: AlertState(), ssidBlockedByPermission: true)
        XCTAssertEqual(result.alert, .locationPermissionNeeded)
    }

    func testBlockedSSIDWithOnlyCatchAllEvaluatesNormally() {
        let result = evaluator(networks: [catchAll, ethernet])
            .evaluate(ip: TestIP.private172, activeIdentifiers: [], alertState: AlertState(), ssidBlockedByPermission: true)
        XCTAssertEqual(result.status, .match)
    }

    func testPermissionStateResetsOnceSSIDIsReadable() {
        let state = AlertState(locationAlertShown: true)
        let result = evaluator().evaluate(ip: TestIP.private192_100, activeIdentifiers: ["HomeWiFi"], alertState: state)
        XCTAssertEqual(result.status, .match)
        XCTAssertFalse(result.alertState.locationAlertShown)
    }

    func testPermissionCheckKeepsExistingMismatchState() {
        let result = evaluator().evaluate(ip: TestIP.dns, activeIdentifiers: [], alertState: acknowledgedHome, ssidBlockedByPermission: true)
        XCTAssertEqual(result.alertState.acknowledgedNetwork, "HomeWiFi")
        XCTAssertTrue(result.alertState.mismatchAcknowledged)
    }

    // MARK: - NetworkEntry kinds

    func testNetworkEntryKinds() {
        XCTAssertTrue(home.isWiFiNetwork)
        XCTAssertFalse(catchAll.isWiFiNetwork)
        XCTAssertTrue(catchAll.isCatchAll)
        for wired in ["Ethernet", "USB", "Thunderbolt"] {
            XCTAssertFalse(NetworkEntry(networkIdentifier: wired).isWiFiNetwork, wired)
        }
    }
}
