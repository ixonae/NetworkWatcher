import SwiftUI
import ServiceManagement
import UserNotifications

struct GeneralSettingsView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var settings: AppSettings = AppSettings()
    /// Edited as text: a number-formatted field keeps the previous value when the text is invalid.
    @State private var intervalText: String = ""
    @State private var selectedURLOption: String = AppSettings.predefinedURLs[0].name
    @State private var customURL: String = ""
    @State private var authToken: String = ""
    @State private var notificationsDenied = false
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?
    private let launchAtLogin = LaunchAtLogin()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Check every") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("", text: $intervalText)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !isIntervalValid {
                        Text("Enter a value between \(AppSettings.checkIntervalRange.lowerBound) and \(AppSettings.checkIntervalRange.upperBound) seconds.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Lookup service", selection: $selectedURLOption) {
                        ForEach(AppSettings.predefinedURLs, id: \.name) { option in
                            Text(option.name).tag(option.name)
                        }
                        Divider()
                        Text("Custom").tag("custom")
                    }
                    .onChange(of: selectedURLOption) { _, newValue in
                        if newValue == "custom" {
                            settings.ipLookupURL = customURL
                        } else if let url = AppSettings.predefinedURLs.first(where: { $0.name == newValue })?.url {
                            settings.ipLookupURL = url
                        }
                    }

                    if selectedURLOption == "custom" {
                        LabeledContent("URL") {
                            TextField("", text: $customURL)
                                .onChange(of: customURL) { _, newValue in
                                    settings.ipLookupURL = newValue
                                }
                        }
                    }

                    SecureField("Auth token", text: $authToken, prompt: Text("Optional"))
                } header: {
                    Text("IP Check")
                }

                Section {
                    Toggle("Show external IP in menu bar", isOn: $settings.showIPInMenuBar)
                } header: {
                    Text("Menu Bar")
                }

                Section {
                    Toggle("Allow unconfigured networks", isOn: $settings.allowUnconfiguredNetworks)

                    Text("Networks without configured IPs will be considered valid and won't trigger alerts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Picker("Alert style", selection: $settings.alertStyle) {
                        ForEach(AlertStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }

                    if settings.alertStyle == .notification && notificationsDenied {
                        Text("Notifications are turned off for Network Watcher in System Settings, so popup windows are used instead.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle("Mute alerts", isOn: $settings.muteAlerts)

                    Text("Suppress alerts for IP mismatches and restorations. The menu bar icon will still update.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } header: {
                    Text("Monitoring")
                }

                Section {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { updateLaunchAtLogin($0) }
                    ))

                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if launchAtLoginNeedsApproval {
                        HStack {
                            Text("Waiting for approval in System Settings > Login Items.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Login Items") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Text("Applies immediately.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("System")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Save") {
                    if let interval = parsedInterval {
                        settings.checkIntervalSeconds = interval
                    }
                    networkManager.updateSettings(settings)
                    let trimmedToken = authToken.trimmingCharacters(in: .whitespaces)
                    if trimmedToken.isEmpty {
                        KeychainService.delete(key: "ipLookupAuthToken")
                    } else {
                        _ = KeychainService.save(key: "ipLookupAuthToken", value: trimmedToken)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!isIntervalValid)
            }
            .padding()
        }
        .onAppear {
            settings = networkManager.settings
            intervalText = String(settings.checkIntervalSeconds)
            refreshLaunchAtLogin()
            initURLSelection()
            authToken = KeychainService.load(key: "ipLookupAuthToken") ?? ""
        }
        // The menu bar toggles these too; keep this copy current so Save doesn't revert them.
        .onReceive(networkManager.$settings) { updated in
            settings.showIPInMenuBar = updated.showIPInMenuBar
            settings.muteAlerts = updated.muteAlerts
        }
        // Approval happens in System Settings, so re-read the status on coming back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationsDenied = status == .denied
        }
    }

    private var parsedInterval: Int? {
        Int(intervalText.trimmingCharacters(in: .whitespaces))
    }

    private var isIntervalValid: Bool {
        parsedInterval.map(AppSettings.isValidInterval) ?? false
    }

    private func initURLSelection() {
        if let match = AppSettings.predefinedURLs.first(where: { $0.url == settings.ipLookupURL }) {
            selectedURLOption = match.name
        } else {
            selectedURLOption = "custom"
            customURL = settings.ipLookupURL
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = launchAtLogin.setEnabled(enabled)
        if let launchAtLoginError {
            Log.settings.error("\(launchAtLoginError, privacy: .public)")
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginEnabled = launchAtLogin.isEnabled
        launchAtLoginNeedsApproval = launchAtLogin.requiresApproval
    }
}
