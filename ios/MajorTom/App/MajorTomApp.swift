import SwiftUI

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Control", systemImage: "terminal") {
                    ChatView(relay: relay)
                }

                Tab("Connect", systemImage: "antenna.radiowaves.left.and.right") {
                    ConnectionView(relay: relay)
                }

                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
            .tint(MajorTomTheme.Colors.accent)
            .preferredColorScheme(.dark)
        }
    }
}
