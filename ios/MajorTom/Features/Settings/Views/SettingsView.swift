import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    HStack {
                        Text("Server")
                        Spacer()
                        Text("localhost:9090")
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    }

                    HStack {
                        Text("Phase")
                        Spacer()
                        Text("1 — Hello Claude")
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsView()
}
