import SwiftUI

/// Cloudflare Tunnel configuration section.
///
/// Toggle to enable/disable, token stored in Keychain (masked by default),
/// and a status indicator.
struct CloudflareTunnelView: View {
    @Bindable var configManager: ConfigManager

    @State private var tunnelToken = ""
    @State private var showToken = false
    @State private var tokenSaveTask: Task<Void, Never>?

    /// Derived status label for the tunnel (uses @State to avoid Keychain reads during recomputation).
    private var statusText: String {
        if !configManager.config.cloudflareEnabled {
            return "Disabled"
        }
        return !tunnelToken.isEmpty ? "Token saved" : "Not configured"
    }

    private var statusColor: Color {
        if !configManager.config.cloudflareEnabled { return .secondary }
        return !tunnelToken.isEmpty ? .green : .orange
    }

    var body: some View {
        GroupBox("Cloudflare Tunnel") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Enable Cloudflare Tunnel", isOn: $configManager.config.cloudflareEnabled)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if configManager.config.cloudflareEnabled {
                    Divider()

                    LabeledContent("Tunnel Token") {
                        HStack(spacing: 4) {
                            Group {
                                if showToken {
                                    TextField("Cloudflare Tunnel Token", text: $tunnelToken)
                                } else {
                                    SecureField("Cloudflare Tunnel Token", text: $tunnelToken)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)

                            Button {
                                showToken.toggle()
                            } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(showToken ? "Hide" : "Reveal")
                        }
                    }

                    Text("Get a tunnel token from the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .onAppear {
            tunnelToken = configManager.getSecret(ConfigManager.SecretKey.cloudflareToken) ?? ""
        }
        .onChange(of: tunnelToken) {
            // Debounce Keychain writes — only persist after 1s of inactivity
            tokenSaveTask?.cancel()
            tokenSaveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if tunnelToken.isEmpty {
                    configManager.deleteSecret(ConfigManager.SecretKey.cloudflareToken)
                } else {
                    configManager.setSecret(ConfigManager.SecretKey.cloudflareToken, value: tunnelToken)
                }
            }
        }
    }
}
