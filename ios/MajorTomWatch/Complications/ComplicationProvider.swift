import WidgetKit
import SwiftUI

// MARK: - Complication Timeline Entry

struct MajorTomComplicationEntry: TimelineEntry {
    let date: Date
    let activeSessionCount: Int
    let totalCost: Double
    let pendingApprovals: Int
    let isConnected: Bool

    var formattedCost: String {
        if totalCost < 0.01 && totalCost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", totalCost)
    }

    var inlineSummary: String {
        if !isConnected { return "Disconnected" }
        if activeSessionCount == 0 { return "No sessions" }
        return "\(activeSessionCount) sessions \u{2022} \(formattedCost)"
    }

    static let placeholder = MajorTomComplicationEntry(
        date: .now,
        activeSessionCount: 2,
        totalCost: 3.45,
        pendingApprovals: 0,
        isConnected: true
    )

    static let empty = MajorTomComplicationEntry(
        date: .now,
        activeSessionCount: 0,
        totalCost: 0,
        pendingApprovals: 0,
        isConnected: false
    )
}

// MARK: - Timeline Provider

struct MajorTomComplicationProvider: TimelineProvider {
    private let appGroupId = "group.com.majortom.shared"

    func placeholder(in context: Context) -> MajorTomComplicationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MajorTomComplicationEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MajorTomComplicationEntry>) -> Void) {
        let entry = readEntry()
        // Refresh in 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: entry.date) ?? entry.date
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readEntry() -> MajorTomComplicationEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return .empty
        }
        return MajorTomComplicationEntry(
            date: .now,
            activeSessionCount: defaults.integer(forKey: WatchConnectivityKeys.activeSessionCount),
            totalCost: defaults.double(forKey: WatchConnectivityKeys.totalCostToday),
            pendingApprovals: defaults.integer(forKey: WatchConnectivityKeys.pendingApprovalCount),
            isConnected: defaults.bool(forKey: WatchConnectivityKeys.connectionStatus)
        )
    }
}

// MARK: - Circular Complication

struct CircularComplicationView: View {
    let entry: MajorTomComplicationEntry

    private let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)

    var body: some View {
        ZStack {
            if entry.pendingApprovals > 0 {
                // Show pending approval count with red
                VStack(spacing: 0) {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("\(entry.pendingApprovals)")
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
            } else {
                // Show session count
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                    Text("\(entry.activeSessionCount)")
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Rectangular Complication

struct RectangularComplicationView: View {
    let entry: MajorTomComplicationEntry

    private let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(accentColor)
                Text("Major Tom")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Text("\(entry.activeSessionCount) sessions")
                .font(.caption)

            HStack(spacing: 4) {
                Text(entry.formattedCost)
                    .font(.caption2)
                    .foregroundStyle(accentColor)

                if entry.pendingApprovals > 0 {
                    Spacer()
                    Image(systemName: "bell.badge.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text("\(entry.pendingApprovals)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Inline Complication

struct InlineComplicationView: View {
    let entry: MajorTomComplicationEntry

    var body: some View {
        Text(entry.inlineSummary)
            .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Corner Complication

struct CornerComplicationView: View {
    let entry: MajorTomComplicationEntry

    var body: some View {
        Text("\(entry.activeSessionCount)")
            .font(.system(.title3, design: .rounded, weight: .bold))
            .widgetLabel {
                Text("sessions")
            }
            .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widget Configuration

// NOTE: This complication widget is registered via the MajorTomWidgets bundle (shared extension
// on the iOS side). If a watch-specific widget were needed, it would require a separate watchOS
// widget extension target. For now this is a known limitation — complications use the shared
// App Group data written by the iOS app's PhoneWatchConnectivityService.

struct MajorTomComplication: Widget {
    let kind: String = "MajorTomComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MajorTomComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Major Tom")
        .description("Session status and cost at a glance.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Adaptive Entry View

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MajorTomComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryRectangular:
            RectangularComplicationView(entry: entry)
        case .accessoryInline:
            InlineComplicationView(entry: entry)
        case .accessoryCorner:
            CornerComplicationView(entry: entry)
        default:
            CircularComplicationView(entry: entry)
        }
    }
}
