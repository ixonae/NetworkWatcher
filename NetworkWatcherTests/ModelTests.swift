import XCTest

final class ModelTests: XCTestCase {

    // MARK: - AllowedIPEntry

    func testAllowedIPEntryDefaults() {
        let entry = AllowedIPEntry(range: TestIP.stub)
        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.range, TestIP.stub)
        XCTAssertFalse(entry.isVPN)
    }

    func testAllowedIPEntryCodable() throws {
        let entry = AllowedIPEntry(range: TestIP.cidr10_8, isVPN: true)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AllowedIPEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.range, entry.range)
        XCTAssertEqual(decoded.isVPN, true)
    }

    func testAllowedIPEntryHashable() {
        let entry1 = AllowedIPEntry(range: TestIP.stub)
        let entry2 = AllowedIPEntry(range: TestIP.secondary)
        var set = Set<AllowedIPEntry>()
        set.insert(entry1)
        set.insert(entry2)
        set.insert(entry1) // duplicate
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - NetworkEntry

    func testNetworkEntryDefaults() {
        let entry = NetworkEntry(networkIdentifier: "Test")
        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.networkIdentifier, "Test")
        XCTAssertTrue(entry.allowedIPRanges.isEmpty)
    }

    func testNetworkEntryCodable() throws {
        let ranges = [
            AllowedIPEntry(range: TestIP.stub),
            AllowedIPEntry(range: TestIP.cidr10_24),
            AllowedIPEntry(range: "*", isVPN: true),
        ]
        let entry = NetworkEntry(networkIdentifier: "TestWiFi", allowedIPRanges: ranges)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.networkIdentifier, entry.networkIdentifier)
        XCTAssertEqual(decoded.allowedIPRanges.count, 3)
        XCTAssertEqual(decoded.allowedIPRanges[0].range, TestIP.stub)
        XCTAssertFalse(decoded.allowedIPRanges[0].isVPN)
        XCTAssertEqual(decoded.allowedIPRanges[2].range, "*")
        XCTAssertTrue(decoded.allowedIPRanges[2].isVPN)
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
        settings.muteAlerts = true
        settings.ipLookupURL = "https://custom.example.com/ip"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.checkIntervalSeconds, 30)
        XCTAssertTrue(decoded.showIPInMenuBar)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertTrue(decoded.allowUnconfiguredNetworks)
        XCTAssertTrue(decoded.muteAlerts)
        XCTAssertEqual(decoded.ipLookupURL, "https://custom.example.com/ip")
    }

    func testAppSettingsPredefinedURLs() {
        XCTAssertFalse(AppSettings.predefinedURLs.isEmpty)
        for preset in AppSettings.predefinedURLs {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertTrue(preset.url.hasPrefix("https://"))
        }
    }

    // MARK: - Migration from old format

    func testNetworkEntryDecodesOldFormatWithStringRanges() throws {
        let oldJSON = """
        {"id":"550E8400-E29B-41D4-A716-446655440000","networkIdentifier":"TestWiFi","isVPN":false,"allowedIPRanges":["1.2.3.4","10.0.0.0/24"]}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.networkIdentifier, "TestWiFi")
        XCTAssertEqual(decoded.allowedIPRanges.count, 2)
        XCTAssertEqual(decoded.allowedIPRanges[0].range, "1.2.3.4")
        XCTAssertFalse(decoded.allowedIPRanges[0].isVPN)
        XCTAssertEqual(decoded.allowedIPRanges[1].range, "10.0.0.0/24")
        XCTAssertFalse(decoded.allowedIPRanges[1].isVPN)
    }

    func testNetworkEntryDecodesOldFormatWithVPNTrue() throws {
        let oldJSON = """
        {"id":"550E8400-E29B-41D4-A716-446655440000","networkIdentifier":"VPNNet","isVPN":true,"allowedIPRanges":["10.0.0.0/8"]}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.networkIdentifier, "VPNNet")
        XCTAssertEqual(decoded.allowedIPRanges.count, 1)
        XCTAssertEqual(decoded.allowedIPRanges[0].range, "10.0.0.0/8")
        XCTAssertTrue(decoded.allowedIPRanges[0].isVPN)
    }

    func testNetworkEntryDecodesOldFormatEmptyRanges() throws {
        let oldJSON = """
        {"id":"550E8400-E29B-41D4-A716-446655440000","networkIdentifier":"Empty","allowedIPRanges":[]}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.networkIdentifier, "Empty")
        XCTAssertTrue(decoded.allowedIPRanges.isEmpty)
    }

    func testNetworkEntryDecodesNewFormat() throws {
        let newJSON = """
        {"id":"550E8400-E29B-41D4-A716-446655440000","networkIdentifier":"New","allowedIPRanges":[{"id":"660E8400-E29B-41D4-A716-446655440000","range":"1.2.3.4","isVPN":true}]}
        """
        let data = newJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.networkIdentifier, "New")
        XCTAssertEqual(decoded.allowedIPRanges.count, 1)
        XCTAssertEqual(decoded.allowedIPRanges[0].range, "1.2.3.4")
        XCTAssertTrue(decoded.allowedIPRanges[0].isVPN)
    }

    func testAppSettingsDecodesWithoutMuteAlerts() throws {
        let oldJSON = """
        {"checkIntervalSeconds":60,"showIPInMenuBar":false,"launchAtLogin":false,"allowUnconfiguredNetworks":false,"ipLookupURL":"https://api.ipify.org?format=text"}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(decoded.muteAlerts)
    }

    func testAppSettingsDecodesEmptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.checkIntervalSeconds, 60)
        XCTAssertFalse(decoded.showIPInMenuBar)
        XCTAssertFalse(decoded.launchAtLogin)
        XCTAssertFalse(decoded.allowUnconfiguredNetworks)
        XCTAssertFalse(decoded.muteAlerts)
        XCTAssertEqual(decoded.ipLookupURL, "https://api.ipify.org?format=text")
    }

    func testNetworkEntryDecodesWithInvalidAllowedIPRanges() throws {
        let json = """
        {"id":"550E8400-E29B-41D4-A716-446655440000","networkIdentifier":"Broken","allowedIPRanges":123}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkEntry.self, from: data)

        XCTAssertEqual(decoded.networkIdentifier, "Broken")
        XCTAssertTrue(decoded.allowedIPRanges.isEmpty)
    }

    // MARK: - Default settings

    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.checkIntervalSeconds, 60)
        XCTAssertFalse(settings.showIPInMenuBar)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.allowUnconfiguredNetworks)
        XCTAssertFalse(settings.muteAlerts)
        XCTAssertEqual(settings.ipLookupURL, "https://api.ipify.org?format=text")
    }
}
