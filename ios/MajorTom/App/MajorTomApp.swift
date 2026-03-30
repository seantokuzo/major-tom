import SwiftUI
import WatchConnectivity

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()
    @State private var officeViewModel = OfficeViewModel()
    @State private var auth = AuthService()
    @State private var sessionStorage = SessionStorageService()
    @State private var notificationService = NotificationService()
    @State private var liveActivityManager = LiveActivityManager()
    @State private var watchConnectivity = PhoneWatchConnectivityService()
    @State private var selectedTab: AppTab = .control
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isPaired {
                    mainTabView
                } else {
                    PairingView(auth: auth)
                }
            }
            .tint(MajorTomTheme.Colors.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                relay.officeViewModel = officeViewModel
                relay.authService = auth
                relay.notificationService = notificationService
                relay.liveActivityManager = liveActivityManager
                relay.watchConnectivityService = watchConnectivity
                setupNotificationHandlers()
                setupWatchConnectivity()
            }
            .onChange(of: auth.isPaired) { _, isPaired in
                if isPaired {
                    Task {
                        // Request notification permission after pairing
                        _ = await notificationService.requestPermission()
                        try? await relay.connect(to: auth.serverURL)
                    }
                }
            }
            // Handle deep links from notifications
            .onChange(of: notificationService.pendingDeepLink) { _, deepLink in
                guard let deepLink else { return }
                handleDeepLink(deepLink)
                notificationService.pendingDeepLink = nil
            }
            // Handle deep links from Live Activity approve/deny buttons and widget taps
            .onOpenURL { url in
                handleLiveActivityURL(url)
            }
            // Handle Siri shortcut notifications (in-process, e.g. Spotlight)
            .onReceive(NotificationCenter.default.publisher(for: .startSessionFromShortcut)) { _ in
                handleShortcutAction(.startSession)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToOfficeFromShortcut)) { _ in
                handleShortcutAction(.navigateToOffice)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCostFromShortcut)) { _ in
                handleShortcutAction(.showCost)
            }
            // Check for cross-process shortcut actions (Siri / Shortcuts app) on scene phase change
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    if let action = ShortcutActionKey.consumeAction() {
                        handleShortcutAction(action)
                    }
                }
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            ChatView(relay: relay, storage: sessionStorage)
                .tabItem {
                    Label("Control", systemImage: "terminal")
                }
                .tag(AppTab.control)

            OfficeView(viewModel: officeViewModel, relay: relay)
                .tabItem {
                    Label("Office", systemImage: "building.2")
                }
                .tag(AppTab.office)

            ConnectionView(relay: relay)
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(AppTab.connect)

            AnalyticsDashboardView(auth: auth)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(AppTab.analytics)

            SettingsView(auth: auth, relay: relay)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Notification Handlers

    private func setupNotificationHandlers() {
        notificationService.onApprovalAction = { requestId, approved in
            Task {
                let decision: ApprovalDecision = approved ? .allow : .deny
                try? await relay.sendApproval(requestId: requestId, decision: decision)
                if approved {
                    HapticService.approve()
                } else {
                    HapticService.deny()
                }
            }
        }
    }

    private func handleShortcutAction(_ action: ShortcutActionKey.Action) {
        switch action {
        case .startSession:
            selectedTab = .control
            Task {
                if relay.currentSession == nil {
                    try? await relay.startSession()
                }
            }
        case .navigateToOffice:
            selectedTab = .office
        case .showCost:
            selectedTab = .control
        }
    }

    private func handleDeepLink(_ deepLink: NotificationDeepLink) {
        if deepLink.isApproval {
            selectedTab = .control
        } else if deepLink.isOffice {
            selectedTab = .office
        } else if deepLink.isSession {
            selectedTab = .control
        }
        HapticService.impact(.light)
    }

    // MARK: - Live Activity Deep Links

    /// Handle URLs from Live Activity approve/deny buttons and widget taps.
    ///
    /// Supported schemes:
    /// - `majortom://approve/{requestId}` — approve the pending request
    /// - `majortom://deny/{requestId}` — deny the pending request
    /// - `majortom://session/{sessionId}` — navigate to session
    private func handleLiveActivityURL(_ url: URL) {
        guard url.scheme == "majortom" else { return }

        let host = url.host()
        let pathComponent = url.pathComponents.dropFirst().first // skip leading "/"

        switch host {
        case "approve":
            let requestId = pathComponent ?? "latest"
            resolveApproval(requestId: requestId, approved: true)
        case "deny":
            let requestId = pathComponent ?? "latest"
            resolveApproval(requestId: requestId, approved: false)
        case "session":
            selectedTab = .control
            HapticService.impact(.light)
        default:
            break
        }
    }

    /// Resolve an approval from a deep link.
    /// If requestId is "latest", approve/deny the most recent pending request.
    private func resolveApproval(requestId: String, approved: Bool) {
        let targetId: String
        if requestId == "latest" {
            guard let latest = relay.pendingApprovals.last else { return }
            targetId = latest.id
        } else {
            targetId = requestId
        }

        selectedTab = .control
        Task {
            let decision: ApprovalDecision = approved ? .allow : .deny
            try? await relay.sendApproval(requestId: targetId, decision: decision)
            if approved {
                HapticService.approve()
            } else {
                HapticService.deny()
            }
        }
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        watchConnectivity.activate()

        // Handle approval decisions from watch
        watchConnectivity.onApprovalDecision = { requestId, approved in
            Task {
                let decision: ApprovalDecision = approved ? .allow : .deny
                try? await relay.sendApproval(requestId: requestId, decision: decision)
                if approved {
                    HapticService.approve()
                } else {
                    HapticService.deny()
                }
            }
        }
    }
}

// MARK: - Tab Enum

enum AppTab: Hashable {
    case control
    case office
    case connect
    case analytics
    case settings
}
