import Foundation

class IPChecker {
    /// Checks can run every few seconds, so a stalled request must not hang around for the 60s default.
    static let requestTimeout: TimeInterval = 10

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchExternalIP(from urlString: String, authToken: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw IPCheckerError.invalidURL
        }

        // Never answer from the URL cache: a stale IP would be judged against the current network.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw IPCheckerError.badResponse
        }

        // A captive portal answers 200 with an HTML page, so only accept a single plain IP address.
        guard let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              IPValidator.isValidIPAddress(ip) else {
            throw IPCheckerError.invalidData
        }

        return ip
    }

    /// Short, user-facing reason for a failed lookup, suitable for the menu.
    static func failureReason(for error: Error) -> String {
        if let error = error as? IPCheckerError {
            switch error {
            case .invalidURL: return "invalid lookup URL"
            case .badResponse: return "lookup service error"
            case .invalidData: return "no valid IP in response"
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "lookup timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "offline"
            case .cannotFindHost, .dnsLookupFailed: return "lookup host not found"
            default: break
            }
        }
        return "lookup failed"
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
