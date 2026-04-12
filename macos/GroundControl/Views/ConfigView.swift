import AppKit
import SwiftUI

/// Form-based configuration editor for the relay server.
///
/// Sections: Server, Authentication, Directories, Features, Startup, Cloudflare.
/// Secrets are stored in macOS Keychain, non-secret config in ~/.major-tom/config.json.
struct ConfigView: View {
    let relay: RelayProcess
    @Bindable var configManager: ConfigManager

    @State private var showResetConfirmation = false
    @State private var saveError: String?
    @State private var showSaveSuccess = false

    // Keychain-backed secret fields (loaded on appear)
    @State private var googleClientId = ""
    @State private var googleClientSecret = ""
    @State private var showGoogleClientId = false
    @State private var showGoogleClientSecret = false

    private var validation: RelayConfig.ValidationResult {
        configManager.config.validate()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                serverSection
                authSection
                directoriesSection
                featuresSection
                startupSection
                CloudflareTunnelView(relay: relay, configManager: configManager)

                Divider()
                actionButtons
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: loadSecrets)
        .alert("Reset to Defaults", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all configuration to default values. Keychain secrets will not be affected.")
        }
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        GroupBox("Server") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Relay Port") {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("Port", value: $configManager.config.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        if let error = validation.portError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                LabeledContent("Hook Port") {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("Hook Port", value: $configManager.config.hookPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        if let error = validation.hookPortError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                LabeledContent("Log Level") {
                    Picker("", selection: $configManager.config.logLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Authentication Section

    @ViewBuilder
    private var authSection: some View {
        GroupBox("Authentication") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Auth Mode") {
                    Picker("", selection: $configManager.config.authMode) {
                        ForEach(AuthMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                if configManager.config.authMode == .google {
                    googleOAuthFields
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var googleOAuthFields: some View {
        Divider()

        LabeledContent("Client ID") {
            HStack(spacing: 4) {
                Group {
                    if showGoogleClientId {
                        TextField("Google Client ID", text: $googleClientId)
                    } else {
                        SecureField("Google Client ID", text: $googleClientId)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

                Button {
                    showGoogleClientId.toggle()
                } label: {
                    Image(systemName: showGoogleClientId ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(showGoogleClientId ? "Hide" : "Reveal")
            }
        }

        LabeledContent("Client Secret") {
            HStack(spacing: 4) {
                Group {
                    if showGoogleClientSecret {
                        TextField("Google Client Secret", text: $googleClientSecret)
                    } else {
                        SecureField("Google Client Secret", text: $googleClientSecret)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

                Button {
                    showGoogleClientSecret.toggle()
                } label: {
                    Image(systemName: showGoogleClientSecret ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(showGoogleClientSecret ? "Hide" : "Reveal")
            }
        }
    }

    // MARK: - Directories Section

    @ViewBuilder
    private var directoriesSection: some View {
        GroupBox("Directories") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Claude Work Dir") {
                    HStack(spacing: 4) {
                        TextField("~/path/to/dir", text: $configManager.config.claudeWorkDir)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)

                        Button("Browse...") {
                            chooseDirectory()
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Features Section

    @ViewBuilder
    private var featuresSection: some View {
        GroupBox("Features") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Multi-User Mode", isOn: $configManager.config.multiUserEnabled)
                    .help("Enable multi-user features (per-user OS accounts)")
            }
            .padding(8)
        }
    }

    // MARK: - Startup Section

    @ViewBuilder
    private var startupSection: some View {
        GroupBox("Startup") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-start relay on app launch", isOn: $configManager.config.autoStart)
                    .help("Automatically start the relay server when Ground Control launches")

                Toggle("Launch at login", isOn: $configManager.config.launchAtLogin)
                    .help("Open Ground Control automatically when you log in to your Mac")
                    .onChange(of: configManager.config.launchAtLogin) { _, newValue in
                        LoginItemManager.setEnabled(newValue)
                    }
            }
            .padding(8)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Button("Reset to Defaults") {
                showResetConfirmation = true
            }

            Spacer()

            if let error = saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showSaveSuccess {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Apply & Restart") {
                applyAndRestart()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!validation.isValid)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Actions

    private func loadSecrets() {
        googleClientId = configManager.getSecret(ConfigManager.SecretKey.googleClientId) ?? ""
        googleClientSecret = configManager.getSecret(ConfigManager.SecretKey.googleClientSecret) ?? ""
    }

    private func saveSecrets() {
        if googleClientId.isEmpty {
            configManager.deleteSecret(ConfigManager.SecretKey.googleClientId)
        } else {
            configManager.setSecret(ConfigManager.SecretKey.googleClientId, value: googleClientId)
        }

        if googleClientSecret.isEmpty {
            configManager.deleteSecret(ConfigManager.SecretKey.googleClientSecret)
        } else {
            configManager.setSecret(ConfigManager.SecretKey.googleClientSecret, value: googleClientSecret)
        }
    }

    private func applyAndRestart() {
        saveError = nil
        showSaveSuccess = false

        do {
            try configManager.save()
            saveSecrets()
            showSaveSuccess = true

            // Hide success message after a moment
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                showSaveSuccess = false
            }

            // Restart relay to pick up new config
            Task {
                await relay.restart()
            }
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func resetToDefaults() {
        configManager.resetToDefaults()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the default working directory for Claude"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            configManager.config.claudeWorkDir = url.path
        }
    }
}
