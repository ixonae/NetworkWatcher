import Foundation

struct UpdateCheckResult {
    var status: UpdateStatus

    enum UpdateStatus: Equatable {
        case upToDate
        case available(version: String, url: String)
        case error(String)
    }
}

struct UpdateChecker {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdate(currentVersion: String) async -> UpdateCheckResult.UpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/ixonae/NetworkWatcher/releases/latest") else {
            return .error("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return .error("Could not fetch releases.")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                return .error("Could not parse release info.")
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewerVersion(latestVersion, than: currentVersion) {
                return .available(version: latestVersion, url: htmlURL)
            } else {
                return .upToDate
            }
        } catch {
            return .error("Network error.")
        }
    }

    func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0..<maxCount {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
