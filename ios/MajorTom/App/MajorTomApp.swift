import SwiftUI

@main
struct MajorTomApp: App {
    @State private var relay = RelayService()
    @State private var officeSceneManager = OfficeSceneManager()
    @State private var auth: AuthService
    @State private var notificationService = NotificationService()
    @State private var liveActivityManager = LiveActivityManager()
    @State private var watchConnectivity = PhoneWatchConnectivityService()
    @State private var titleStore: TabTitleStore
    @State private var terminalViewModel: TerminalViewModel
    @State private var achievementsViewModel: AchievementsViewModel?
    @State private var selectedTab: AppTab = .terminal

    init() {
        // TerminalViewModel is lifted to the App so the Office Manager can
        // see the authoritative list of terminal tabs. Office existence is
        // a per-tab iOS decision — no auto-creation tied to claude.
        let authService = AuthService()
        let store = TabTitleStore()
        _auth = State(initialValue: authService)
        _titleStore = State(initialValue: store)
        _terminalViewModel = State(initialValue: TerminalViewModel(auth: authService, titleStore: store))
    }
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
                let achievementsVM = AchievementsViewModel(auth: auth)
                achievementsViewModel = achievementsVM
                relay.officeSceneManager = officeSceneManager
                officeSceneManager.relay = relay
                relay.authService = auth
                relay.notificationService = notificationService
                relay.liveActivityManager = liveActivityManager
                relay.watchConnectivityService = watchConnectivity
                relay.achievementsViewModel = achievementsVM
                // Propagate user identity to relay for multi-user features
                relay.currentUserId = auth.userId
                if let role = auth.userRole {
                    relay.currentUserRole = role
                }
                setupNotificationHandlers()
                setupWatchConnectivity()
                // Kill any Live Activities left over from a prior launch (force-kill,
                // crash, etc.) so the Dynamic Island doesn't persist indefinitely.
                // Also set up the "user toggled off -> end all" observer.
                liveActivityManager.observePreferenceChanges()
                Task { await liveActivityManager.cleanupOrphanedActivities() }
            }
            .onChange(of: auth.userId) { _, newId in
                relay.currentUserId = newId
            }
            .onChange(of: auth.userRole) { _, newRole in
                relay.currentUserRole = newRole ?? .viewer
            }
            // Single auth-state connect path. `initial: true` fires on
            // cold launch for already-paired devices (AuthService loads
            // credentials from the Keychain synchronously in init()),
            // and the same handler catches a later false→true pairing
            // transition. RelayService.connect is a no-op if the socket
            // is already open, so repeat firings are safe.
            .onChange(of: auth.isPaired, initial: true) { _, isPaired in
                guard isPaired else { return }
                Task {
                    _ = await notificationService.requestPermission()
                    await relay.fetchAuthMethods(serverURL: auth.serverURL)
                    try? await relay.connect(to: auth.serverURL)
                }
            }
            // Wave 4: flush queued /btw messages when the relay reconnects so
            // any messages sent offline are delivered without user action.
            .onChange(of: relay.connectionState) { _, newState in
                if newState == .connected {
                    relay.flushAllQueuedSpriteMessages()
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
            .onReceive(NotificationCenter.default.publisher(for: .sendPromptFromShortcut)) { _ in
                handleShortcutAction(.sendPrompt)
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickApproveFromShortcut)) { _ in
                handleShortcutAction(.quickApprove)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGodModeFromShortcut)) { _ in
                handleShortcutAction(.toggleGodMode)
            }
            .onReceive(NotificationCenter.default.publisher(for: .checkAchievementsFromShortcut)) { _ in
                handleShortcutAction(.checkAchievements)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTerminalFromShortcut)) { _ in
                handleShortcutAction(.openTerminal)
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
            TerminalView(viewModel: terminalViewModel, liveActivityManager: liveActivityManager, watchConnectivity: watchConnectivity)
                .tabItem {
                    Label("Terminal", systemImage: "apple.terminal")
                }
                .tag(AppTab.terminal)

            OfficeManagerView(sceneManager: officeSceneManager, relay: relay, titleStore: titleStore, terminalViewModel: terminalViewModel)
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

            Group {
                if let vm = achievementsViewModel {
                    AchievementsListView(viewModel: vm)
                } else {
                    ProgressView()
                        .tint(MajorTomTheme.Colors.accent)
                }
            }
                .tabItem {
                    Label("Achievements", systemImage: "trophy")
                }
                .tag(AppTab.achievements)

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

        // Wave 5 — "Cool Beans" action on /btw response notifications clears
        // the unread state on the matching sprite (same as in-app Cool Beans).
        // Wave 4 — the `tabId` parameter routes multi-session tabs to the
        // correct Office; nil = legacy cli/vscode session.
        notificationService.onBtwCoolBeansAction = { sessionId, subagentId, tabId in
            let vm = officeSceneManager.ensureViewModel(for: sessionId, tabId: tabId)
            // The sprite id equals the subagentId for linked sprites.
            vm.dismissResponse(for: subagentId)
        }
    }

    private func handleShortcutAction(_ action: ShortcutActionKey.Action) {
        switch action {
        case .startSession:
            selectedTab = .terminal
            Task {
                if relay.currentSession == nil {
                    try? await relay.startSession()
                }
            }
        case .navigateToOffice:
            selectedTab = .office
        case .showCost:
            selectedTab = .terminal
        case .sendPrompt:
            selectedTab = .terminal
            Task {
                if let text = WidgetDataProvider.consumePendingPrompt() {
                    try? await relay.sendPrompt(text)
                }
            }
        case .quickApprove:
            selectedTab = .terminal
            Task {
                // Prefer the approval that the widget/intent snapshot showed, with a safe fallback.
                let snapshotApprovalId = WidgetDataProvider.consumePendingApprovalId()

                let targetApproval: ApprovalRequest? = {
                    if let id = snapshotApprovalId {
                        // Use the specific approval from the snapshot if it is still pending.
                        return relay.pendingApprovals.first(where: { $0.id == id })
                    }
                    // Snapshot is missing or stale; fall back to the latest pending approval.
                    return relay.pendingApprovals.last
                }()

                if let approval = targetApproval {
                    try? await relay.sendApproval(requestId: approval.id, decision: .allow)
                    HapticService.approve()
                }
            }
        case .openTerminal:
            selectedTab = .terminal
        case .toggleGodMode:
            Task {
                guard WidgetDataProvider.consumeGodModeToggle() else { return }
                switch relay.permissionMode {
                case .god:
                    // Toggle from god mode back to manual
                    try? await relay.setPermissionMode(.manual)
                    HapticService.modeSwitch()
                case .manual:
                    // Toggle from manual into god mode
                    try? await relay.setPermissionMode(.god, godSubMode: .normal)
                    HapticService.modeSwitch()
                default:
                    // In other modes (smart / delay), do not change the mode via this shortcut
                    break
                }
            }
        case .checkAchievements:
            selectedTab = .achievements
        }
    }

    private func handleDeepLink(_ deepLink: NotificationDeepLink) {
        if deepLink.isApproval {
            selectedTab = .terminal
        } else if deepLink.isOffice {
            selectedTab = .office
        } else if deepLink.isSession {
            selectedTab = .terminal
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
            // Navigate to the Terminal tab for the session.
            // If a specific sessionId is provided and differs from the current session,
            // attach to it so the user sees the right session context.
            if let sessionId = pathComponent,
               relay.currentSession?.id != sessionId {
                Task { try? await relay.attachSession(id: sessionId) }
            }
            selectedTab = .terminal
            HapticService.impact(.light)
        default:
            break
        }
    }

    /// Resolve an approval from a deep link.
    /// If requestId is "latest", approve/deny the most recent pending request.
    /// Only acts if the resolved requestId is currently in `pendingApprovals`
    /// to prevent untrusted callers from invoking arbitrary approvals.
    private func resolveApproval(requestId: String, approved: Bool) {
        let targetId: String
        if requestId == "latest" {
            guard let latest = relay.pendingApprovals.last else { return }
            targetId = latest.id
        } else {
            // Validate that this request is actually pending
            guard relay.pendingApprovals.contains(where: { $0.id == requestId }) else { return }
            targetId = requestId
        }

        selectedTab = .terminal
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
    case terminal
    case office
    case connect
    case analytics
    case achievements
    case settings
}
