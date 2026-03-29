import XCTest
@testable import Network_Watcher

final class IPValidatorTests: XCTestCase {

    // MARK: - ipToUInt32

    func testIPToUInt32_validIP() {
        XCTAssertEqual(IPValidator.ipToUInt32("0.0.0.0"), 0)
        XCTAssertEqual(IPValidator.ipToUInt32("255.255.255.255"), 0xFFFFFFFF)
        XCTAssertEqual(IPValidator.ipToUInt32("192.168.1.1"), (192 << 24) | (168 << 16) | (1 << 8) | 1)
        XCTAssertEqual(IPValidator.ipToUInt32("10.0.0.1"), (10 << 24) | 1)
    }

    func testIPToUInt32_invalid() {
        XCTAssertNil(IPValidator.ipToUInt32(""))
        XCTAssertNil(IPValidator.ipToUInt32("1.2.3"))
        XCTAssertNil(IPValidator.ipToUInt32("1.2.3.4.5"))
        XCTAssertNil(IPValidator.ipToUInt32("abc.def.ghi.jkl"))
        XCTAssertNil(IPValidator.ipToUInt32("256.1.1.1"))
        XCTAssertNil(IPValidator.ipToUInt32("-1.0.0.0"))
    }

    func testIPToUInt32_trimming() {
        XCTAssertEqual(IPValidator.ipToUInt32("  10.0.0.1  "), IPValidator.ipToUInt32("10.0.0.1"))
    }

    // MARK: - matchesCIDR

    func testMatchesCIDR_singleHost() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "10.0.0.1", cidr: "10.0.0.1/32"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "10.0.0.2", cidr: "10.0.0.1/32"))
    }

    func testMatchesCIDR_slash24() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "192.168.1.100", cidr: "192.168.1.0/24"))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "192.168.1.0", cidr: "192.168.1.0/24"))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "192.168.1.255", cidr: "192.168.1.0/24"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "192.168.2.1", cidr: "192.168.1.0/24"))
    }

    func testMatchesCIDR_slash16() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "172.16.5.10", cidr: "172.16.0.0/16"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "172.17.0.1", cidr: "172.16.0.0/16"))
    }

    func testMatchesCIDR_slash0() {
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "1.2.3.4", cidr: "0.0.0.0/0"))
        XCTAssertTrue(IPValidator.matchesCIDR(ip: "255.255.255.255", cidr: "0.0.0.0/0"))
    }

    func testMatchesCIDR_invalidCIDR() {
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "1.2.3.4", cidr: "invalid"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "1.2.3.4", cidr: "1.2.3.4/33"))
        XCTAssertFalse(IPValidator.matchesCIDR(ip: "1.2.3.4", cidr: "1.2.3.4/-1"))
    }

    // MARK: - validate

    func testValidate_exactMatch() {
        XCTAssertTrue(IPValidator.validate(ip: "1.2.3.4", against: ["1.2.3.4"]))
        XCTAssertFalse(IPValidator.validate(ip: "1.2.3.5", against: ["1.2.3.4"]))
    }

    func testValidate_cidrMatch() {
        XCTAssertTrue(IPValidator.validate(ip: "10.0.0.50", against: ["10.0.0.0/24"]))
        XCTAssertFalse(IPValidator.validate(ip: "10.0.1.50", against: ["10.0.0.0/24"]))
    }

    func testValidate_wildcard() {
        XCTAssertTrue(IPValidator.validate(ip: "1.2.3.4", against: ["*"]))
        XCTAssertTrue(IPValidator.validate(ip: "255.255.255.255", against: ["*"]))
    }

    func testValidate_multipleRanges() {
        let ranges = ["10.0.0.0/24", "192.168.1.0/24", "8.8.8.8"]
        XCTAssertTrue(IPValidator.validate(ip: "10.0.0.5", against: ranges))
        XCTAssertTrue(IPValidator.validate(ip: "192.168.1.100", against: ranges))
        XCTAssertTrue(IPValidator.validate(ip: "8.8.8.8", against: ranges))
        XCTAssertFalse(IPValidator.validate(ip: "172.16.0.1", against: ranges))
    }

    func testValidate_emptyRanges() {
        XCTAssertFalse(IPValidator.validate(ip: "1.2.3.4", against: []))
    }

    func testValidate_whitespaceTrimming() {
        XCTAssertTrue(IPValidator.validate(ip: "1.2.3.4", against: ["  1.2.3.4  "]))
        XCTAssertTrue(IPValidator.validate(ip: "1.2.3.4", against: [" * "]))
    }

    // MARK: - isValidIPOrCIDR

    func testIsValidIPOrCIDR_validIP() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("1.2.3.4"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("0.0.0.0"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("255.255.255.255"))
    }

    func testIsValidIPOrCIDR_validCIDR() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("10.0.0.0/24"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("0.0.0.0/0"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("1.2.3.4/32"))
    }

    func testIsValidIPOrCIDR_wildcard() {
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("*"))
        XCTAssertTrue(IPValidator.isValidIPOrCIDR("  *  "))
    }

    func testIsValidIPOrCIDR_invalid() {
        XCTAssertFalse(IPValidator.isValidIPOrCIDR(""))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("abc"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("1.2.3"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("1.2.3.4/33"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("1.2.3.4/-1"))
        XCTAssertFalse(IPValidator.isValidIPOrCIDR("256.0.0.0"))
    }
}
