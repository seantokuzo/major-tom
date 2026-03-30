import SwiftUI
import WidgetKit

// MARK: - Small Widget View — Session Count + Cost

struct SessionCountView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(WidgetColors.accent)
                Text("Major Tom")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetColors.textSecondary)
                Spacer()
                Circle()
                    .fill(snapshot.isConnected ? WidgetColors.statusGreen : WidgetColors.statusRed)
                    .frame(width: 6, height: 6)
            }

            Spacer()

            Text("\(snapshot.activeSessionCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetColors.accent)
                .minimumScaleFactor(0.6)

            Text(snapshot.activeSessionCount == 1 ? "active session" : "active sessions")
                .font(.caption2)
                .foregroundStyle(WidgetColors.textSecondary)

            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption2)
                Text(snapshot.formattedTotalCost)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
            }
            .foregroundStyle(WidgetColors.textTertiary)
        }
        .padding(12)
    }
}
