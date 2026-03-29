import SwiftUI

struct NetworkDetailView: View {
    @Binding var network: NetworkEntry
    @State private var newIP = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: iconName)
                Text(network.networkIdentifier == "*" ? "Any network (catch-all)" : network.networkIdentifier)
                    .font(.title2)
                    .fontWeight(.medium)
            }

            if network.networkIdentifier == "*" {
                Text("This entry matches any network that doesn't have its own specific configuration. Use it to define a set of IPs that should be valid regardless of which network you're connected to.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Toggle("VPN connection", isOn: $network.isVPN)
            if network.isVPN {
                Text("When matched, the menu bar icon will indicate an active VPN connection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }

            Divider()

            Text("Allowed IP Addresses / Ranges")
                .font(.headline)

            if network.allowedIPRanges.isEmpty {
                Text("No allowed IPs configured yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                List {
                    ForEach(Array(network.allowedIPRanges.enumerated()), id: \.offset) { index, ip in
                        HStack {
                            Text(ip)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(action: {
                                network.allowedIPRanges.remove(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.bordered)
            }

            HStack {
                TextField("IP, CIDR, or * (e.g. 1.2.3.4, 10.0.0.0/24, *)", text: $newIP)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addIP() }
                Button("Add") { addIP() }
                    .disabled(!IPValidator.isValidIPOrCIDR(newIP))
            }

            Text("Use a specific IP (1.2.3.4), a CIDR range (10.0.0.0/24), or * to allow any IP address on this network.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private var iconName: String {
        if network.isVPN { return "lock.shield" }
        if network.networkIdentifier == "*" { return "globe" }
        return "wifi"
    }

    private func addIP() {
        let trimmed = newIP.trimmingCharacters(in: .whitespaces)
        guard IPValidator.isValidIPOrCIDR(trimmed) else { return }
        network.allowedIPRanges.append(trimmed)
        newIP = ""
    }
}
