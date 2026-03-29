import XCTest

final class IPValidatorTests: XCTestCase {

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

    // MARK: - validate

    func testValidateExactMatch() {
        XCTAssertTrue(IPValidator.validate(ip: TestIP.stub, against: [TestIP.stub]))
        XCTAssertFalse(IPValidator.validate(ip: TestIP.stubAlt, against: [TestIP.stub]))
    }

    func testValidateCidrMatch() {
        XCTAssertTrue(IPValidator.validate(ip: TestIP.private10_50, against: [TestIP.cidr10_24]))
        XCTAssertFalse(IPValidator.validate(ip: TestIP.private10Alt, against: [TestIP.cidr10_24]))
    }

    func testValidateWildcard() {
        XCTAssertTrue(IPValidator.validate(ip: TestIP.stub, against: ["*"]))
        XCTAssertTrue(IPValidator.validate(ip: TestIP.broadcast, against: ["*"]))
    }

    func testValidateMultipleRanges() {
        let ranges = [TestIP.cidr10_24, TestIP.cidr192_24, TestIP.dns]
        XCTAssertTrue(IPValidator.validate(ip: TestIP.private10_5, against: ranges))
        XCTAssertTrue(IPValidator.validate(ip: TestIP.private192_100, against: ranges))
        XCTAssertTrue(IPValidator.validate(ip: TestIP.dns, against: ranges))
        XCTAssertFalse(IPValidator.validate(ip: TestIP.private172_16, against: ranges))
    }

    func testValidateEmptyRanges() {
        XCTAssertFalse(IPValidator.validate(ip: TestIP.stub, against: []))
    }

    func testValidateWhitespaceTrimming() {
        XCTAssertTrue(IPValidator.validate(ip: TestIP.stub, against: ["  \(TestIP.stub)  "]))
        XCTAssertTrue(IPValidator.validate(ip: TestIP.stub, against: [" * "]))
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
