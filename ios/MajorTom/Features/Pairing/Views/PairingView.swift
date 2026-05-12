import SwiftUI

// MARK: - Server Presets

enum ServerPreset: String {
    case cloudflare = "majortom.seantokuzodevtunnel.space"
    case tailscale  = "100.69.151.117:9090"
    case localhost   = "localhost:9090"

    var address: String { rawValue }

    var label: String {
        switch self {
        case .cloudflare: return "☁️ Tunnel"
        case .tailscale:  return "🔒 Tailscale"
        case .localhost:   return "💻 Local"
        }
    }

    /// Single preset for the device's current reachability. Tailscale
    /// (or any VPN presenting as `.other`) wins over LAN; cellular-only
    /// falls back to the public Cloudflare tunnel; offline returns nil.
    /// LAN is intentionally NOT a preset — it's served by Bonjour
    /// discovery in the pairing view, since the Mac's LAN IP drifts.
    init?(reachability: NetworkPathMonitor.Reachability) {
        switch reachability {
        case .tailscale: self = .tailscale
        case .lan:       return nil
        case .cellular:  self = .cloudflare
        case .offline:   return nil
        }
    }
}

struct PairingView: View {
    @State private var viewModel: PairingViewModel

    init(auth: AuthService) {
        _viewModel = State(initialValue: PairingViewModel(auth: auth))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: MajorTomTheme.Spacing.xxl) {
            Spacer()

            // Logo area
            VStack(spacing: MajorTomTheme.Spacing.md) {
                Image("MajorTomLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: MajorTomTheme.Colors.accent.opacity(0.4), radius: 12, y: 4)

                Text("Major Tom")
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text(headerSubtitle)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            }

            // Server address
            VStack(spacing: MajorTomTheme.Spacing.sm) {
                Text("Relay Server")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                TextField("host:port", text: $viewModel.serverAddress)
                    .textFieldStyle(.plain)
                    .font(MajorTomTheme.Typography.codeFont)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(MajorTomTheme.Spacing.md)
                    .background(MajorTomTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        Task { await viewModel.fetchAuthMethods() }
                    }

                // Bonjour-discovered chips (live local-network relays)
                // sit above the static fallback so the user sees the
                // current LAN target without typing the Mac's IP.
                discoveredChips

                // Static fallback presets (tunnel, Tailscale, localhost)
                // for off-LAN access — LAN itself comes from Bonjour above.
                recommendationChip
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.xxl)

            if viewModel.isFetchingMethods {
                ProgressView()
                    .tint(MajorTomTheme.Colors.accent)
            } else if !viewModel.hasAnyAuthMethod {
                // No auth methods enabled on the relay
                noAuthMethodsView
            } else if viewModel.isPinEnabled {
                // PIN auth available — show PIN entry
                pinDisplay
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MajorTomTheme.Spacing.xl)
                    .transition(.opacity)
                    .hapticOnAppear(.heavy)
            }

            if viewModel.isPinEnabled && viewModel.hasAnyAuthMethod {
                // PIN keypad
                pinKeypad

                // Submit button
                Button {
                    HapticService.impact(.medium)
                    Task { await viewModel.submitPIN() }
                } label: {
                    Group {
                        if viewModel.isPairing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Connect")
                                .font(MajorTomTheme.Typography.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
                    .background(viewModel.canSubmit ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
                }
                .disabled(!viewModel.canSubmit)
                .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            }

            Spacer()
        }
        .background(MajorTomTheme.Colors.background)
        .animation(.easeInOut(duration: 0.2), value: viewModel.authState)
        .task {
            // Start Bonjour discovery for live local-network relays.
            viewModel.browser.start()
            // Seed an empty server field — prefers a discovered service if
            // one's already known, falls back to the path monitor's
            // recommendation. One-shot so reachability flips don't fight a
            // user-typed override.
            viewModel.applyInitialRecommendationIfNeeded()
            await viewModel.fetchAuthMethods()
        }
        .onDisappear {
            viewModel.browser.stop()
        }
    }

    @ViewBuilder
    private var discoveredChips: some View {
        if !viewModel.discoveredServices.isEmpty {
            VStack(spacing: 6) {
                Text("Found on your network")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.discoveredServices) { service in
                            Button {
                                HapticService.impact(.light)
                                Task { await viewModel.useDiscovered(service) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "wifi")
                                        .font(.system(size: 10))
                                    Text(service.displayName)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(
                                    viewModel.serverAddress == service.address
                                        ? MajorTomTheme.Colors.background
                                        : MajorTomTheme.Colors.textSecondary
                                )
                                .padding(.horizontal, MajorTomTheme.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(
                                    viewModel.serverAddress == service.address
                                        ? MajorTomTheme.Colors.accent
                                        : MajorTomTheme.Colors.surfaceElevated
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        } else if viewModel.browser.isBrowsing {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Looking for relay on your network...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var recommendationChip: some View {
        if let preset = viewModel.recommendedPreset {
            Button {
                HapticService.impact(.light)
                Task { await viewModel.useRecommended() }
            } label: {
                HStack(spacing: 4) {
                    Text("Auto:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    Text(preset.label)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(
                            viewModel.serverAddress == preset.address
                                ? MajorTomTheme.Colors.background
                                : MajorTomTheme.Colors.textSecondary
                        )
                }
                .padding(.horizontal, MajorTomTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(
                    viewModel.serverAddress == preset.address
                        ? MajorTomTheme.Colors.accent
                        : MajorTomTheme.Colors.surfaceElevated
                )
                .clipShape(Capsule())
            }
        } else {
            Text("Offline — enter a relay URL above")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
    }

    private var headerSubtitle: String {
        if !viewModel.hasAnyAuthMethod {
            return "No authentication methods are enabled on the relay server"
        }
        if viewModel.isPinEnabled {
            return "Enter the 6-digit PIN from your relay server"
        }
        return "Connect to your relay server"
    }

    private var noAuthMethodsView: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "lock.slash")
                .font(.system(size: 36))
                .foregroundStyle(MajorTomTheme.Colors.deny)

            Text("No authentication methods enabled")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Text("Contact your relay administrator to enable PIN or Google authentication.")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MajorTomTheme.Spacing.xxl)

            Button {
                Task { await viewModel.fetchAuthMethods() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }
            .padding(.top, MajorTomTheme.Spacing.sm)
        }
        .padding(.horizontal, MajorTomTheme.Spacing.xl)
    }

    // MARK: - PIN Display

    private var pinDisplay: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            ForEach(0..<6, id: \.self) { index in
                let isFilled = index < viewModel.pin.count
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                    .fill(isFilled ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.surface)
                    .frame(width: 44, height: 52)
                    .overlay {
                        if isFilled {
                            let pinIndex = viewModel.pin.index(viewModel.pin.startIndex, offsetBy: index)
                            Text(String(viewModel.pin[pinIndex]))
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .foregroundStyle(MajorTomTheme.Colors.background)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                            .stroke(
                                index == viewModel.pin.count
                                    ? MajorTomTheme.Colors.accent
                                    : MajorTomTheme.Colors.surfaceElevated,
                                lineWidth: index == viewModel.pin.count ? 2 : 1
                            )
                    }
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.xxl)
    }

    // MARK: - Keypad

    private var pinKeypad: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            ForEach(keypadRows, id: \.self) { row in
                HStack(spacing: MajorTomTheme.Spacing.md) {
                    ForEach(row, id: \.self) { key in
                        keypadButton(key)
                    }
                }
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.xxl)
    }

    private var keypadRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"],
        ]
    }

    private func keypadButton(_ key: String) -> some View {
        Group {
            if key.isEmpty {
                Color.clear
                    .frame(width: 72, height: 52)
            } else {
                Button {
                    HapticService.impact(.light)
                    if key == "⌫" {
                        viewModel.deleteDigit()
                    } else {
                        viewModel.appendDigit(key)
                    }
                } label: {
                    Text(key)
                        .font(.system(.title2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .frame(width: 72, height: 52)
                        .background(MajorTomTheme.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                }
            }
        }
    }
}

#Preview {
    PairingView(auth: AuthService())
}
