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

    @Published var currentIP: String = "Checking..."
    @Published var ipStatus: IPStatus = .unknown
    private var mismatchAlertAcknowledged = false
    private var lastCheckTime: Date?

    enum IPStatus {
        case match
        case matchVPN
        case mismatch
        case unknown
        case noNetwork
    }

    func applicationDidFinishLaunching(_: Notification) {
        networkMonitor.requestLocationPermission()
        setupStatusItem()
        startChecking()

        networkManager.$settings
            .sink { [weak self] settings in
                self?.updateMenuBarIPDisplay()
                self?.restartTimer()
            }
            .store(in: &cancellables)
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

    private func updateMenuBarIPDisplay() {
        guard let button = statusItem.button else { return }
        if networkManager.settings.showIPInMenuBar {
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

        menu.addItem(NSMenuItem.separator())

        let showIPItem = NSMenuItem(title: "Show IP in Menu Bar", action: #selector(toggleShowIP), keyEquivalent: "")
        showIPItem.tag = 101
        showIPItem.state = networkManager.settings.showIPInMenuBar ? .on : .off
        showIPItem.target = self
        menu.addItem(showIPItem)

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
            ipItem.title = "IP: \(currentIP)"
        }

        if let lastCheckItem = menu.item(withTag: 102) {
            if let lastCheck = lastCheckTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .medium
                lastCheckItem.title = "Last check: \(formatter.string(from: lastCheck))"
            } else {
                lastCheckItem.title = "Last check: Never"
            }
        }

        if let showIPItem = menu.item(withTag: 101) {
            showIPItem.state = networkManager.settings.showIPInMenuBar ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func toggleShowIP() {
        var settings = networkManager.settings
        settings.showIPInMenuBar.toggle()
        networkManager.updateSettings(settings)
        updateMenuBarIPDisplay()
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

    private func startChecking() {
        restartTimer()
        Task { await performIPCheck() }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(networkManager.settings.checkIntervalSeconds, 5))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.performIPCheck() }
        }
    }

    @MainActor
    func performIPCheck() async {
        do {
            let authToken = KeychainService.load(key: "ipLookupAuthToken")
            let ip = try await ipChecker.fetchExternalIP(from: networkManager.settings.ipLookupURL, authToken: authToken)
            currentIP = ip
            lastCheckTime = Date()

            let activeIdentifiers = networkMonitor.activeNetworkIdentifiers()

            // Find the first configured network that matches an active connection
            var matchedNetwork: NetworkEntry?
            for identifier in activeIdentifiers {
                if let network = networkManager.networkForSSID(identifier) {
                    matchedNetwork = network
                    break
                }
            }

            let isUnconfigured = matchedNetwork == nil || matchedNetwork!.allowedIPRanges.isEmpty
            let networkName = matchedNetwork?.networkIdentifier
                ?? activeIdentifiers.first
                ?? "Unknown"

            if isUnconfigured {
                if networkManager.settings.allowUnconfiguredNetworks {
                    let wasInMismatch = mismatchAlertAcknowledged
                    ipStatus = .match
                    mismatchAlertAcknowledged = false
                    if wasInMismatch {
                        showRestoredAlert(ip: ip, networkName: networkName)
                    }
                } else {
                    ipStatus = .mismatch

                    if !mismatchAlertAcknowledged {
                        showUnconfiguredNetworkAlert(ip: ip, networkName: networkName)
                        mismatchAlertAcknowledged = true
                    }

                }
            } else if IPValidator.validate(ip: ip, against: matchedNetwork!.allowedIPRanges) {
                let wasInMismatch = mismatchAlertAcknowledged
                ipStatus = matchedNetwork!.isVPN ? .matchVPN : .match
                mismatchAlertAcknowledged = false
                if wasInMismatch {
                    showRestoredAlert(ip: ip, networkName: networkName)
                }
            } else {
                ipStatus = .mismatch

                if !mismatchAlertAcknowledged {
                    showMismatchAlert(ip: ip, network: matchedNetwork!)
                    mismatchAlertAcknowledged = true
                }


            }

            updateStatusIcon()
            refreshMenu()

        } catch {
            currentIP = "Error"
            ipStatus = .unknown
            updateStatusIcon()
            refreshMenu()
        }
    }

    private func showMismatchAlert(ip: String, network: NetworkEntry) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "IP Address Mismatch"
        alert.informativeText = "Your current external IP (\(ip)) does not match the expected IP range for network \"\(network.networkIdentifier)\".\n\nIf this is unexpected, check that the allowed IP list for this network is correct in Settings."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showRestoredAlert(ip: String, networkName: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "IP Address Restored"
        alert.informativeText = "Your external IP (\(ip)) on \"\(networkName)\" now matches the expected range."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUnconfiguredNetworkAlert(ip: String, networkName: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Unconfigured Network"
        alert.informativeText = "You are connected to \"\(networkName)\" with external IP \(ip), but this network has no allowed IPs configured.\n\nYou can add this network and its expected IPs in Settings, or enable \"Allow unconfigured networks\" in General settings to skip this warning."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        refreshMenu()
    }
}
