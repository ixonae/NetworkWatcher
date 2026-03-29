import Foundation

struct NetworkEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var networkIdentifier: String
    var isVPN: Bool = false
    var allowedIPRanges: [String] = []
}
