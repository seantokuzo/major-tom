import Foundation
import UIKit
import WebKit

// MARK: - Terminal Connection State

enum TerminalConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Bridge Messages (JS → Swift)

/// Messages received from the terminal.html JavaScript bridge via
/// `window.webkit.messageHandlers.majorTom.postMessage()`.
enum TerminalBridgeMessage {
    case ready
    case connected(tabId: String)
    case disconnected(code: Int, reason: String)
    case retryExhausted(code: Int, reason: String)
    case bell
    case title(String)
    case selection(String)
    case resize(cols: Int, rows: Int)

    /// Parse a raw dictionary from `WKScriptMessageHandler`.
    static func parse(_ body: Any) -> TerminalBridgeMessage? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else {
            return nil
        }

        switch type {
        case "ready":
            return .ready
        case "connected":
            let tabId = dict["tabId"] as? String ?? ""
            return .connected(tabId: tabId)
        case "disconnected":
            let code = dict["code"] as? Int ?? 0
            let reason = dict["reason"] as? String ?? ""
            return .disconnected(code: code, reason: reason)
        case "retry_exhausted":
            let code = dict["code"] as? Int ?? 0
            let reason = dict["reason"] as? String ?? ""
            return .retryExhausted(code: code, reason: reason)
        case "bell":
            return .bell
        case "title":
            let title = dict["title"] as? String ?? ""
            return .title(title)
        case "selection":
            let text = dict["text"] as? String ?? ""
            return .selection(text)
        case "resize":
            let cols = dict["cols"] as? Int ?? 80
            let rows = dict["rows"] as? Int ?? 24
            return .resize(cols: cols, rows: rows)
        default:
            return nil
        }
    }
}

// MARK: - Terminal ViewModel

@Observable
@MainActor
final class TerminalViewModel {
    /// Current connection state of the terminal WebSocket.
    var connectionState: TerminalConnectionState = .disconnected

    /// The active tab ID for the PTY session on the relay.
    /// Derived from the active tab in the `tabs` array.
    var tabId: String {
        activeTab?.tabId ?? "default"
    }

    /// Terminal title shown in the status bar. Prefers a user rename
    /// (`userTitle`) over the xterm-supplied shell title.
    var terminalTitle: String {
        activeTab?.displayTitle ?? "Terminal"
    }

    /// Current terminal dimensions.
    var cols: Int = 80
    var rows: Int = 24

    /// Whether the terminal page has loaded and reported ready.
    var isReady: Bool = false

    /// Whether the web content process has terminated (recoverable).
    var didTerminate: Bool = false

    /// Weak reference to the WKWebView for sending keys from the native keybar.
    /// Set by TerminalWebView's makeUIView; nilled automatically on dealloc.
    weak var webView: WKWebView?

    // MARK: - Multi-Tab State

    /// All open terminal tabs.
    var tabs: [TerminalTab] = []

    /// The ID of the tab pending close confirmation (when user taps close).
    var pendingCloseTabId: UUID?

    /// Whether the close-tab confirmation dialog is showing.
    var showCloseConfirmation: Bool = false

    /// Signals the web view to switch to a new tab (disconnect + reconnect).
    /// Set by `switchTab(id:)`, consumed by TerminalWebView's `updateUIView`.
    var pendingTabSwitch: String?

    /// The currently active tab, if any.
    var activeTab: TerminalTab? {
        tabs.first(where: { $0.isActive })
    }

    /// Keybar customization and preference sync.
    var keybarViewModel: KeybarViewModel

    /// The currently selected terminal theme.
    var selectedTheme: TerminalTheme {
        keybarViewModel.selectedTheme
    }

    /// Reference to the auth service for relay URL and token.
    private let auth: AuthService

    // MARK: - Tab Persistence

    /// UserDefaults key for persisted tab IDs (string array).
    private static let persistedTabIdsKey = "mt-terminal-tab-ids"

    /// UserDefaults key for the active tab ID (string).
    private static let persistedActiveTabIdKey = "mt-terminal-active-tab-id"

    /// UserDefaults key for user-supplied tab renames ([tabId: userTitle]).
    private static let persistedTabUserTitlesKey = "mt-terminal-tab-user-titles"

