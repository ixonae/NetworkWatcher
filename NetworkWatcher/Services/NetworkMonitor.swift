import Cocoa
import CoreWLAN
import CoreLocation
import SystemConfiguration

class NetworkMonitor: NSObject, CLLocationManagerDelegate, CWEventDelegate {
    typealias Scheduler = (TimeInterval, DispatchWorkItem) -> Void

    /// Global keys cover address and route changes on any interface.
    static let dynamicStoreKeys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
    /// Link state of physical en* interfaces only; awdl, llw, utun and bridges flap too often to be useful.
    static let dynamicStorePatterns = ["State:/Network/Interface/en[0-9]+/Link"]

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let scheduler: Scheduler
    private(set) var dynamicStore: SCDynamicStore?
    private var debounceWork: DispatchWorkItem?
    private(set) var isMonitoring = false

    /// Delay before reporting a change, so the new network has time to finish coming up.
    let debounceInterval: TimeInterval

    /// Called on the main queue after the SSID or interface changes, or after the Mac wakes.
    var onNetworkChange: (() -> Void)?

    init(
        debounceInterval: TimeInterval = 2,
        scheduler: @escaping Scheduler = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }
    ) {
        self.debounceInterval = debounceInterval
        self.scheduler = scheduler
        super.init()
        locationManager.delegate = self
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Change Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        wifiClient.delegate = self
        for event in [CWEventType.ssidDidChange, .bssidDidChange] {
            do {
                try wifiClient.startMonitoringEvent(with: event)
            } catch {
                NSLog("NetworkMonitor: failed to monitor Wi-Fi event \(event.rawValue): \(error)")
            }
        }

        // The store retains a weak box, so a late callback never touches a freed monitor.
        let box = WeakMonitorBox(self)
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                _ = Unmanaged<WeakMonitorBox>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                Unmanaged<WeakMonitorBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<WeakMonitorBox>.fromOpaque(info).takeUnretainedValue().monitor?.scheduleChangeNotification()
        }
        let store = withExtendedLifetime(box) {
            SCDynamicStoreCreate(nil, "NetworkWatcher" as CFString, callback, &context)
        }
        if let store {
            SCDynamicStoreSetNotificationKeys(
                store,
                Self.dynamicStoreKeys as CFArray,
                Self.dynamicStorePatterns as CFArray
            )
            SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main)
            dynamicStore = store
        } else {
            NSLog("NetworkMonitor: failed to create dynamic store: \(SCErrorString(SCError()))")
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        debounceWork?.cancel()
        debounceWork = nil
        try? wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
        if let store = dynamicStore {
            SCDynamicStoreSetDispatchQueue(store, nil)
            dynamicStore = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Coalesces bursts of events (SSID, BSSID, interface and route changes) into one callback.
    /// Must be called on the main queue; ignored while not monitoring.
    func scheduleChangeNotification() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isMonitoring else { return }

        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onNetworkChange?() }
        debounceWork = work
        scheduler(debounceInterval, work)
    }

    @objc private func systemDidWake() {
        scheduleChangeNotification()
    }

    // MARK: - CWEventDelegate

    // CoreWLAN delivers these on a private queue.

    func ssidDidChangeForWiFiInterface(withName _: String) {
        DispatchQueue.main.async { [weak self] in self?.scheduleChangeNotification() }
    }

    func bssidDidChangeForWiFiInterface(withName _: String) {
        DispatchQueue.main.async { [weak self] in self?.scheduleChangeNotification() }
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

    /// Returns all active network identifiers: WiFi SSID if connected, plus interface types like "Ethernet".
    func activeNetworkIdentifiers() -> [String] {
        Self.networkIdentifiers(ssid: currentSSID(), interfaceTypes: activeInterfaces().map(\.type))
    }

    /// SSID first, then each wired type once ("Ethernet", "USB", "Thunderbolt"). USB and Thunderbolt
    /// links are also reported as "Ethernet" after all specific types, so rules created for "Ethernet"
    /// before USB/Thunderbolt were detected keep matching, while a specific rule still wins.
    static func networkIdentifiers(ssid: String?, interfaceTypes: [InterfaceType]) -> [String] {
        var identifiers: [String] = []
        func append(_ identifier: String) {
            if !identifiers.contains(identifier) {
                identifiers.append(identifier)
            }
        }

        if let ssid {
            append(ssid)
        }
        for type in interfaceTypes {
            switch type {
            case .ethernet: append("Ethernet")
            case .usb: append("USB")
            case .thunderbolt: append("Thunderbolt")
            case .other: break
            }
        }
        if interfaceTypes.contains(where: { $0 == .usb || $0 == .thunderbolt }) {
            append("Ethernet")
        }
        return identifiers
    }

    /// Classifies a SystemConfiguration interface; nil for interfaces that aren't a network to match on.
    ///
    /// Wired adapters all report type "Ethernet", so USB and Thunderbolt are told apart by display name.
    /// Values seen on macOS 26: ("en1", "Ethernet", "Thunderbolt 1"), ("bridge0", "Bridge",
    /// "Thunderbolt Bridge"), ("en0", "IEEE80211", "Wi-Fi"); USB adapters show e.g. "USB 10/100/1000 LAN"
    /// and Apple's Thunderbolt adapter "Thunderbolt Ethernet".
    static func classify(bsdName: String, interfaceType: String, displayName: String, isWiFi: Bool) -> InterfaceType? {
        if isWiFi || bsdName.hasPrefix("utun") || bsdName.hasPrefix("ipsec") {
            return nil // Wi-Fi is matched by SSID; VPN tunnels are skipped
        }
        let name = displayName.lowercased()
        if interfaceType == "Bridge" || name.contains("thunderbolt") {
            return .thunderbolt
        }
        if name.contains("usb") {
            return .usb
        }
        if interfaceType == "Ethernet" || interfaceType == "IEEE80211" || bsdName.hasPrefix("en") {
            return .ethernet
        }
        return .other(interfaceType)
    }

    private func activeInterfaces() -> [NetworkInterface] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return []
        }
        let wifiName = wifiClient.interface()?.interfaceName

        return interfaces.compactMap { iface in
            let bsdName = SCNetworkInterfaceGetBSDName(iface) as String? ?? ""
            guard isInterfaceActive(bsdName),
                  let type = Self.classify(
                      bsdName: bsdName,
                      interfaceType: SCNetworkInterfaceGetInterfaceType(iface) as String? ?? "",
                      displayName: SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? "",
                      isWiFi: bsdName == wifiName
                  ) else {
                return nil
            }
            return NetworkInterface(name: bsdName, type: type)
        }
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

private final class WeakMonitorBox {
    weak var monitor: NetworkMonitor?

    init(_ monitor: NetworkMonitor) {
        self.monitor = monitor
    }
}

enum InterfaceType: Equatable {
    case ethernet
    case usb
    case thunderbolt
    case other(String)
}
