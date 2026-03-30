import WidgetKit

// MARK: - Timeline Entry

struct SessionTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Timeline Provider

struct SessionTimelineProvider: TimelineProvider {
    typealias Entry = SessionTimelineEntry

    func placeholder(in context: Context) -> SessionTimelineEntry {
        SessionTimelineEntry(
            date: Date(),
            snapshot: .placeholder
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionTimelineEntry) -> Void) {
        let snapshot = WidgetDataService.readSnapshot()
        let entry = SessionTimelineEntry(
            date: Date(),
            snapshot: snapshot.sessions.isEmpty ? .placeholder : snapshot
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionTimelineEntry>) -> Void) {
        let snapshot = WidgetDataService.readSnapshot()
        let entry = SessionTimelineEntry(
            date: Date(),
            snapshot: snapshot
        )

        // Refresh every 15 minutes (Apple minimum), supplemented by
        // WidgetCenter.shared.reloadAllTimelines() from the main app.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}