    init(auth: AuthService) {
        self.auth = auth
        self.keybarViewModel = KeybarViewModel(auth: auth)

        // Restore persisted tab IDs. Tab-Keyed Offices (Wave 4) — we no
        // longer auto-spawn a default tab on empty; the user explicitly
        // creates every terminal via the "New Terminal" action. Previously
        // a cold launch without saved tabs materialized an unwanted PTY
        // (and sometimes an unwanted Office card) before the user did
        // anything intentional.
        let defaults = UserDefaults.standard
        let savedTabIds = defaults.stringArray(forKey: Self.persistedTabIdsKey) ?? []
        let savedActiveId = defaults.string(forKey: Self.persistedActiveTabIdKey)
        let savedUserTitles = defaults.dictionary(forKey: Self.persistedTabUserTitlesKey) as? [String: String] ?? [:]

        self.tabs = savedTabIds.map { tabId in
            TerminalTab(
                tabId: tabId,
                title: "Terminal",
                userTitle: savedUserTitles[tabId],
                isActive: tabId == savedActiveId
            )
        }

        // If there are tabs but none are marked active, activate the first
        // so a subsequent connect knows which PTY to attach to.
        if !self.tabs.isEmpty, !self.tabs.contains(where: { $0.isActive }) {
            self.tabs[0].isActive = true
        }
    }

    /// Persist current tab IDs, active tab, and user rename overrides.
    private func persistTabIds() {
        let defaults = UserDefaults.standard
        defaults.set(tabs.map(\.tabId), forKey: Self.persistedTabIdsKey)
        defaults.set(activeTab?.tabId, forKey: Self.persistedActiveTabIdKey)
        let userTitles: [String: String] = tabs.reduce(into: [:]) { acc, tab in
            if let custom = tab.userTitle, !custom.isEmpty {
                acc[tab.tabId] = custom
            }
        }
        if userTitles.isEmpty {
            defaults.removeObject(forKey: Self.persistedTabUserTitlesKey)
        } else {
            defaults.set(userTitles, forKey: Self.persistedTabUserTitlesKey)
        }
    }

    /// Apply a user-supplied rename to the given tab. Passing `nil` or an
    /// empty string clears the override, falling back to the xterm title.
    func renameTab(id: UUID, to newTitle: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs[index].userTitle = (trimmed?.isEmpty == false) ? trimmed : nil
        persistTabIds()
    }

    /// Reconcile persisted tabs with the relay's live PTY sessions.
    ///
    /// Fetches `GET /shell/tabs` and prunes any local tabs whose sessions
    /// no longer exist on the relay (e.g. expired past the 30-min grace
    /// after the relay was restarted while the app was backgrounded).
    /// Missing sessions are silent — the relay spawns a fresh PTY on the
    /// next connect.
    ///
    /// Call once after auth is established (e.g. from the terminal view's
    /// onAppear or after a successful auth check).
    func reconcileWithRelay() async {
        let base = relayBaseURL
        guard let url = URL(string: "\(base)/shell/tabs") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Auth: send the session JWT as a cookie header rather than a URL
        // query parameter. Query-param auth exposes the token in logs,
        // caches, and intermediaries — reserved for the WKWebView fallback
        // path where cookie injection is unreliable. Native URLSession
        // requests have full control over headers.
        if let token = authToken {
            request.setValue("mt-session=\(token)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            // v2 shape: [{tabId, attached, lastActivityAt}]
            struct TabEntry: Decodable {
                let tabId: String
            }

            let decoded = try JSONDecoder().decode([TabEntry].self, from: data)
            let relaySessions = Set(decoded.map(\.tabId))

            // If the relay has no live sessions at all, skip reconciliation
            // — our tabs will spawn fresh PTYs on connect. Only prune when
            // the relay has some sessions but ours are missing from the set.
            if relaySessions.isEmpty { return }

            let before = tabs.count
            tabs = tabs.filter { relaySessions.contains($0.tabId) }

            // Tab-Keyed Offices (Wave 4) — if every local tab got pruned we
            // leave `tabs` empty and let the TerminalView show its empty
            // state. No more auto-spawning a fresh default PTY the user
            // never asked for.
            if !tabs.isEmpty, !tabs.contains(where: { $0.isActive }) {
                tabs[0].isActive = true
            }

            if tabs.count != before {
                persistTabIds()
            }
        } catch {
            // Network error — skip reconciliation, tabs will connect normally.
            // The relay spawns PTYs on demand so stale tab IDs just get fresh
            // sessions (`restored:false`), which is acceptable.
        }
    }

    // MARK: - Tab Management

    /// Create a new tab and switch to it.
    func createTab() {
        // Deactivate all existing tabs.
        for i in tabs.indices {
            tabs[i].isActive = false
        }

        let newTab = TerminalTab(title: "Terminal", isActive: true)
        tabs.append(newTab)
        persistTabIds()

        // Signal the web view to connect to the new tab.
        pendingTabSwitch = newTab.tabId
    }

    /// Close a tab by its ID.
    ///
    /// Tab-Keyed Offices (Wave 4) — closing the last tab leaves `tabs`
    /// empty; TerminalView shows an explicit "New Terminal" empty state
    /// rather than auto-spawning a fresh PTY. If the closed tab was the
    /// active one (and others remain), we switch to the nearest neighbor.
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = tabs[index].isActive
        tabs.remove(at: index)

        if tabs.isEmpty {
            persistTabIds()
            // Clear any pending switch — there's nothing to connect to.
            pendingTabSwitch = nil
            connectionState = .disconnected
            isReady = false
            return
        }

        // If the closed tab was active, switch to a neighbor.
        if wasActive {
            let newIndex = min(index, tabs.count - 1)
            tabs[newIndex].isActive = true
            pendingTabSwitch = tabs[newIndex].tabId
        }
        persistTabIds()
    }

