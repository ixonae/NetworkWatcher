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
}
