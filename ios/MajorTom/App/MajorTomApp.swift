import SwiftUI

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView(relay: relay)
                    .tabItem {
                        Label("Control", systemImage: "terminal")
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
        }
    }
}
