import SwiftUI

struct DelayCountdownView: View {
    let state: DelayCountdownState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Circular countdown
            ZStack {
                // Track
                Circle()
                    .stroke(
                        MajorTomTheme.Colors.warning.opacity(0.2),
                        lineWidth: 3
                    )

                // Progress
                Circle()
                    .trim(from: 0, to: 1 - state.progress)
                    .stroke(
                        MajorTomTheme.Colors.warning,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.progress)

                // Seconds remaining
                Text("\(state.remainingSeconds)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.warning)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: state.remainingSeconds)
            }
            .frame(width: 36, height: 36)

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-approving")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                Text("in \(state.remainingSeconds)s")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.warning)
            }

            Spacer()

            // Cancel button
            Button {
                HapticService.buttonTap()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(.horizontal, MajorTomTheme.Spacing.md)
                    .padding(.vertical, MajorTomTheme.Spacing.xs)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }
}

// MARK: - Delay Picker

struct DelaySecondsPicker: View {
    let selectedSeconds: Int
    let onSelected: (Int) -> Void

    private let options = [3, 5, 10, 15, 30]

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "timer")
                .font(.system(size: 14))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            ForEach(options, id: \.self) { seconds in
                Button {
                    HapticService.buttonTap()
                    onSelected(seconds)
                } label: {
                    Text("\(seconds)s")
                        .font(.system(size: 13, weight: selectedSeconds == seconds ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(
                            selectedSeconds == seconds
                                ? MajorTomTheme.Colors.warning
                                : MajorTomTheme.Colors.textTertiary
                        )
                        .padding(.horizontal, MajorTomTheme.Spacing.sm)
                        .padding(.vertical, MajorTomTheme.Spacing.xs)
                        .background(
                            selectedSeconds == seconds
                                ? MajorTomTheme.Colors.warning.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DelayCountdownView(
            state: DelayCountdownState(
                requestId: "test-1",
                totalSeconds: 10,
                remainingSeconds: 7
            ),
            onCancel: {}
        )

        DelayCountdownView(
            state: DelayCountdownState(
                requestId: "test-2",
                totalSeconds: 5,
                remainingSeconds: 2
            ),
            onCancel: {}
        )

        DelaySecondsPicker(selectedSeconds: 5) { _ in }
        DelaySecondsPicker(selectedSeconds: 15) { _ in }
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
