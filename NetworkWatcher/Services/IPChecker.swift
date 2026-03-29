import Foundation

class IPChecker {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchExternalIP(from urlString: String, authToken: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw IPCheckerError.invalidURL
        }

        var request = URLRequest(url: url)
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw IPCheckerError.badResponse
        }

        guard let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ip.isEmpty else {
            throw IPCheckerError.invalidData
        }

        return ip
    }
}

enum IPCheckerError: LocalizedError {
    case invalidURL
    case badResponse
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid IP lookup URL"
        case .badResponse: return "Bad response from IP lookup service"
        case .invalidData: return "Could not parse IP address from response"
        }
    }
}
