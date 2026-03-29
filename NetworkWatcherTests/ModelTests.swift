import XCTest

final class ModelTests: XCTestCase {

    // MARK: - NetworkEntry

    func testNetworkEntryDefaults() {
        let entry = NetworkEntry(networkIdentifier: "Test")
        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.networkIdentifier, "Test")
        XCTAssertTrue(entry.allowedIPRanges.isEmpty)
    }

    func testNetworkEntryCodable() throws {
        let entry = NetworkEntry(networkIdentifier: "TestWiFi", allowedIPRanges: [TestIP.stub, TestIP.cidr10_24, "*"])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.networkIdentifier, entry.networkIdentifier)
        XCTAssertEqual(decoded.allowedIPRanges, entry.allowedIPRanges)
    }

    func testNetworkEntryHashable() {
        let entry1 = NetworkEntry(networkIdentifier: "WiFi1")
        let entry2 = NetworkEntry(networkIdentifier: "WiFi2")
        var set = Set<NetworkEntry>()
        set.insert(entry1)
        set.insert(entry2)
        set.insert(entry1) // duplicate
        XCTAssertEqual(set.count, 2)
    }

    func testNetworkEntryDefaultIsVPN() {
        let entry = NetworkEntry(networkIdentifier: "Test")
        XCTAssertFalse(entry.isVPN)
    }

    func testNetworkEntryVpnCodable() throws {
        let entry = NetworkEntry(networkIdentifier: "VPNNet", isVPN: true, allowedIPRanges: [TestIP.cidr10_8])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.isVPN, true)
        XCTAssertEqual(decoded.networkIdentifier, "VPNNet")
        XCTAssertEqual(decoded.allowedIPRanges, [TestIP.cidr10_8])
    }

    func testNetworkEntryUniqueIDs() {
        let entry1 = NetworkEntry(networkIdentifier: "Same")
        let entry2 = NetworkEntry(networkIdentifier: "Same")
        XCTAssertNotEqual(entry1.id, entry2.id)
    }

    // MARK: - AppSettings

    func testAppSettingsCodable() throws {
        var settings = AppSettings()
        settings.checkIntervalSeconds = 30
        settings.showIPInMenuBar = true
        settings.launchAtLogin = true
        settings.allowUnconfiguredNetworks = true
        settings.ipLookupURL = "https://custom.example.com/ip"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.checkIntervalSeconds, 30)
        XCTAssertTrue(decoded.showIPInMenuBar)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertTrue(decoded.allowUnconfiguredNetworks)
        XCTAssertEqual(decoded.ipLookupURL, "https://custom.example.com/ip")
    }

    func testAppSettingsPredefinedURLs() {
        XCTAssertFalse(AppSettings.predefinedURLs.isEmpty)
        for preset in AppSettings.predefinedURLs {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertTrue(preset.url.hasPrefix("https://"))
        }
    }
}
