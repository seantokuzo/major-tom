import SwiftUI

/// Shared timer for relative time updates — one timer for all message bubbles and separators.
let sharedRelativeTimeTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

struct TurnSeparator: View {
    let timestamp: Date
    @State private var relativeTime = ""

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            line
            Text(relativeTime)
                .font(.caption2)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            line
        }
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .onAppear { updateRelativeTime() }
        .onReceive(sharedRelativeTimeTimer) { _ in updateRelativeTime() }
    }

    private var line: some View {
        Rectangle()
            .fill(MajorTomTheme.Colors.textTertiary.opacity(0.3))
            .frame(height: 0.5)
    }

    private func updateRelativeTime() {
        relativeTime = RelativeTimeFormatter.format(timestamp)
    }
}

// MARK: - Relative Time Formatter

enum RelativeTimeFormatter {
    static func format(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TurnSeparator(timestamp: Date())
        TurnSeparator(timestamp: Date().addingTimeInterval(-120))
        TurnSeparator(timestamp: Date().addingTimeInterval(-3700))
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
