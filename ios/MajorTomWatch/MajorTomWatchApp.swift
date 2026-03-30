import SwiftUI

@main
struct MajorTomWatchApp: App {
    @State private var connectivity = WatchConnectivityService()
    @State private var viewModel: WatchViewModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    ContentView(viewModel: viewModel)
                } else {
                    ProgressView()
                        .tint(Color(red: 0.95, green: 0.65, blue: 0.25))
                }
            }
            .onAppear {
                guard viewModel == nil else { return }
                connectivity.activate()
                viewModel = WatchViewModel(connectivity: connectivity)
            }
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.95, green: 0.65, blue: 0.25))
        }
    }
}
