import SwiftUI

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

                Text("Sign in with Google to connect")
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            }

            if viewModel.isFetchingMethods {
                ProgressView()
                    .tint(MajorTomTheme.Colors.accent)
            } else if viewModel.isGoogleEnabled {
                googleSignInButton
            } else {
                noAuthMethodsView
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

            Spacer()
        }
        .background(MajorTomTheme.Colors.background)
        .animation(.easeInOut(duration: 0.2), value: viewModel.authState)
        .task {
            // Bonjour browses silently so LAN-resolved URLs are preferred
            // over the tunnel when the relay is on the same network.
            viewModel.startDiscovery()
            await viewModel.fetchAuthMethods()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }

    // MARK: - Google Sign-In

    private var googleSignInButton: some View {
        Button {
            HapticService.impact(.medium)
            Task { await viewModel.signInWithGoogle() }
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                if viewModel.isSigningInWithGoogle {
                    ProgressView()
                        .tint(MajorTomTheme.Colors.textPrimary)
                } else {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20))
                }
                Text(viewModel.isSigningInWithGoogle ? "Signing in…" : "Sign in with Google")
                    .font(MajorTomTheme.Typography.headline)
            }
            .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MajorTomTheme.Spacing.md)
            .background(MajorTomTheme.Colors.surfaceElevated)
            .overlay {
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .stroke(MajorTomTheme.Colors.surface, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        }
        .disabled(viewModel.isSigningInWithGoogle || viewModel.isPairing)
        .padding(.horizontal, MajorTomTheme.Spacing.xxl)
    }

    private var noAuthMethodsView: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "lock.slash")
                .font(.system(size: 36))
                .foregroundStyle(MajorTomTheme.Colors.deny)

            Text("Google sign-in not available")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Text("Make sure the relay is reachable and has Google OAuth configured for iOS.")
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
}

#Preview {
    PairingView(auth: AuthService())
}
