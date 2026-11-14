import XCTest

final class AlertContentTests: XCTestCase {

    func testMismatchContent() {
        let content = AlertContent(.mismatch(ip: TestIP.dns, networkName: "HomeWiFi"))
        XCTAssertEqual(content.identifier, AlertContent.mismatchID)
        XCTAssertEqual(content.title, "IP Address Mismatch")
        XCTAssertTrue(content.body.contains(TestIP.dns))
        XCTAssertTrue(content.body.contains("HomeWiFi"))
        XCTAssertNotNil(content.detail)
        XCTAssertEqual(content.severity, .critical)
        XCTAssertTrue(content.playsSound)
        XCTAssertFalse(content.opensLocationSettings)
        XCTAssertEqual(content.supersedes, [])
    }

    func testUnconfiguredContent() {
        let content = AlertContent(.unconfigured(ip: TestIP.dns, networkName: "CafeWiFi"))
        XCTAssertEqual(content.identifier, AlertContent.unconfiguredID)
        XCTAssertTrue(content.body.contains("CafeWiFi"))
        XCTAssertTrue(content.body.contains(TestIP.dns))
        XCTAssertEqual(content.severity, .warning)
        XCTAssertTrue(content.playsSound)
    }

    func testRestoredContentIsSilentAndWithdrawsMismatches() {
        let content = AlertContent(.restored(ip: TestIP.stub, networkName: "HomeWiFi"))
        XCTAssertEqual(content.identifier, AlertContent.restoredID)
        XCTAssertTrue(content.body.contains(TestIP.stub))
        XCTAssertEqual(content.severity, .informational)
        XCTAssertFalse(content.playsSound)
        XCTAssertNil(content.detail)
        XCTAssertEqual(Set(content.supersedes), [AlertContent.mismatchID, AlertContent.unconfiguredID])
    }

    func testLocationContentOpensLocationSettings() {
        let content = AlertContent(.locationPermissionNeeded)
        XCTAssertEqual(content.identifier, AlertContent.locationID)
        XCTAssertTrue(content.opensLocationSettings)
        XCTAssertEqual(content.severity, .warning)
        XCTAssertTrue(content.detail?.contains("Location Services") ?? false)
    }

    func testIdentifiersAreStablePerKind() {
        let first = AlertContent(.mismatch(ip: TestIP.dns, networkName: "A"))
        let second = AlertContent(.mismatch(ip: TestIP.stub, networkName: "B"))
        XCTAssertEqual(first.identifier, second.identifier)
    }

    func testIdentifiersAreDistinctAcrossKinds() {
        let ids = [
            AlertContent(.mismatch(ip: TestIP.dns, networkName: "A")).identifier,
            AlertContent(.unconfigured(ip: TestIP.dns, networkName: "A")).identifier,
            AlertContent(.restored(ip: TestIP.dns, networkName: "A")).identifier,
            AlertContent(.locationPermissionNeeded).identifier,
        ]
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
