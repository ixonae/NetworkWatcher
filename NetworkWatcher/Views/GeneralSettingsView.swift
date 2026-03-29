import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var settings: AppSettings = AppSettings()
    @State private var selectedURLOption: String = "ipify"
    @State private var customURL: String = ""
    @State private var authToken: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Check every") {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.checkIntervalSeconds, format: .number)
                                .frame(width: 60)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                        }
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

                    Toggle("Mute alerts", isOn: $settings.muteAlerts)

                    Text("Suppress popup alerts for IP mismatches and restorations. The menu bar icon will still update.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } header: {
                    Text("Monitoring")
                }

                Section {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(newValue)
                        }
                } header: {
                    Text("System")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Save") {
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
            }
            .padding()
        }
        .onAppear {
            settings = networkManager.settings
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            initURLSelection()
            authToken = KeychainService.load(key: "ipLookupAuthToken") ?? ""
        }
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
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
            settings.launchAtLogin = !enabled
        }
    }
}