    /// Request to close a tab — shows confirmation dialog.
    func requestCloseTab(id: UUID) {
        pendingCloseTabId = id
        showCloseConfirmation = true
    }

    /// Confirm and execute the pending tab close.
    func confirmCloseTab() {
        guard let tabId = pendingCloseTabId else { return }
        pendingCloseTabId = nil
        closeTab(id: tabId)
    }

    /// Switch to a different tab by its ID.
    func switchTab(id: UUID) {
        guard let targetIndex = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Already active — nothing to do.
        if tabs[targetIndex].isActive { return }

        // Deactivate all, activate target.
        for i in tabs.indices {
            tabs[i].isActive = false
        }
        tabs[targetIndex].isActive = true
        persistTabIds()

        // Signal the web view to disconnect current and connect to the new tab.
        pendingTabSwitch = tabs[targetIndex].tabId
    }

    // MARK: - Relay Configuration

    /// Build the relay WebSocket URL for `/shell/:tabId`.
    var relayURL: String {
        let base = auth.serverURL
        let scheme = base.contains("://") ? "" : "http://"
        // Strip protocol prefix for the host, then decide ws/wss
        let fullBase = "\(scheme)\(base)"
        let wsScheme = fullBase.hasPrefix("https://") ? "wss" : "ws"
        let host = fullBase
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return "\(wsScheme)://\(host)"
    }

    /// The session JWT token for auth.
    var authToken: String? {
        auth.sessionCookie
    }

    /// The relay domain for cookie injection.
    var relayDomain: String {
        let base = auth.serverURL
        let cleaned = base
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        // Strip port if present for cookie domain
        return cleaned.components(separatedBy: ":").first ?? cleaned
    }

    /// Full relay base URL (http/https) for cookie path.
    var relayBaseURL: String {
        let base = auth.serverURL
        let scheme = base.contains("://") ? "" : "http://"
        return "\(scheme)\(base)"
    }

    /// Build the config object to inject into the terminal page via WKUserScript.
    ///
    /// The token is included so the JS layer can use it as a query-param
    /// fallback if cookie auth fails (WKWebView edge cases). The JS side
    /// only appends `?token=` when `config.tokenFallback` is true — by
    /// default cookies are the primary auth path, keeping the JWT out of
    /// URLs/logs/proxies.
    var bridgeConfig: [String: Any] {
        var config: [String: Any] = [
            "relayURL": relayURL,
            "tabId": tabId,
            "theme": themeConfig,
            "fontSize": keybarViewModel.fontSize,
        ]
        if let token = authToken {
            config["token"] = token
            // Token is available for fallback but JS won't use it in the
            // URL by default — see terminal.html's connectWS() gating.
            config["tokenFallback"] = false
        }
        return config
    }

    /// Terminal theme — driven by KeybarViewModel's selected theme.
    var themeConfig: [String: String] {
        selectedTheme.asDictionary
    }

    // MARK: - Bridge Message Handling

    /// Handle a message from the JS bridge.
    func handleBridgeMessage(_ message: TerminalBridgeMessage) {
        switch message {
        case .ready:
            isReady = true

        case .connected(let connectedTabId):
            connectionState = .connected
            // Activate the tab whose tabId matches the relay-confirmed ID.
            // The relay echoes back the tabId on successful connection, so
            // we reconcile by toggling isActive to the matching tab.
            if let index = tabs.firstIndex(where: { $0.tabId == connectedTabId }) {
                for i in tabs.indices {
                    tabs[i].isActive = (i == index)
                }
            }

        case .disconnected(let code, _):
            // Clean close (1000/1001) stays as .disconnected. Transient
            // drops are non-fatal — the JS layer's bounded auto-retry
            // (3 attempts, 500ms→1s→2s) kicks in underneath. We reflect
            // that as .connecting so the error overlay doesn't flash.
            // Only `.retryExhausted` flips to .error.
            if code == 1000 || code == 1001 {
                connectionState = .disconnected
            } else {
                connectionState = .connecting
            }

        case .retryExhausted(let code, let reason):
            connectionState = .error("Disconnected: \(reason) (\(code))")

        case .bell:
            HapticService.impact(.light)

        case .title(let title):
            // Update the active tab's title from xterm title escape sequence.
            let newTitle = title.isEmpty ? "Terminal" : title
            if let index = tabs.firstIndex(where: { $0.isActive }) {
                tabs[index].title = newTitle
            }

        case .selection(let text):
            UIPasteboard.general.string = text

        case .resize(let cols, let rows):
            self.cols = cols
            self.rows = rows
        }
    }

