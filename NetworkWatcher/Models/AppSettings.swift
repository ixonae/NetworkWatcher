import Foundation

struct AppSettings: Codable {
    var checkIntervalSeconds: Int = 60
    var showIPInMenuBar: Bool = false
    var launchAtLogin: Bool = false
    var allowUnconfiguredNetworks: Bool = false
    var muteAlerts: Bool = false
    var ipLookupURL: String = "https://api.ipify.org?format=text"

    static let predefinedURLs: [(name: String, url: String)] = [
        ("ipify", "https://api.ipify.org?format=text"),
        ("ifconfig.me", "https://ifconfig.me/ip"),
        ("icanhazip.com", "https://icanhazip.com"),
    ]

    enum CodingKeys: String, CodingKey {
        case checkIntervalSeconds, showIPInMenuBar, launchAtLogin
        case allowUnconfiguredNetworks, muteAlerts, ipLookupURL
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .checkIntervalSeconds) ?? 60
        showIPInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showIPInMenuBar) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        allowUnconfiguredNetworks = try container.decodeIfPresent(Bool.self, forKey: .allowUnconfiguredNetworks) ?? false
        muteAlerts = try container.decodeIfPresent(Bool.self, forKey: .muteAlerts) ?? false
        ipLookupURL = try container.decodeIfPresent(String.self, forKey: .ipLookupURL) ?? "https://api.ipify.org?format=text"
    }
}
