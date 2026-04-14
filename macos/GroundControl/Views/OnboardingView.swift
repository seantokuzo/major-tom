import SwiftUI

/// First-run onboarding wizard shown on initial launch.
///
/// Steps:
/// 1. Port configuration (default 9090, validate availability)
/// 2. Auth mode selection (none / PIN / Google OAuth)
/// 3. Optional Cloudflare Tunnel setup
///
/// Saves config via `ConfigManager` and starts the relay on completion.
struct OnboardingView: View {
    let configManager: ConfigManager
    let relay: RelayProcess
    let onComplete: () -> Void

    @State private var currentStep = 0

    // Config values being set up
    @State private var port = 9090
    @State private var portAvailable = true
    @State private var checkingPort = false
    @State private var authMode: AuthMode = .pin
    @State private var enableCloudflare = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0: portStep
                case 1: authStep
                case 2: cloudflareStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()

            // Navigation buttons
            navigationBar
        }
        .frame(width: 520, height: 440)
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not save configuration: \(saveError ?? "Unknown error"). Please try again.")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Welcome to Ground Control")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Let's set up your relay server")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Step 1: Port Configuration

    @ViewBuilder
    private var portStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Port Configuration")
                .font(.headline)

            Text("Choose the port for the relay server. The default (9090) works for most setups.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Relay Port") {
                        HStack(spacing: 8) {
                            TextField("Port", value: $port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onChange(of: port) {
                                    checkPortAvailability()
                                }

                            if checkingPort {
                                ProgressView()
                                    .controlSize(.small)
                            } else if portAvailable && port >= 1024 && port <= 65535 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if port < 1024 || port > 65535 {
                        Text("Port must be between 1024 and 65535")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !portAvailable && !checkingPort {
                        Text("Port \(port) appears to be in use. You can still use it if the other process will be stopped.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(4)
            }
        }
        .onAppear {
            checkPortAvailability()
        }
    }

    // MARK: - Step 2: Auth Mode

    @ViewBuilder
    private var authStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authentication")
                .font(.headline)

            Text("Choose how clients authenticate with the relay.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                authOption(
                    mode: .none,
                    title: "No Authentication",
                    description: "Anyone on the network can connect. Only use on trusted local networks.",
                    icon: "lock.open",
                    iconColor: .orange
                )

                authOption(
                    mode: .pin,
                    title: "PIN Authentication",
                    description: "Clients enter a PIN code to connect. Simple and effective for personal use.",
                    icon: "lock.fill",
                    iconColor: .blue
                )

                authOption(
                    mode: .google,
                    title: "Google OAuth",
                    description: "Clients sign in with Google. Best for shared setups. Requires OAuth credentials.",
                    icon: "person.badge.shield.checkmark",
                    iconColor: .green
                )
            }
        }
    }

    @ViewBuilder
    private func authOption(mode: AuthMode, title: String, description: String, icon: String, iconColor: Color) -> some View {
        Button {
            authMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if authMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(authMode == mode ? Color.blue.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(authMode == mode ? Color.blue.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Cloudflare Tunnel

    @ViewBuilder
    private var cloudflareStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote Access")
                .font(.headline)

            Text("Cloudflare Tunnel lets you access the relay from anywhere, not just your local network.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Cloudflare Tunnel", isOn: $enableCloudflare)

                    if enableCloudflare {
                        Text("You can configure the tunnel token in Settings after setup is complete.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("You can enable this later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            Spacer()

            // Summary
            GroupBox("Setup Summary") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Port") {
                        Text("\(port)")
                            .monospacedDigit()
                    }
                    LabeledContent("Authentication") {
                        Text(authMode.displayName)
                    }
                    LabeledContent("Cloudflare Tunnel") {
                        Text(enableCloudflare ? "Enabled" : "Disabled")
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Navigation Bar

    @ViewBuilder
    private var navigationBar: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            } else {
                Button("Finish Setup") {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Validation

    private var canAdvance: Bool {
        switch currentStep {
        case 0:
            return port >= 1024 && port <= 65535
        default:
            return true
        }
    }

    // MARK: - Actions

    private func checkPortAvailability() {
        checkingPort = true
        let portToCheck = port
        Task {
            let available = await isPortAvailable(portToCheck)
            if port == portToCheck {
                portAvailable = available
                checkingPort = false
            }
        }
    }

    private func isPortAvailable(_ port: Int) async -> Bool {
        // Try to bind a socket to the port — if it succeeds, the port is free
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return true } // Assume available if we can't check

        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    @State private var saveError: String?
    @State private var showSaveError = false

    private func finishSetup() {
        // Apply config
        configManager.config.port = port
        configManager.config.authMode = authMode
        configManager.config.cloudflareEnabled = enableCloudflare

        // Save — only proceed if successful
        do {
            try configManager.save()
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
            return
        }

        // Mark onboarding complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        // Start the relay
        Task {
            await relay.start()
        }

        onComplete()
    }
}
