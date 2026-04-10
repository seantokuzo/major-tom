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

    /// The active tab ID for the tmux window.
    /// Derived from the active tab in the `tabs` array.
    var tabId: String {
        activeTab?.tabId ?? "default"
    }

    /// Terminal title (set by xterm title escape sequence).
    /// Derived from the active tab's title.
    var terminalTitle: String {
        activeTab?.title ?? "Terminal"
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

    init(auth: AuthService) {
        self.auth = auth
        self.keybarViewModel = KeybarViewModel(auth: auth)
        // Create the initial default tab.
        let initialTab = TerminalTab(title: "Terminal", isActive: true)
        self.tabs = [initialTab]
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

        // Signal the web view to connect to the new tab.
        pendingTabSwitch = newTab.tabId
    }

    /// Close a tab by its ID.
    ///
    /// If the closed tab was active, switches to the nearest neighbor.
    /// If it was the last tab, creates a fresh one (never zero tabs).
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = tabs[index].isActive
        tabs.remove(at: index)

        // Never allow zero tabs — create a fresh one.
        if tabs.isEmpty {
            let newTab = TerminalTab(title: "Terminal", isActive: true)
            tabs.append(newTab)
            pendingTabSwitch = newTab.tabId
            return
        }

        // If the closed tab was active, switch to a neighbor.
        if wasActive {
            let newIndex = min(index, tabs.count - 1)
            tabs[newIndex].isActive = true
            pendingTabSwitch = tabs[newIndex].tabId
        }
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

        case .disconnected(let code, let reason):
            connectionState = .disconnected
            if code != 1000 && code != 1001 {
                connectionState = .error("Disconnected: \(reason) (\(code))")
            }

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
