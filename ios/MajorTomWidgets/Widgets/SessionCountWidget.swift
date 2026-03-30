import SwiftUI
import WidgetKit

// MARK: - Small Widget — Session Count

struct SessionCountWidget: Widget {
    let kind = "SessionCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SessionTimelineProvider()
        ) { entry in
            SessionCountView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetColors.backgroundGradient
                }
        }
        .configurationDisplayName("Session Count")
        .description("Active session count and today's cost at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Session Count", as: .systemSmall) {
    SessionCountWidget()
} timeline: {
    SessionTimelineEntry(date: Date(), snapshot: .placeholder)
    SessionTimelineEntry(date: Date(), snapshot: .empty)
}
