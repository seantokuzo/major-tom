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
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(MajorTomTheme.Colors.accent)

                Text("Major Tom")
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text("Enter the 6-digit PIN from your relay server")
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
            }
            .padding(.horizontal, MajorTomTheme.Spacing.xxl)

            // PIN display
            pinDisplay

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

            Spacer()
        }
        .background(MajorTomTheme.Colors.background)
        .animation(.easeInOut(duration: 0.2), value: viewModel.authState)
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
