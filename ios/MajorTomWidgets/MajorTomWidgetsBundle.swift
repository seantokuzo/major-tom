import SwiftUI
import WidgetKit

// MARK: - Major Tom Widget Bundle

@main
struct MajorTomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionCountWidget()
        ActiveSessionsWidget()
        FleetDashboardWidget()
    }
}