    // MARK: - Copy/Paste

    /// Paste text into the terminal via the JS bridge.
    func pasteText(_ text: String) {
        guard let webView else { return }
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "if(window.MajorTom && window.MajorTom.paste){window.MajorTom.paste(\(json))}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Enable or disable copy/select mode in the terminal.
    /// When enabled, touch interactions in xterm select text instead of scrolling.
    func setCopyMode(_ enabled: Bool) {
        guard let webView else { return }
        let js = """
        if(window.MajorTom && window.MajorTom._term){
          window.MajorTom._term.options.rightClickSelectsWord = \(enabled);
          if(\(enabled)){
            window.MajorTom._term.select(0, window.MajorTom._term.buffer.active.cursorY, window.MajorTom._term.cols);
          } else {
            window.MajorTom._term.clearSelection();
          }
        }
        """
        webView.evaluateJavaScript(js) { _, _ in }
    }

    // MARK: - Orientation / Resize

    /// Trigger a terminal resize via the JS bridge (e.g. after orientation change).
    /// The fit addon recalculates cols/rows based on the new container dimensions.
    func triggerResize() {
        guard let webView else { return }
        let js = "if(window.MajorTom && window.MajorTom.resize){window.MajorTom.resize()}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    // MARK: - Theme & Font

    /// Apply a theme to the live terminal by calling the JS bridge.
    func applyTheme(_ theme: TerminalTheme) {
        guard let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: theme.asDictionary),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "if(window.MajorTom && window.MajorTom.setTheme){window.MajorTom.setTheme(\(json))}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Apply a font size to the live terminal by calling the JS bridge.
    func applyFontSize(_ size: Int) {
        guard let webView else { return }
        let js = "if(window.MajorTom && window.MajorTom.setFontSize){window.MajorTom.setFontSize(\(size))}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    // MARK: - Key Input

    /// Send raw terminal input to the web terminal via the JS bridge.
    ///
    /// This is the primary entry point for the NativeKeybar. The string is
    /// escaped for safe interpolation into a JavaScript snippet and then
    /// passed directly to `window.MajorTom._term.input(..., true)` so the
    /// xterm instance receives the raw bytes without additional key mapping.
    func sendBytes(_ bytes: String) {
        guard let webView else { return }

        // Escape the raw input so it can be safely embedded in the injected
        // JavaScript snippet before passing it through to `term.input()`.
        let escaped = bytes
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        // Use term.input() for raw byte injection -- this handles all escape
        // sequences correctly without the sendKey mapper double-processing them.
        let js = "if(window.MajorTom && window.MajorTom._term){window.MajorTom._term.input('\(escaped)',true)}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Send a named special key to the terminal via the JS bridge.
    /// Uses `MajorTom.sendKey()` which maps key names to escape sequences.
    func sendSpecialKey(_ key: String, ctrl: Bool = false, alt: Bool = false, shift: Bool = false) {
        guard let webView else { return }

        // JSON-encode the key name to safely handle any special characters
        guard let keyData = try? JSONSerialization.data(withJSONObject: key),
              let encodedKey = String(data: keyData, encoding: .utf8) else {
            return
        }

        var parts: [String] = ["key:\(encodedKey)"]
        if ctrl { parts.append("ctrl:true") }
        if alt { parts.append("alt:true") }
        if shift { parts.append("shift:true") }

        let js = "if(window.MajorTom && window.MajorTom.sendKey){window.MajorTom.sendKey({\(parts.joined(separator: ","))})}"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    // MARK: - Lifecycle

    /// Called when the WKWebView content process terminates (memory pressure).
    func handleProcessTermination() {
        didTerminate = true
        connectionState = .disconnected
        isReady = false
    }

    /// Reset after recovering from process termination.
    func resetAfterRecovery() {
        didTerminate = false
        connectionState = .disconnected
        isReady = false
    }
}
