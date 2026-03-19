import SwiftUI

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()
    @State private var officeViewModel = OfficeViewModel()

    var body: some Scene {
        WindowGroup {
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

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .tint(MajorTomTheme.Colors.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                // Wire the office view model to the relay service
                // so agent events flow from WebSocket → RelayService → OfficeViewModel → OfficeScene
                relay.officeViewModel = officeViewModel
            }
        }
    }
}
