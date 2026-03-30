import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(auth: AuthService, relay: RelayService) {
        _viewModel = State(initialValue: SettingsViewModel(auth: auth, relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                connectionSection
                authSection
                notificationSection
                sessionSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Unpair Device?", isPresented: $viewModel.showUnpairConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Unpair", role: .destructive) {
                    viewModel.unpair()
                }
            } message: {
                Text("This will remove your device token. You'll need a new PIN to reconnect.")
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            HStack {
                Label("Server", systemImage: "server.rack")
                Spacer()
                Text(viewModel.serverURL)
                    .font(MajorTomTheme.Typography.codeFont)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            HStack {
                Label("Status", systemImage: "circle.fill")
                Spacer()
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.connectionState.rawValue.capitalized)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("Connection")
        }
    }

    // MARK: - Auth

    private var authSection: some View {
        Section {
            if viewModel.isPaired {
                HStack {
                    Label("Device", systemImage: "iphone")
                    Spacer()
                    Text(viewModel.deviceName)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)

                if let deviceId = viewModel.deviceId {
                    HStack {
                        Label("Device ID", systemImage: "number")
                        Spacer()
                        Text(String(deviceId.prefix(8)) + "...")
                            .font(MajorTomTheme.Typography.codeFontSmall)
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
                    .listRowBackground(MajorTomTheme.Colors.surface)
                }

                NavigationLink {
                    DeviceManagementView(viewModel: viewModel)
                } label: {
                    Label("Paired Devices", systemImage: "desktopcomputer")
                }
                .listRowBackground(MajorTomTheme.Colors.surface)

                Button(role: .destructive) {
                    HapticService.impact(.heavy)
                    viewModel.showUnpairConfirmation = true
                } label: {
                    Label("Unpair Device", systemImage: "xmark.shield")
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                HStack {
                    Label("Status", systemImage: "lock.open")
                    Spacer()
                    Text("Not Paired")
                        .foregroundStyle(MajorTomTheme.Colors.deny)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Authentication")
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsView(auth: viewModel.authService)
            } label: {
                Label("Notification Settings", systemImage: "bell.badge")
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Session

    private var sessionSection: some View {
        Section {
            HStack {
                Label("Active Sessions", systemImage: "terminal")
                Spacer()
                Text("\(viewModel.sessionCount)")
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            if let sessionId = viewModel.currentSessionId {
                HStack {
                    Label("Session ID", systemImage: "number")
                    Spacer()
                    Text(String(sessionId.prefix(8)) + "...")
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Session")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("2.0.0")
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            HStack {
                Label("Phase", systemImage: "flag")
                Spacer()
                Text("Feature Parity")
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("About")
        }
    }

    private var connectionStatusColor: Color {
        switch viewModel.connectionState {
        case .connected: MajorTomTheme.Colors.allow
        case .connecting, .reconnecting: MajorTomTheme.Colors.accent
        case .disconnected: MajorTomTheme.Colors.deny
        }
    }
}

#Preview {
    SettingsView(auth: AuthService(), relay: RelayService())
}
