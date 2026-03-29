import Foundation
import CoreWLAN
import CoreLocation
import SystemConfiguration

class NetworkMonitor: NSObject, CLLocationManagerDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocationPermission() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func currentSSID() -> String? {
        return wifiClient.interface()?.ssid()
    }

    func currentBSSID() -> String? {
        return wifiClient.interface()?.bssid()
    }

    func wifiInterfaceName() -> String? {
        return wifiClient.interface()?.interfaceName
    }

    /// Returns all active network identifiers: WiFi SSID if connected, plus interface types like "Ethernet".
    func activeNetworkIdentifiers() -> [String] {
        var identifiers: [String] = []

        if let ssid = currentSSID() {
            identifiers.append(ssid)
        }

        for iface in activeInterfaces() {
            switch iface.type {
            case .ethernet:
                identifiers.append("Ethernet")
            case .usb:
                identifiers.append("USB")
            case .thunderbolt:
                identifiers.append("Thunderbolt")
            default:
                break
            }
        }

        return identifiers
    }

    /// Returns the name of the first active interface (for disabling).
    func primaryInterfaceName() -> String? {
        return wifiInterfaceName() ?? activeInterfaces().first?.name
    }

    private func activeInterfaces() -> [NetworkInterface] {
        var result: [NetworkInterface] = []

        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return result
        }

        for iface in interfaces {
            let bsdName = SCNetworkInterfaceGetBSDName(iface) as String? ?? ""
            let typeStr = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""

            guard isInterfaceActive(bsdName) else { continue }

            let type: InterfaceType
            switch typeStr {
            case "Ethernet", "IEEE80211":
                if wifiClient.interface()?.interfaceName == bsdName {
                    continue // WiFi handled separately via SSID
                }
                type = .ethernet
            case "Bridge":
                type = .ethernet
            default:
                if bsdName.hasPrefix("en") {
                    type = .ethernet
                } else if bsdName.hasPrefix("utun") || bsdName.hasPrefix("ipsec") {
                    continue // VPN tunnels, skip
                } else {
                    type = .other(typeStr)
                }
            }

            result.append(NetworkInterface(name: bsdName, type: type))
        }

        return result
    }

    private func isInterfaceActive(_ bsdName: String) -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            if name == bsdName {
                let flags = Int32(ptr.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isRunning = (flags & IFF_RUNNING) != 0
                if isUp && isRunning && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        // Permission changed; the next SSID check will now work if authorized
    }
}

struct NetworkInterface {
    let name: String
    let type: InterfaceType
}

enum InterfaceType {
    case ethernet
    case usb
    case thunderbolt
    case other(String)
}
