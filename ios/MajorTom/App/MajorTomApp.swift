import SwiftUI

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()
    @State private var officeViewModel = OfficeViewModel()
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isPaired {
                    mainTabView
                } else {
                    PairingView(auth: auth)
                }
            }
            .tint(MajorTomTheme.Colors.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                relay.officeViewModel = officeViewModel
                relay.authService = auth
            }
            .onChange(of: auth.isPaired) { _, isPaired in
                if isPaired {
                    Task {
                        try? await relay.connect(to: auth.serverURL)
                    }
                }
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            ChatView(relay: relay)
                .tabItem {
                    Label("Control", systemImage: "terminal")
                }

            OfficeView(viewModel: officeViewModel)
                .tabItem {
                    Label("Office", systemImage: "building.2")
                }

            ConnectionView(relay: relay)
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }

            SettingsView(auth: auth, relay: relay)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
