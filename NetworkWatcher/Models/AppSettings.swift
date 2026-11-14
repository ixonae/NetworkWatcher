import Foundation

struct AppSettings: Codable {
    var checkIntervalSeconds: Int = 60
    var showIPInMenuBar: Bool = false
    var launchAtLogin: Bool = false
    var allowUnconfiguredNetworks: Bool = false
    var muteAlerts: Bool = false
    var ipLookupURL: String = "https://api.ipify.org?format=text"

    /// IPv4-only endpoints: dual-stack services return an IPv6 address when one is available,
    /// which would not match the IPv4 rules most networks are configured with.
    static let predefinedURLs: [(name: String, url: String)] = [
        ("ipify (IPv4)", "https://api.ipify.org?format=text"),
        ("icanhazip (IPv4)", "https://ipv4.icanhazip.com"),
        ("ident.me (IPv4)", "https://4.ident.me"),
    ]

    /// Former dual-stack presets, mapped to their IPv4-only replacements.
    static let legacyPresetURLs: [String: String] = [
        "https://icanhazip.com": "https://ipv4.icanhazip.com",
        "https://ifconfig.me/ip": "https://4.ident.me",
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
        let storedURL = try container.decodeIfPresent(String.self, forKey: .ipLookupURL) ?? "https://api.ipify.org?format=text"
        ipLookupURL = Self.legacyPresetURLs[storedURL] ?? storedURL
    }
}
