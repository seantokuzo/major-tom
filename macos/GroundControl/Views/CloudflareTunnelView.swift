import SwiftUI

/// Cloudflare Tunnel configuration section.
///
/// Toggle to enable/disable, token stored in Keychain (masked by default),
/// optional tunnel name (display-only), live tunnel status from TunnelProcess,
/// and a "Test Tunnel" button that probes the relay's /health endpoint.
struct CloudflareTunnelView: View {
    let relay: RelayProcess
    @Bindable var configManager: ConfigManager

    @State private var tunnelToken = ""
    @State private var showToken = false
    @State private var tokenSaveTask: Task<Void, Never>?

    @State private var testResult: TestResult?
    @State private var isTesting = false

    /// Cached result of `TunnelProcess.findCloudflared()`. The fallback path
    /// spawns `/usr/bin/which` synchronously, so we must not re-evaluate on
    /// every view recomputation (any field edit triggers one).
    @State private var cloudflaredInstalled = true

    private enum TestResult: Equatable {
        case success(statusCode: Int)
        case failure(String)
    }

    // MARK: - Derived status

    private var statusText: String {
        if !configManager.config.cloudflareEnabled {
            return "Disabled"
        }
        // Prefer live process state over static "token saved" when enabled.
        switch relay.tunnel.state {
        case .idle:
            return tunnelToken.isEmpty ? "No token" : "Idle (waiting for relay)"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .restarting(let attempt):
            return "Restarting (attempt \(attempt)/5)..."
        case .error(let msg):
            return msg
        }
    }

    private var statusColor: Color {
        if !configManager.config.cloudflareEnabled { return .secondary }
        switch relay.tunnel.state {
        case .idle:
            return tunnelToken.isEmpty ? .orange : .gray
        case .starting, .stopping, .restarting:
            return .yellow
        case .running:
            return .green
        case .error:
            return .red
        }
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
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if configManager.config.cloudflareEnabled {
                    Divider()

                    if !cloudflaredInstalled {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("cloudflared not found — install with ") +
                            Text("`brew install cloudflared`").font(.body.monospaced())
                        }
                        .font(.caption)
                    }

                    LabeledContent("Tunnel Name") {
                        TextField("major-tom", text: $configManager.config.cloudflareTunnelName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                    }

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

                    HStack(spacing: 8) {
                        Button {
                            Task { await testTunnel() }
                        } label: {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Test Tunnel")
                            }
                        }
                        .disabled(isTesting || !relay.state.isRunning)
                        .help(relay.state.isRunning
                              ? "Probe the relay /health endpoint"
                              : "Start the relay first")

                        if let testResult {
                            switch testResult {
                            case .success(let code):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("OK (HTTP \(code))")
                                }
                                .font(.caption)
                            case .failure(let msg):
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(msg)
                                        .lineLimit(2)
                                }
                                .font(.caption)
                            }
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
            // Probe for cloudflared once. `findCloudflared` may spawn `which`
            // synchronously, so hop off the main thread for the discovery.
            Task.detached {
                let found = TunnelProcess.findCloudflared() != nil
                await MainActor.run { self.cloudflaredInstalled = found }
            }
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

    // MARK: - Actions

    /// Probe the relay's local `/health` endpoint. This validates that the
    /// relay is reachable on its configured port — which is the first thing
    /// that has to be true before the tunnel can forward traffic.
    private func testTunnel() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        guard let url = URL(string: "http://127.0.0.1:\(relay.state.port)/health") else {
            testResult = .failure("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    testResult = .success(statusCode: http.statusCode)
                } else {
                    testResult = .failure("HTTP \(http.statusCode)")
                }
            } else {
                testResult = .failure("No HTTP response")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}
