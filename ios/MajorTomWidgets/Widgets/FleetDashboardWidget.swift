import SwiftUI
import WidgetKit

// MARK: - Large Widget — Fleet Dashboard

struct FleetDashboardWidget: Widget {
    let kind = "FleetDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SessionTimelineProvider()
        ) { entry in
            FleetDashboardWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetColors.backgroundGradient
                }
        }
        .configurationDisplayName("Fleet Dashboard")
        .description("Full fleet overview with sessions, agents, and health.")
        .supportedFamilies([.systemLarge])
    }
}

#Preview("Fleet Dashboard", as: .systemLarge) {
    FleetDashboardWidget()
} timeline: {
    SessionTimelineEntry(date: Date(), snapshot: .placeholder)
    SessionTimelineEntry(date: Date(), snapshot: .empty)
}
