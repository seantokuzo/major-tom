import SwiftUI

// MARK: - Progress Ring

/// Circular progress indicator for incremental achievements.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 60
    var lineWidth: CGFloat = 5
    var showLabel: Bool = true

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    MajorTomTheme.Colors.surface,
                    lineWidth: lineWidth
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    progressColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)

            // Percentage label
            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .monospaced))
                    .foregroundStyle(progressColor)
            }
        }
        .frame(width: size, height: size)
    }

    private var progressColor: Color {
        if progress >= 1.0 {
            return MajorTomTheme.Colors.allow
        } else if progress >= 0.5 {
            return MajorTomTheme.Colors.accent
        } else {
            return MajorTomTheme.Colors.textSecondary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressRing(progress: 0.0)
        ProgressRing(progress: 0.35)
        ProgressRing(progress: 0.75)
        ProgressRing(progress: 1.0)
        ProgressRing(progress: 0.5, size: 40, lineWidth: 3)
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
