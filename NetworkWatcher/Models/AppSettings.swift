import Foundation

struct AppSettings: Codable {
    var checkIntervalSeconds: Int = 60
    var showIPInMenuBar: Bool = false
    var launchAtLogin: Bool = false
    var allowUnconfiguredNetworks: Bool = false
    var ipLookupURL: String = "https://api.ipify.org?format=text"

    static let predefinedURLs: [(name: String, url: String)] = [
        ("ipify", "https://api.ipify.org?format=text"),
        ("ifconfig.me", "https://ifconfig.me/ip"),
        ("icanhazip.com", "https://icanhazip.com"),
    ]
}
