import SwiftUI

struct ConnectionView: View {
    @State private var viewModel: ConnectionViewModel

    init(relay: RelayService) {
        _viewModel = State(initialValue: ConnectionViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: MajorTomTheme.Spacing.xl) {
            Spacer()

            // Status indicator
            VStack(spacing: MajorTomTheme.Spacing.md) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 48, height: 48)
                    .shadow(color: statusColor.opacity(0.5), radius: 12)

                Text(viewModel.connectionState.rawValue.capitalized)
                    .font(MajorTomTheme.Typography.title)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            }

            // Server address input
            VStack(spacing: MajorTomTheme.Spacing.sm) {
                Text("Relay Server")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

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
            }
            .padding(.horizontal, MajorTomTheme.Spacing.xxl)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MajorTomTheme.Spacing.xl)
                    .hapticOnAppear(.heavy)
            }

            // Connect/Disconnect button
            Button {
                HapticService.impact(.medium)
                Task {
                    if viewModel.isConnected {
                        viewModel.disconnect()
                    } else {
                        await viewModel.connect()
                    }
                }
            } label: {
                Text(viewModel.isConnected ? "Disconnect" : "Connect")
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
                    .background(viewModel.isConnected ? MajorTomTheme.Colors.deny : MajorTomTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            }
            .buttonStyle(.haptic(.medium))
            .disabled(viewModel.isConnecting)
            .padding(.horizontal, MajorTomTheme.Spacing.xxl)

            Spacer()
        }
        .background(MajorTomTheme.Colors.background)
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: MajorTomTheme.Colors.allow
        case .connecting, .reconnecting: MajorTomTheme.Colors.accent
        case .disconnected: MajorTomTheme.Colors.deny
        }
    }
}

#Preview {
    ConnectionView(relay: RelayService())
}
