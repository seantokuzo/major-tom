import SwiftUI
import WidgetKit

// MARK: - Medium Widget — Active Sessions

struct ActiveSessionsWidget: Widget {
    let kind = "ActiveSessionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SessionTimelineProvider()
        ) { entry in
            ActiveSessionsView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetColors.backgroundGradient
                }
        }
        .configurationDisplayName("Active Sessions")
        .description("Top 3 active sessions with status and cost.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Active Sessions", as: .systemMedium) {
    ActiveSessionsWidget()
} timeline: {
    SessionTimelineEntry(date: Date(), snapshot: .placeholder)
    SessionTimelineEntry(date: Date(), snapshot: .empty)
}
