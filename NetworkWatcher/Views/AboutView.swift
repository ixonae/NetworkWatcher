import SwiftUI

struct AboutView: View {
    @State private var updateStatus: UpdateCheckResult.UpdateStatus?
    @State private var isChecking = false
    private let updateChecker = UpdateChecker()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Network Watcher")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(currentVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Made by")
                    Link("Ixonae", destination: URL(string: "https://www.ixonae.com")!)
                }

                Link("GitHub Repository", destination: URL(string: "https://github.com/ixonae/NetworkWatcher")!)
            }
            .font(.callout)

            Divider()

            VStack(spacing: 8) {
                HStack {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates...")
                            .foregroundColor(.secondary)
                    } else if let status = updateStatus {
                        switch status {
                        case .upToDate:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("You're up to date.")
                        case .available(let version, _):
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                            Text("Version \(version) is available!")
                        case .error(let message):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(message)
                        }
                    }
                }
                .font(.callout)

                if case .available(_, let url) = updateStatus {
                    Link("Download latest version", destination: URL(string: url)!)
                        .font(.callout)
                }

                Button("Check for Updates") {
                    checkForUpdates()
                }
                .disabled(isChecking)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 350)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private func checkForUpdates() {
        isChecking = true
        Task {
            let result = await updateChecker.checkForUpdate(currentVersion: currentVersion)
            await MainActor.run {
                updateStatus = result
                isChecking = false
            }
        }
    }
}
