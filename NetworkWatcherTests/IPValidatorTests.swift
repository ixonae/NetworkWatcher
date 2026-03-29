import XCTest

final class IPValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func entries(_ ranges: [String]) -> [AllowedIPEntry] {
        ranges.map { AllowedIPEntry(range: $0) }
    }

    private func vpnEntry(_ range: String) -> AllowedIPEntry {
        AllowedIPEntry(range: range, isVPN: true)
    }

    // MARK: - ipToUInt32

    func testIPToUInt32ValidIP() {
        XCTAssertEqual(IPValidator.ipToUInt32(TestIP.zero), 0)
        XCTAssertEqual(IPValidator.ipToUInt32(TestIP.broadcast), 0xFFFFFFFF)
        XCTAssertEqual(IPValidator.ipToUInt32(TestIP.private192), (192 << 24) | (168 << 16) | (1 << 8) | 1)
        XCTAssertEqual(IPValidator.ipToUInt32(TestIP.private10), (10 << 24) | 1)
    }

    func testIPToUInt32Invalid() {
        XCTAssertNil(IPValidator.ipToUInt32(""))
        XCTAssertNil(IPValidator.ipToUInt32("1.2.3"))
        XCTAssertNil(IPValidator.ipToUInt32("1.2.3.4.5"))
        XCTAssertNil(IPValidator.ipToUInt32("abc.def.ghi.jkl"))
        XCTAssertNil(IPValidator.ipToUInt32(TestIP.overflow))
        XCTAssertNil(IPValidator.ipToUInt32(TestIP.negative))
    }

    func testIPToUInt32Trimming() {
        XCTAssertEqual(IPValidator.ipToUInt32("  \(TestIP.private10)  "), IPValidator.ipToUInt32(TestIP.private10))
    }

    // MARK: - matchesCIDR

    func testMatchesCIDRSingleHost() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.private10, cidr: TestIP.cidrHostSingle))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.private10_2, cidr: TestIP.cidrHostSingle))
    }

    func testMatchesCIDRSlash24() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.private192_100, cidr: TestIP.cidr192_24))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.private192_0, cidr: TestIP.cidr192_24))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.private192_255, cidr: TestIP.cidr192_24))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.private192_2, cidr: TestIP.cidr192_24))
    }

    func testMatchesCIDRSlash16() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.private172, cidr: TestIP.cidr172_16))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.private172Alt, cidr: TestIP.cidr172_16))
    }

    func testMatchesCIDRSlash0() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.stub, cidr: TestIP.cidrAll))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: TestIP.broadcast, cidr: TestIP.cidrAll))
    }

    func testMatchesCIDRInvalidCIDR() {
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.stub, cidr: "invalid"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.stub, cidr: "\(TestIP.stub)/33"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: TestIP.stub, cidr: "\(TestIP.stub)/-1"))
    }

    // MARK: - validate (matched)

    func testValidateExactMatch() {
        let result = IPValidator.validate(ip: TestIP.stub, against: entries([TestIP.stub]))
        XCTAssertTrue(result.matched)
        XCTAssertFalse(result.isVPN)
    }

    func testValidateExactNoMatch() {
        let result = IPValidator.validate(ip: TestIP.stubAlt, against: entries([TestIP.stub]))
        XCTAssertFalse(result.matched)
    }

    func testValidateCidrMatch() {
        let result = IPValidator.validate(ip: TestIP.private10_50, against: entries([TestIP.cidr10_24]))
        XCTAssertTrue(result.matched)
    }

    func testValidateCidrNoMatch() {
        let result = IPValidator.validate(ip: TestIP.private10Alt, against: entries([TestIP.cidr10_24]))
        XCTAssertFalse(result.matched)
    }

    func testValidateWildcard() {
        let result1 = IPValidator.validate(ip: TestIP.stub, against: entries(["*"]))
        XCTAssertTrue(result1.matched)

        let result2 = IPValidator.validate(ip: TestIP.broadcast, against: entries(["*"]))
        XCTAssertTrue(result2.matched)
    }

    func testValidateMultipleRanges() {
        let rangeEntries = entries([TestIP.cidr10_24, TestIP.cidr192_24, TestIP.dns])

        XCTAssertTrue(IPValidator.validate(ip: TestIP.private10_5, against: rangeEntries).matched)
        XCTAssertTrue(IPValidator.validate(ip: TestIP.private192_100, against: rangeEntries).matched)
        XCTAssertTrue(IPValidator.validate(ip: TestIP.dns, against: rangeEntries).matched)
        XCTAssertFalse(IPValidator.validate(ip: TestIP.private172_16, against: rangeEntries).matched)
    }

    func testValidateEmptyRanges() {
        let result = IPValidator.validate(ip: TestIP.stub, against: [])
        XCTAssertFalse(result.matched)
    }

    func testValidateWhitespaceTrimming() {
        let result1 = IPValidator.validate(ip: TestIP.stub, against: [AllowedIPEntry(range: "  \(TestIP.stub)  ")])
        XCTAssertTrue(result1.matched)

        let result2 = IPValidator.validate(ip: TestIP.stub, against: [AllowedIPEntry(range: " * ")])
        XCTAssertTrue(result2.matched)
    }

    // MARK: - validate (VPN flag)

    func testValidateVPNFlagReturned() {
        let result = IPValidator.validate(ip: TestIP.stub, against: [vpnEntry(TestIP.stub)])
        XCTAssertTrue(result.matched)
        XCTAssertTrue(result.isVPN)
    }

    func testValidateNonVPNFlagReturned() {
        let result = IPValidator.validate(ip: TestIP.stub, against: entries([TestIP.stub]))
        XCTAssertTrue(result.matched)
        XCTAssertFalse(result.isVPN)
    }

    func testValidateVPNFlagFromMatchingEntry() {
        let mixed = [
            AllowedIPEntry(range: TestIP.cidr10_24, isVPN: false),
            AllowedIPEntry(range: TestIP.cidr192_24, isVPN: true),
        ]
        // Should match the second entry (VPN)
        let result = IPValidator.validate(ip: TestIP.private192_100, against: mixed)
        XCTAssertTrue(result.matched)
        XCTAssertTrue(result.isVPN)

        // Should match the first entry (non-VPN)
        let result2 = IPValidator.validate(ip: TestIP.private10_50, against: mixed)
        XCTAssertTrue(result2.matched)
        XCTAssertFalse(result2.isVPN)
    }

    func testValidateVPNWildcard() {
        let result = IPValidator.validate(ip: TestIP.stub, against: [vpnEntry("*")])
        XCTAssertTrue(result.matched)
        XCTAssertTrue(result.isVPN)
    }

    func testValidateVPNCIDR() {
        let result = IPValidator.validate(ip: TestIP.private10_50, against: [vpnEntry(TestIP.cidr10_24)])
        XCTAssertTrue(result.matched)
        XCTAssertTrue(result.isVPN)
    }

    func testValidateNoMatchReturnsFalseVPN() {
        let result = IPValidator.validate(ip: TestIP.stub, against: [vpnEntry(TestIP.secondary)])
        XCTAssertFalse(result.matched)
        XCTAssertFalse(result.isVPN)
    }

    // MARK: - isValidIPOrCIDR

    func testIsValidIPOrCIDRValidIP() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.stub))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.zero))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.broadcast))
    }

    func testIsValidIPOrCIDRValidCIDR() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.cidr10_24))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.cidrAll))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR(TestIP.cidrHost))
    }

    func testIsValidIPOrCIDRWildcard() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("*"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("  *  "))
    }

    func testIsValidIPOrCIDRInvalid() {
        XCTAssertFalse(IPValidator.isValidIPOrCIDR(""))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("abc"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("1.2.3"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("\(TestIP.stub)/33"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("\(TestIP.stub)/-1"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR(TestIP.overflow2))
    }
}
