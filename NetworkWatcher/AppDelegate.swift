import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let networkManager = NetworkManager()
    let ipChecker = IPChecker()
    let networkMonitor = NetworkMonitor()

    var currentIP: String = "Checking..."
    var ipStatus: IPStatus = .unknown
    private var alertState = AlertState()
    /// Orders checks so a slower, older check can't overwrite a newer result.
    private var checkCoordinator = CheckCoordinator()
    /// Why the last check failed, shown in the menu; nil after a successful check.
    private var lastFailureReason: String?
    private var lastCheckTime: Date?
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    /// Last IP the lookup returned, so rule changes can be re-evaluated without a new request.
    private var lastFetchedIP: String?
    /// Settings the timer and status were last configured from, to tell what a change affects.
    private var appliedSettings: AppSettings?

    private let modalPresenter = ModalAlertPresenter()
    private lazy var notificationPresenter = NotificationAlertPresenter { [weak self] in self?.openSettings() }
    private var notificationsAllowed = false

    func applicationDidFinishLaunching(_: Notification) {
        networkMonitor.requestLocationPermission()
        // Created up front so it is the notification delegate before any notification is clicked.
        _ = notificationPresenter
        setupStatusItem()

        networkMonitor.onNetworkChange = { [weak self] in
            Task { await self?.performIPCheck() }
        }
        networkMonitor.startMonitoring()

        // @Published emits before the property changes, so always use the emitted value.
        networkManager.$settings
            .sink { [weak self] settings in self?.settingsDidChange(settings) }
            .store(in: &cancellables)
        networkManager.$networks
            .dropFirst()
            .sink { [weak self] networks in self?.reevaluateStatus(networks: networks) }
            .store(in: &cancellables)

        Task { await performIPCheck() }
    }

    private func settingsDidChange(_ settings: AppSettings) {
        let change = SettingsChange.between(appliedSettings, settings)
        appliedSettings = settings

        updateMenuBarIPDisplay(showIP: settings.showIPInMenuBar)
        if change.restartTimer {
            restartTimer(intervalSeconds: settings.checkIntervalSeconds)
        }
        if change.requestNotificationPermission {
            requestNotificationPermission()
        }
        if change.recheck {
            Task { await performIPCheck() }
        } else if change.reevaluate {
            reevaluateStatus(settings: settings)
        }
    }

    /// Re-applies the rules to the last fetched IP after the user edits them, without a new lookup.
    /// No alert is shown for a change the user just made, but the alert state is updated so the
    /// next periodic check doesn't raise one about it either.
    private func reevaluateStatus(networks: [NetworkEntry]? = nil, settings: AppSettings? = nil) {
        guard let ip = lastFetchedIP else { return }
        let evaluator = StatusEvaluator(
            networks: networks ?? networkManager.networks,
            settings: settings ?? networkManager.settings
        )
        let evaluation = evaluator.evaluate(
            ip: ip,
            activeIdentifiers: networkMonitor.activeNetworkIdentifiers(),
            alertState: alertState,
            ssidBlockedByPermission: networkMonitor.isSSIDBlockedByPermission
        )
        ipStatus = evaluation.status
        alertState = evaluation.alertState
        updateStatusIcon()
        refreshMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        setupMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String

        switch ipStatus {
        case .match:
            symbolName = "checkmark.circle"
        case .matchVPN:
            symbolName = "lock.shield"
        case .mismatch:
            symbolName = "xmark.circle"
        case .unknown:
            symbolName = "questionmark.circle"
        case .noNetwork:
            symbolName = "minus.circle"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Network Status") {
            let finalImage = image.withSymbolConfiguration(config)
            finalImage?.isTemplate = true
            button.image = finalImage
            button.contentTintColor = nil
        }

        updateMenuBarIPDisplay()
    }

    private func updateMenuBarIPDisplay(showIP: Bool? = nil) {
        guard let button = statusItem.button else { return }
        if showIP ?? networkManager.settings.showIPInMenuBar {
            button.title = " \(currentIP)"
        } else {
            button.title = ""
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        let menu = NSMenu()

        let ipItem = NSMenuItem(title: "IP: \(currentIP)", action: nil, keyEquivalent: "")
        ipItem.tag = 100
        menu.addItem(ipItem)

        let lastCheckItem = NSMenuItem(title: "Last check: Never", action: nil, keyEquivalent: "")
        lastCheckItem.tag = 102
        menu.addItem(lastCheckItem)

        let locationItem = NSMenuItem(title: "Allow Location Access…", action: #selector(openLocationSettings), keyEquivalent: "")
        locationItem.tag = 104
        locationItem.target = self
        locationItem.isHidden = true
        menu.addItem(locationItem)

        menu.addItem(NSMenuItem.separator())

        let showIPItem = NSMenuItem(title: "Show IP in Menu Bar", action: #selector(toggleShowIP), keyEquivalent: "")
        showIPItem.tag = 101
        showIPItem.state = networkManager.settings.showIPInMenuBar ? .on : .off
        showIPItem.target = self
        menu.addItem(showIPItem)

        let muteAlertsItem = NSMenuItem(title: "Mute Alerts", action: #selector(toggleMuteAlerts), keyEquivalent: "")
        muteAlertsItem.tag = 103
        muteAlertsItem.state = networkManager.settings.muteAlerts ? .on : .off
        muteAlertsItem.target = self
        menu.addItem(muteAlertsItem)

        menu.addItem(NSMenuItem.separator())

        let checkNowItem = NSMenuItem(title: "Check Now", action: #selector(checkNow), keyEquivalent: "r")
        checkNowItem.target = self
        menu.addItem(checkNowItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Network Watcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    private func refreshMenu() {
        guard let menu = statusItem.menu else { return }

        if let ipItem = menu.item(withTag: 100) {
            if let reason = lastFailureReason {
                ipItem.title = "IP: \(currentIP) (\(reason))"
            } else {
                ipItem.title = "IP: \(currentIP)"
            }
        }

        if let lastCheckItem = menu.item(withTag: 102) {
            if let lastCheck = lastCheckTime {
                lastCheckItem.title = "Last check: \(Self.timeFormatter.string(from: lastCheck))"
            } else {
                lastCheckItem.title = "Last check: Never"
            }
        }

        if let showIPItem = menu.item(withTag: 101) {
            showIPItem.state = networkManager.settings.showIPInMenuBar ? .on : .off
        }

        if let locationItem = menu.item(withTag: 104) {
            locationItem.isHidden = !networkMonitor.isSSIDBlockedByPermission
        }

        if let muteAlertsItem = menu.item(withTag: 103) {
            muteAlertsItem.state = networkManager.settings.muteAlerts ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func toggleShowIP() {
        var settings = networkManager.settings
        settings.showIPInMenuBar.toggle()
        networkManager.updateSettings(settings)
        refreshMenu()
    }

    @objc private func toggleMuteAlerts() {
        var settings = networkManager.settings
        settings.muteAlerts.toggle()
        networkManager.updateSettings(settings)
        refreshMenu()
    }

    @objc private func checkNow() {
        Task { await performIPCheck() }
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(networkManager: networkManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Network Watcher Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - IP Checking

    private func restartTimer(intervalSeconds: Int) {
        timer?.invalidate()
        let interval = TimeInterval(AppSettings.clampedInterval(intervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.performIPCheck(trigger: .timer) }
        }
    }

    @MainActor
    func performIPCheck(trigger: CheckCoordinator.Trigger = .immediate) async {
        guard let generation = checkCoordinator.begin(trigger) else { return }
        defer { checkCoordinator.finish(generation) }

        do {
            let authToken = KeychainService.load(key: "ipLookupAuthToken")
            let ip = try await ipChecker.fetchExternalIP(from: networkManager.settings.ipLookupURL, authToken: authToken)
            guard checkCoordinator.isCurrent(generation) else { return }
            currentIP = ip
            lastFetchedIP = ip
            lastFailureReason = nil
            lastCheckTime = Date()

            let evaluator = StatusEvaluator(networks: networkManager.networks, settings: networkManager.settings)
            let evaluation = evaluator.evaluate(
                ip: ip,
                activeIdentifiers: networkMonitor.activeNetworkIdentifiers(),
                alertState: alertState,
                ssidBlockedByPermission: networkMonitor.isSSIDBlockedByPermission
            )
            ipStatus = evaluation.status
            // Store state before presenting a modal alert: checks can run while it is open.
            alertState = evaluation.alertState

            updateStatusIcon()
            refreshMenu()

            if let alert = evaluation.alert {
                // Finish first: the modal alert blocks until dismissed and periodic checks should continue.
                checkCoordinator.finish(generation)
                present(alert)
            }

        } catch {
            guard checkCoordinator.isCurrent(generation) else { return }
            currentIP = "Unavailable"
            lastFailureReason = IPChecker.failureReason(for: error)
            Log.network.error("IP lookup failed: \(error.localizedDescription, privacy: .public)")
            lastCheckTime = Date()
            ipStatus = .unknown
            updateStatusIcon()
            refreshMenu()
        }
    }

    private func present(_ alert: StatusAlert) {
        let content = AlertContent(alert)
        Task { @MainActor in
            // Re-read each time: the user may have allowed or blocked notifications in System Settings.
            notificationsAllowed = await notificationPresenter.isAuthorized()
            let style = AlertStyle.effective(
                preferred: networkManager.settings.alertStyle,
                notificationsAllowed: notificationsAllowed
            )
            switch style {
            case .notification: notificationPresenter.present(content)
            case .popup: modalPresenter.present(content)
            }
        }
    }

    private func requestNotificationPermission() {
        Task { @MainActor in
            notificationsAllowed = await notificationPresenter.requestAuthorization()
        }
    }

    @objc private func openLocationSettings() {
        NSWorkspace.shared.open(NetworkMonitor.locationSettingsURL)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        refreshMenu()
    }
}
