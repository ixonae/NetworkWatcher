import XCTest

final class NetworkManagerTests: XCTestCase {

    private static let suiteName = "com.ixonae.NetworkWatcher.Tests"
    var manager: NetworkManager!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.suiteName)!
        testDefaults.removePersistentDomain(forName: Self.suiteName)
        manager = NetworkManager(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    // MARK: - Network CRUD

    func testAddNetwork() {
        let network = NetworkEntry(networkIdentifier: "TestWiFi")
        manager.addNetwork(network)

        XCTAssertEqual(manager.networks.count, 1)
        XCTAssertEqual(manager.networks.first?.networkIdentifier, "TestWiFi")
    }

    func testUpdateNetwork() {
        var network = NetworkEntry(networkIdentifier: "TestWiFi")
        manager.addNetwork(network)

        network.allowedIPRanges = [AllowedIPEntry(range: TestIP.stub)]
        manager.updateNetwork(network)

        XCTAssertEqual(manager.networks.first?.allowedIPRanges.first?.range, TestIP.stub)
    }

    func testDeleteNetwork() {
        let network = NetworkEntry(networkIdentifier: "TestWiFi")
        manager.addNetwork(network)
        XCTAssertEqual(manager.networks.count, 1)

        manager.deleteNetwork(network)
        XCTAssertEqual(manager.networks.count, 0)
    }

    // MARK: - networkForSSID

    func testNetworkForSSIDExactMatch() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        manager.addNetwork(network)

        let result = manager.networkForSSID("MyWiFi")
        XCTAssertEqual(result?.networkIdentifier, "MyWiFi")
    }

    func testNetworkForSSIDCaseInsensitive() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        manager.addNetwork(network)

        let result = manager.networkForSSID("mywifi")
        XCTAssertEqual(result?.networkIdentifier, "MyWiFi")
    }

    func testNetworkForSSIDNoMatchNoWildcard() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        manager.addNetwork(network)

        let result = manager.networkForSSID("OtherWiFi")
        XCTAssertNil(result)
    }

    func testNetworkForSSIDFallbackToWildcard() {
        let specific = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: [AllowedIPEntry(range: TestIP.secondary)])
        manager.addNetwork(specific)
        manager.addNetwork(catchAll)

        let result1 = manager.networkForSSID("MyWiFi")
        XCTAssertEqual(result1?.networkIdentifier, "MyWiFi")

        let result2 = manager.networkForSSID("UnknownWiFi")
        XCTAssertEqual(result2?.networkIdentifier, "*")
    }

    // MARK: - Settings

    func testUpdateSettings() {
        var settings = AppSettings()
        settings.checkIntervalSeconds = 30
        settings.showIPInMenuBar = true

        manager.updateSettings(settings)

        XCTAssertEqual(manager.settings.checkIntervalSeconds, 30)
        XCTAssertTrue(manager.settings.showIPInMenuBar)
    }

    func testSettingsPersistence() {
        var settings = AppSettings()
        settings.checkIntervalSeconds = 45
        manager.updateSettings(settings)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.settings.checkIntervalSeconds, 45)
    }

    func testNetworkPersistence() {
        let network = NetworkEntry(networkIdentifier: "PersistTest", allowedIPRanges: [AllowedIPEntry(range: TestIP.cidr10_8)])
        manager.addNetwork(network)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.count, 1)
        XCTAssertEqual(manager2.networks.first?.networkIdentifier, "PersistTest")
        XCTAssertEqual(manager2.networks.first?.allowedIPRanges.first?.range, TestIP.cidr10_8)
    }

    // MARK: - Edge Cases

    func testUpdateNetworkNonExistentID() {
        let network = NetworkEntry(networkIdentifier: "Ghost")
        manager.updateNetwork(network)
        XCTAssertEqual(manager.networks.count, 0)
    }

    func testDeleteNetworkNonExistentID() {
        let network = NetworkEntry(networkIdentifier: "Original")
        manager.addNetwork(network)

        let ghost = NetworkEntry(networkIdentifier: "Ghost")
        manager.deleteNetwork(ghost)
        XCTAssertEqual(manager.networks.count, 1)
        XCTAssertEqual(manager.networks.first?.networkIdentifier, "Original")
    }

    func testAddMultipleNetworksOrderPreserved() {
        manager.addNetwork(NetworkEntry(networkIdentifier: "Alpha"))
        manager.addNetwork(NetworkEntry(networkIdentifier: "Beta"))
        manager.addNetwork(NetworkEntry(networkIdentifier: "Gamma"))

        XCTAssertEqual(manager.networks.map(\.networkIdentifier), ["Alpha", "Beta", "Gamma"])
    }

    func testNetworkPersistenceWithVPNOnIPEntry() {
        let vpnEntry = AllowedIPEntry(range: TestIP.cidr10_8, isVPN: true)
        let network = NetworkEntry(networkIdentifier: "VPNWiFi", allowedIPRanges: [vpnEntry])
        manager.addNetwork(network)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.first?.allowedIPRanges.first?.isVPN, true)
        XCTAssertEqual(manager2.networks.first?.allowedIPRanges.first?.range, TestIP.cidr10_8)
    }

    func testNetworkForSSIDWildcardOnly() {
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        manager.addNetwork(catchAll)

        let result = manager.networkForSSID("AnyNetwork")
        XCTAssertEqual(result?.networkIdentifier, "*")
    }

    func testNetworkForSSIDSpecificPreferredOverWildcard() {
        let specific = NetworkEntry(networkIdentifier: "HomeWiFi", allowedIPRanges: [AllowedIPEntry(range: TestIP.private10)])
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: [AllowedIPEntry(range: TestIP.stub)])
        manager.addNetwork(catchAll)
        manager.addNetwork(specific)

        let result = manager.networkForSSID("HomeWiFi")
        XCTAssertEqual(result?.networkIdentifier, "HomeWiFi")
    }

    func testMalformedUserDefaultsNetworks() {
        testDefaults.set("not json".data(using: .utf8), forKey: "savedNetworks")
        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.count, 0)
    }

    func testMalformedUserDefaultsSettings() {
        testDefaults.set("not json".data(using: .utf8), forKey: "appSettings")
        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.settings.checkIntervalSeconds, 60)
    }

    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.checkIntervalSeconds, 60)
        XCTAssertFalse(settings.showIPInMenuBar)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.allowUnconfiguredNetworks)
        XCTAssertFalse(settings.muteAlerts)
        XCTAssertEqual(settings.ipLookupURL, "https://api.ipify.org?format=text")
    }

    func testMuteAlertsPersistence() {
        var settings = AppSettings()
        settings.muteAlerts = true
        manager.updateSettings(settings)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertTrue(manager2.settings.muteAlerts)
    }
}
