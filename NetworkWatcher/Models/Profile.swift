import Foundation

struct AllowedIPEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var range: String
    var isVPN: Bool = false
}

struct NetworkEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var networkIdentifier: String
    var allowedIPRanges: [AllowedIPEntry] = []

    enum CodingKeys: String, CodingKey {
        case id, networkIdentifier, allowedIPRanges, isVPN
    }

    init(id: UUID = UUID(), networkIdentifier: String, allowedIPRanges: [AllowedIPEntry] = []) {
        self.id = id
        self.networkIdentifier = networkIdentifier
        self.allowedIPRanges = allowedIPRanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        networkIdentifier = try container.decode(String.self, forKey: .networkIdentifier)

        // Try new format first: [AllowedIPEntry]
        if let entries = try? container.decode([AllowedIPEntry].self, forKey: .allowedIPRanges) {
            allowedIPRanges = entries
        } else if let strings = try? container.decode([String].self, forKey: .allowedIPRanges) {
            // Migrate from old format: [String] with optional per-network isVPN
            let wasVPN = (try? container.decode(Bool.self, forKey: .isVPN)) ?? false
            allowedIPRanges = strings.map { AllowedIPEntry(range: $0, isVPN: wasVPN) }
        } else {
            allowedIPRanges = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(networkIdentifier, forKey: .networkIdentifier)
        try container.encode(allowedIPRanges, forKey: .allowedIPRanges)
    }
}
