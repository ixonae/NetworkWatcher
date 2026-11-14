import Foundation
import os

/// Unified logging categories. IPs and other user data go in with `privacy: .private`.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.ixonae.NetworkWatcher"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let alerts = Logger(subsystem: subsystem, category: "alerts")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
