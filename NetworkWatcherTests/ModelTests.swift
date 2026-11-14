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
        settings.allowUnconfiguredNetworks = true
        settings.muteAlerts = true
        settings.ipLookupURL = "https://custom.example.com/ip"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.checkIntervalSeconds, 30)
        XCTAssertTrue(decoded.showIPInMenuBar)
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

    func testAppSettingsIgnoresLegacyLaunchAtLogin() throws {
        let json = #"{"checkIntervalSeconds":30,"launchAtLogin":true,"muteAlerts":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.checkIntervalSeconds, 30)
        XCTAssertTrue(decoded.muteAlerts)
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNil(reencoded?["launchAtLogin"])
    }

    func testAppSettingsDecodesEmptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.checkIntervalSeconds, 60)
        XCTAssertFalse(decoded.showIPInMenuBar)
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
        XCTAssertFalse(settings.allowUnconfiguredNetworks)
        XCTAssertFalse(settings.muteAlerts)
        XCTAssertEqual(settings.ipLookupURL, "https://api.ipify.org?format=text")
    }

    // MARK: - Lookup service presets

    private func decodeSettings(ipLookupURL: String) throws -> AppSettings {
        let json = #"{"ipLookupURL":"\#(ipLookupURL)"}"#
        return try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testPresetsAreIPv4Only() {
        let urls = AppSettings.predefinedURLs.map(\.url)
        XCTAssertEqual(urls, [
            "https://api.ipify.org?format=text",
            "https://ipv4.icanhazip.com",
            "https://4.ident.me",
        ])
        XCTAssertTrue(AppSettings.predefinedURLs.allSatisfy { $0.name.contains("IPv4") })
    }

    func testDefaultURLIsAPreset() {
        XCTAssertTrue(AppSettings.predefinedURLs.contains { $0.url == AppSettings().ipLookupURL })
    }

    func testLegacyIcanhazipPresetMigrates() throws {
        XCTAssertEqual(try decodeSettings(ipLookupURL: "https://icanhazip.com").ipLookupURL, "https://ipv4.icanhazip.com")
    }

    func testLegacyIfconfigPresetMigrates() throws {
        XCTAssertEqual(try decodeSettings(ipLookupURL: "https://ifconfig.me/ip").ipLookupURL, "https://4.ident.me")
    }

    func testLegacyMigrationsTargetCurrentPresets() {
        let presetURLs = Set(AppSettings.predefinedURLs.map(\.url))
        for target in AppSettings.legacyPresetURLs.values {
            XCTAssertTrue(presetURLs.contains(target), "\(target) is not a current preset")
        }
    }

    func testCurrentPresetsAndCustomURLsAreNotMigrated() throws {
        for preset in AppSettings.predefinedURLs {
            XCTAssertEqual(try decodeSettings(ipLookupURL: preset.url).ipLookupURL, preset.url)
        }
        XCTAssertEqual(try decodeSettings(ipLookupURL: "https://icanhazip.com/custom").ipLookupURL, "https://icanhazip.com/custom")
        XCTAssertEqual(try decodeSettings(ipLookupURL: "https://ip.example.com").ipLookupURL, "https://ip.example.com")
    }

    // MARK: - SettingsChange

    func testFirstSettingsUpdateStartsTimerAndRequestsNotificationPermission() {
        XCTAssertEqual(
            SettingsChange.between(nil, AppSettings()),
            SettingsChange(restartTimer: true, recheck: false, reevaluate: false, requestNotificationPermission: true)
        )
    }

    func testFirstSettingsUpdateWithPopupsSkipsNotificationPermission() {
        var settings = AppSettings()
        settings.alertStyle = .popup
        XCTAssertFalse(SettingsChange.between(nil, settings).requestNotificationPermission)
    }

    func testSwitchingToNotificationsRequestsPermission() {
        var old = AppSettings()
        old.alertStyle = .popup
        XCTAssertTrue(SettingsChange.between(old, AppSettings()).requestNotificationPermission)
    }

    func testSwitchingToPopupsOrKeepingStyleDoesNotRequestPermission() {
        var popup = AppSettings()
        popup.alertStyle = .popup
        XCTAssertFalse(SettingsChange.between(AppSettings(), popup).requestNotificationPermission)
        XCTAssertFalse(SettingsChange.between(AppSettings(), AppSettings()).requestNotificationPermission)
    }

    func testUnchangedSettingsNeedNothing() {
        XCTAssertEqual(
            SettingsChange.between(AppSettings(), AppSettings()),
            SettingsChange(restartTimer: false, recheck: false, reevaluate: false)
        )
    }

    func testIntervalChangeRestartsTimer() {
        var new = AppSettings()
        new.checkIntervalSeconds = 120
        XCTAssertEqual(
            SettingsChange.between(AppSettings(), new),
            SettingsChange(restartTimer: true, recheck: false, reevaluate: false)
        )
    }

    func testLookupURLChangeTriggersRecheck() {
        var new = AppSettings()
        new.ipLookupURL = "https://ip.example.com"
        XCTAssertTrue(SettingsChange.between(AppSettings(), new).recheck)
    }

    func testAllowUnconfiguredChangeTriggersReevaluation() {
        var new = AppSettings()
        new.allowUnconfiguredNetworks = true
        XCTAssertEqual(
            SettingsChange.between(AppSettings(), new),
            SettingsChange(restartTimer: false, recheck: false, reevaluate: true)
        )
    }

    func testDisplayOnlyChangesNeedNothing() {
        var new = AppSettings()
        new.showIPInMenuBar = true
        new.muteAlerts = true
        XCTAssertEqual(
            SettingsChange.between(AppSettings(), new),
            SettingsChange(restartTimer: false, recheck: false, reevaluate: false)
        )
    }

    // MARK: - Alert style

    func testAlertStyleDefaultsToNotification() {
        XCTAssertEqual(AppSettings().alertStyle, .notification)
    }

    func testAlertStyleMissingFromStoredSettingsDefaultsToNotification() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"muteAlerts":true}"#.utf8))
        XCTAssertEqual(decoded.alertStyle, .notification)
    }

    func testUnknownAlertStyleDefaultsToNotification() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"alertStyle":"hologram"}"#.utf8))
        XCTAssertEqual(decoded.alertStyle, .notification)
    }

    func testAlertStyleRoundTrips() throws {
        var settings = AppSettings()
        settings.alertStyle = .popup
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.alertStyle, .popup)
    }

    func testEffectiveAlertStyle() {
        XCTAssertEqual(AlertStyle.effective(preferred: .notification, notificationsAllowed: true), .notification)
        XCTAssertEqual(AlertStyle.effective(preferred: .notification, notificationsAllowed: false), .popup)
        XCTAssertEqual(AlertStyle.effective(preferred: .popup, notificationsAllowed: true), .popup)
        XCTAssertEqual(AlertStyle.effective(preferred: .popup, notificationsAllowed: false), .popup)
    }

    func testAlertStyleLabels() {
        XCTAssertEqual(Set(AlertStyle.allCases.map(\.label)).count, AlertStyle.allCases.count)
    }

    // MARK: - Check interval

    private func decodeInterval(_ value: Int) throws -> Int {
        let json = #"{"checkIntervalSeconds":\#(value)}"#
        return try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).checkIntervalSeconds
    }

    func testIntervalRangeBounds() {
        XCTAssertEqual(AppSettings.checkIntervalRange, 5...3600)
        XCTAssertTrue(AppSettings.checkIntervalRange.contains(AppSettings().checkIntervalSeconds))
    }

    func testIsValidInterval() {
        XCTAssertTrue(AppSettings.isValidInterval(5))
        XCTAssertTrue(AppSettings.isValidInterval(60))
        XCTAssertTrue(AppSettings.isValidInterval(3600))
        XCTAssertFalse(AppSettings.isValidInterval(4))
        XCTAssertFalse(AppSettings.isValidInterval(0))
        XCTAssertFalse(AppSettings.isValidInterval(-1))
        XCTAssertFalse(AppSettings.isValidInterval(3601))
    }

    func testClampedInterval() {
        XCTAssertEqual(AppSettings.clampedInterval(0), 5)
        XCTAssertEqual(AppSettings.clampedInterval(-10), 5)
        XCTAssertEqual(AppSettings.clampedInterval(30), 30)
        XCTAssertEqual(AppSettings.clampedInterval(99999), 3600)
    }

    func testOutOfRangeStoredIntervalsAreClampedOnDecode() throws {
        XCTAssertEqual(try decodeInterval(0), 5)
        XCTAssertEqual(try decodeInterval(-1), 5)
        XCTAssertEqual(try decodeInterval(99999), 3600)
    }

    func testValidStoredIntervalsPassThrough() throws {
        XCTAssertEqual(try decodeInterval(5), 5)
        XCTAssertEqual(try decodeInterval(120), 120)
        XCTAssertEqual(try decodeInterval(3600), 3600)
    }
}
