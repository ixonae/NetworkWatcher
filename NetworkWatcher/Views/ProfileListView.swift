import SwiftUI

struct NetworkListView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var selectedNetworkID: UUID?
    @State private var showingAddSheet = false

    var body: some View {
        HSplitView {
            // Left: network list
            VStack(alignment: .leading, spacing: 0) {
                List(networkManager.networks, selection: $selectedNetworkID) { network in
                    HStack {
                        Image(systemName: network.isVPN ? "lock.shield" : network.networkIdentifier == "*" ? "globe" : "wifi")
                            .foregroundColor(.secondary)
                        Text(network.networkIdentifier == "*" ? "Any network" : network.networkIdentifier)
                        Spacer()
                        Text("\(network.allowedIPRanges.count) IP(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(network.id)
                }
                .listStyle(.sidebar)

                HStack {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedNetworkID == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Right: IP ranges for selected network
            if let id = selectedNetworkID,
               let index = networkManager.networks.firstIndex(where: { $0.id == id }) {
                NetworkDetailView(
                    network: Binding(
                        get: { networkManager.networks[index] },
                        set: { networkManager.updateNetwork($0) }
                    )
                )
                .id(id)
            } else {
                VStack {
                    Spacer()
                    Text("Select or add a network")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddNetworkSheet(networkManager: networkManager) { newNetwork in
                selectedNetworkID = newNetwork.id
            }
        }
    }

    private func deleteSelected() {
        guard let id = selectedNetworkID,
              let network = networkManager.networks.first(where: { $0.id == id }) else { return }
        networkManager.deleteNetwork(network)
        selectedNetworkID = networkManager.networks.first?.id
    }
}

struct AddNetworkSheet: View {
    @ObservedObject var networkManager: NetworkManager
    var onAdd: (NetworkEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedType = "custom"

    private let connectionTypes = [
        ("custom", "WiFi SSID (custom)"),
        ("*", "Any network (catch-all)"),
        ("Ethernet", "Ethernet"),
        ("USB", "USB"),
        ("Thunderbolt", "Thunderbolt"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Network")
                .font(.headline)

            Form {
                Picker("Connection type:", selection: $selectedType) {
                    ForEach(connectionTypes, id: \.0) { type in
                        Text(type.1).tag(type.0)
                    }
                }
                .onChange(of: selectedType) { _, newValue in
                    if newValue != "custom" {
                        name = newValue
                    } else {
                        name = ""
                    }
                }

                if selectedType == "custom" {
                    TextField("WiFi Network Name (SSID):", text: $name)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let network = NetworkEntry(networkIdentifier: name)
                    networkManager.addNetwork(network)
                    onAdd(network)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
