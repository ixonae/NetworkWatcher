import XCTest
@testable import Network_Watcher

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

        network.allowedIPRanges = ["1.2.3.4"]
        manager.updateNetwork(network)

        XCTAssertEqual(manager.networks.first?.allowedIPRanges, ["1.2.3.4"])
    }

    func testDeleteNetwork() {
        let network = NetworkEntry(networkIdentifier: "TestWiFi")
        manager.addNetwork(network)
        XCTAssertEqual(manager.networks.count, 1)

        manager.deleteNetwork(network)
        XCTAssertEqual(manager.networks.count, 0)
    }

    // MARK: - networkForSSID

    func testNetworkForSSID_exactMatch() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: ["1.2.3.4"])
        manager.addNetwork(network)

        let result = manager.networkForSSID("MyWiFi")
        XCTAssertEqual(result?.networkIdentifier, "MyWiFi")
    }

    func testNetworkForSSID_caseInsensitive() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: ["1.2.3.4"])
        manager.addNetwork(network)

        let result = manager.networkForSSID("mywifi")
        XCTAssertEqual(result?.networkIdentifier, "MyWiFi")
    }

    func testNetworkForSSID_noMatch_noWildcard() {
        let network = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: ["1.2.3.4"])
        manager.addNetwork(network)

        let result = manager.networkForSSID("OtherWiFi")
        XCTAssertNil(result)
    }

    func testNetworkForSSID_fallbackToWildcard() {
        let specific = NetworkEntry(networkIdentifier: "MyWiFi", allowedIPRanges: ["1.2.3.4"])
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: ["5.6.7.8"])
        manager.addNetwork(specific)
        manager.addNetwork(catchAll)

        // Specific match
        let result1 = manager.networkForSSID("MyWiFi")
        XCTAssertEqual(result1?.networkIdentifier, "MyWiFi")

        // Falls back to wildcard
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
        let network = NetworkEntry(networkIdentifier: "PersistTest", allowedIPRanges: ["10.0.0.0/8"])
        manager.addNetwork(network)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.count, 1)
        XCTAssertEqual(manager2.networks.first?.networkIdentifier, "PersistTest")
        XCTAssertEqual(manager2.networks.first?.allowedIPRanges, ["10.0.0.0/8"])
    }

    // MARK: - Edge Cases

    func testUpdateNetwork_nonExistentID() {
        let network = NetworkEntry(networkIdentifier: "Ghost")
        manager.updateNetwork(network)
        XCTAssertEqual(manager.networks.count, 0)
    }

    func testDeleteNetwork_nonExistentID() {
        let network = NetworkEntry(networkIdentifier: "Original")
        manager.addNetwork(network)

        let ghost = NetworkEntry(networkIdentifier: "Ghost")
        manager.deleteNetwork(ghost)
        XCTAssertEqual(manager.networks.count, 1)
        XCTAssertEqual(manager.networks.first?.networkIdentifier, "Original")
    }

    func testAddMultipleNetworks_orderPreserved() {
        manager.addNetwork(NetworkEntry(networkIdentifier: "Alpha"))
        manager.addNetwork(NetworkEntry(networkIdentifier: "Beta"))
        manager.addNetwork(NetworkEntry(networkIdentifier: "Gamma"))

        XCTAssertEqual(manager.networks.map(\.networkIdentifier), ["Alpha", "Beta", "Gamma"])
    }

    func testNetworkPersistence_withVPN() {
        let network = NetworkEntry(networkIdentifier: "VPNWiFi", isVPN: true, allowedIPRanges: ["10.0.0.0/8"])
        manager.addNetwork(network)

        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.first?.isVPN, true)
    }

    func testNetworkForSSID_wildcardOnly() {
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: ["1.2.3.4"])
        manager.addNetwork(catchAll)

        let result = manager.networkForSSID("AnyNetwork")
        XCTAssertEqual(result?.networkIdentifier, "*")
    }

    func testNetworkForSSID_specificPreferredOverWildcard() {
        let specific = NetworkEntry(networkIdentifier: "HomeWiFi", allowedIPRanges: ["10.0.0.1"])
        let catchAll = NetworkEntry(networkIdentifier: "*", allowedIPRanges: ["1.2.3.4"])
        manager.addNetwork(catchAll)
        manager.addNetwork(specific)

        let result = manager.networkForSSID("HomeWiFi")
        XCTAssertEqual(result?.networkIdentifier, "HomeWiFi")
    }

    func testMalformedUserDefaults_networks() {
        testDefaults.set("not json".data(using: .utf8), forKey: "savedNetworks")
        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.networks.count, 0)
    }

    func testMalformedUserDefaults_settings() {
        testDefaults.set("not json".data(using: .utf8), forKey: "appSettings")
        let manager2 = NetworkManager(defaults: testDefaults)
        XCTAssertEqual(manager2.settings.checkIntervalSeconds, 60)
    }

    // MARK: - Default settings

    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.checkIntervalSeconds, 60)
        XCTAssertFalse(settings.showIPInMenuBar)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.allowUnconfiguredNetworks)
        XCTAssertEqual(settings.ipLookupURL, "https://api.ipify.org?format=text")
    }
}
