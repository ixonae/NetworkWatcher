import Foundation
import Combine

class NetworkManager: ObservableObject {
    @Published var networks: [NetworkEntry] = []
    @Published var settings: AppSettings = AppSettings()

    private let networksKey = "savedNetworks"
    private let settingsKey = "appSettings"
    private let presetMigrationKey = "lookupPresetMigrationDone"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadNetworks()
        loadSettings()
    }

    // MARK: - Network CRUD

    func addNetwork(_ network: NetworkEntry) {
        networks.append(network)
        saveNetworks()
    }

    func updateNetwork(_ network: NetworkEntry) {
        if let index = networks.firstIndex(where: { $0.id == network.id }) {
            networks[index] = network
        }
        saveNetworks()
    }

    func deleteNetwork(_ network: NetworkEntry) {
        networks.removeAll { $0.id == network.id }
        saveNetworks()
    }

    func networkForSSID(_ ssid: String) -> NetworkEntry? {
        Self.network(forIdentifier: ssid, in: networks)
    }

    static func network(forIdentifier identifier: String, in networks: [NetworkEntry]) -> NetworkEntry? {
        // Try exact match first, then fall back to catch-all "*"
        return networks.first(where: {
            $0.networkIdentifier.lowercased() == identifier.lowercased()
        }) ?? networks.first(where: { $0.networkIdentifier == "*" })
    }

    /// The configured network for the active connections: an exact match on any active identifier
    /// (in order) wins over the "*" catch-all, which only applies when no identifier matches exactly.
    static func network(forActiveIdentifiers identifiers: [String], in networks: [NetworkEntry]) -> NetworkEntry? {
        for identifier in identifiers {
            if let network = networks.first(where: {
                $0.networkIdentifier != "*" && $0.networkIdentifier.lowercased() == identifier.lowercased()
            }) {
                return network
            }
        }
        return networks.first(where: { $0.networkIdentifier == "*" })
    }

    // MARK: - Settings

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        saveSettings()
    }

    // MARK: - Persistence

    private func saveNetworks() {
        if let data = try? JSONEncoder().encode(networks) {
            defaults.set(data, forKey: networksKey)
        }
    }

    private func loadNetworks() {
        if let data = defaults.data(forKey: networksKey),
           let decoded = try? JSONDecoder().decode([NetworkEntry].self, from: data) {
            networks = decoded
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func loadSettings() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
        migrateLegacyLookupPreset()
    }

    /// Moves a former dual-stack preset to its IPv4-only replacement, once. Skipped when an auth
    /// token is saved: the token was meant for the old host and must not be sent to a new one.
    private func migrateLegacyLookupPreset() {
        guard !defaults.bool(forKey: presetMigrationKey) else { return }
        defaults.set(true, forKey: presetMigrationKey)
        guard let replacement = AppSettings.migratedLookupURL(for: settings.ipLookupURL),
              KeychainService.load(key: "ipLookupAuthToken")?.isEmpty ?? true else { return }
        settings.ipLookupURL = replacement
        saveSettings()
    }
}
