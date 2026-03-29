import Foundation
import Combine

class NetworkManager: ObservableObject {
    @Published var networks: [NetworkEntry] = []
    @Published var settings: AppSettings = AppSettings()

    private let networksKey = "savedNetworks"
    private let settingsKey = "appSettings"
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
        // Try exact match first, then fall back to catch-all "*"
        return networks.first(where: {
            $0.networkIdentifier.lowercased() == ssid.lowercased()
        }) ?? networks.first(where: { $0.networkIdentifier == "*" })
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
    }

}
