import SwiftUI

struct NetworkDetailView: View {
    @Binding var network: NetworkEntry
    @State private var newIP = ""
    @State private var newIPIsVPN = false

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

            Divider()

            Text("Allowed IP Addresses / Ranges")
                .font(.headline)

            if network.allowedIPRanges.isEmpty {
                Text("No allowed IPs configured yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                List {
                    ForEach(Array(network.allowedIPRanges.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text(entry.range)
                                .font(.system(.body, design: .monospaced))
                            if entry.isVPN {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.blue)
                                    .help("VPN")
                            }
                            Spacer()
                            Toggle("VPN", isOn: Binding(
                                get: { network.allowedIPRanges[index].isVPN },
                                set: { network.allowedIPRanges[index].isVPN = $0 }
                            ))
                            .toggleStyle(.checkbox)
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
                Toggle("VPN", isOn: $newIPIsVPN)
                    .toggleStyle(.checkbox)
                Button("Add") { addIP() }
                    .disabled(!IPValidator.isValidIPOrCIDR(newIP))
            }

            Text("Use a specific IP (1.2.3.4), a CIDR range (10.0.0.0/24), or * to allow any IP address on this network. Check VPN to indicate this IP/range is accessed through a VPN.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private var iconName: String {
        if network.allowedIPRanges.contains(where: { $0.isVPN }) { return "lock.shield" }
        if network.networkIdentifier == "*" { return "globe" }
        return "wifi"
    }

    private func addIP() {
        let trimmed = newIP.trimmingCharacters(in: .whitespaces)
        guard IPValidator.isValidIPOrCIDR(trimmed) else { return }
        network.allowedIPRanges.append(AllowedIPEntry(range: trimmed, isVPN: newIPIsVPN))
        newIP = ""
        newIPIsVPN = false
    }
}
