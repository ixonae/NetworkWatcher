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
                Log.network.error("Failed to monitor Wi-Fi event \(event.rawValue): \(error.localizedDescription, privacy: .public)")
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
            let reason = String(cString: SCErrorString(SCError()))
            Log.network.error("Failed to create dynamic store: \(reason, privacy: .public)")
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

    /// True when Wi-Fi is connected but macOS withholds the SSID because location access isn't granted.
    var isSSIDBlockedByPermission: Bool {
        let wifi = wifiClient.interface()
        let wifiActive = wifi?.interfaceName.map(Self.activeInterfaceNames().contains) ?? false
        return Self.ssidBlockedByPermission(
            authorization: locationManager.authorizationStatus,
            wifiPoweredOn: wifi?.powerOn() ?? false,
            ssid: wifi?.ssid(),
            wifiActive: wifiActive
        )
    }

    /// - Parameter wifiActive: the Wi-Fi interface is up with an address. A radio that is on but
    ///   not joined to a network has no SSID either, which is not a permission problem.
    static func ssidBlockedByPermission(
        authorization: CLAuthorizationStatus,
        wifiPoweredOn: Bool,
        ssid: String?,
        wifiActive: Bool = true
    ) -> Bool {
        // macOS reports granted location access as .authorizedAlways (there is no "when in use").
        return wifiPoweredOn && wifiActive && ssid == nil && authorization != .authorizedAlways
    }

    /// System Settings pane where the user grants location access.
    static let locationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

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
        // Only Thunderbolt-named interfaces: other bridges (VMs, Internet Sharing) are not a wired network.
        if name.contains("thunderbolt") {
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
        let activeNames = Self.activeInterfaceNames()

        return interfaces.compactMap { iface in
            let bsdName = SCNetworkInterfaceGetBSDName(iface) as String? ?? ""
            guard activeNames.contains(bsdName),
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

    /// One address entry from getifaddrs.
    struct InterfaceAddress: Equatable {
        let name: String
        let flags: Int32
        let family: Int32
        /// IPv6 fe80::/10 address: assigned automatically on any link, so it says nothing about connectivity.
        var isLinkLocal = false
    }

    /// Names of interfaces that are up and running with an IPv4 or global IPv6 address,
    /// so IPv6-only links count as active too.
    static func activeInterfaceNames(from addresses: [InterfaceAddress]) -> Set<String> {
        let required = IFF_UP | IFF_RUNNING
        return Set(addresses.lazy
            .filter {
                $0.flags & required == required && !$0.isLinkLocal && ($0.family == AF_INET || $0.family == AF_INET6)
            }
            .map(\.name))
    }

    /// Reads all interface addresses in a single getifaddrs pass.
    private static func activeInterfaceNames() -> Set<String> {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        let addresses = sequence(first: firstAddr, next: { $0.pointee.ifa_next }).compactMap { ptr -> InterfaceAddress? in
            guard let address = ptr.pointee.ifa_addr else { return nil }
            let family = Int32(address.pointee.sa_family)
            let isLinkLocal = family == AF_INET6 && address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                let bytes = withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
                return bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
            }
            return InterfaceAddress(
                name: String(cString: ptr.pointee.ifa_name),
                flags: Int32(bitPattern: ptr.pointee.ifa_flags),
                family: family,
                isLinkLocal: isLinkLocal
            )
        }
        return activeInterfaceNames(from: addresses)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        // The SSID may have become readable (or hidden), so re-evaluate the network.
        DispatchQueue.main.async { [weak self] in self?.scheduleChangeNotification() }
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
