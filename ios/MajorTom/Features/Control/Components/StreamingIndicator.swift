import SwiftUI

struct StreamingIndicator: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MajorTomTheme.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                    .offset(y: bounceOffset(for: index))
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.assistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        .task {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
    }

    private func bounceOffset(for index: Int) -> CGFloat {
        let delay = CGFloat(index) * 0.15
        let phase = max(0, min(1, animationPhase - delay))
        return -4 * sin(phase * .pi)
    }
}

#Preview {
    VStack(spacing: 20) {
        StreamingIndicator()
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
