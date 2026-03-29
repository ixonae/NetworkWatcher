import SwiftUI

struct SettingsView: View {
    @ObservedObject var networkManager: NetworkManager

    enum Tab: String, CaseIterable {
        case networks = "Networks"
        case general = "General"
        case about = "About"
    }

    @State private var selectedTab: Tab = .networks

    var body: some View {
        TabView(selection: $selectedTab) {
            NetworkListView(networkManager: networkManager)
                .tabItem {
                    Label("Networks", systemImage: "wifi")
                }
                .tag(Tab.networks)

            GeneralSettingsView(networkManager: networkManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tab.general)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .frame(minWidth: 550, minHeight: 400)
        .padding()
    }
}
