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
    var tabId: String = "default"

    /// Terminal title (set by xterm title escape sequence).
    var terminalTitle: String = "Terminal"

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

    /// Reference to the auth service for relay URL and token.
    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
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
        ]
        if let token = authToken {
            config["token"] = token
            // Token is available for fallback but JS won't use it in the
            // URL by default — see terminal.html's connectWS() gating.
            config["tokenFallback"] = false
        }
        return config
    }

    /// Terminal theme matching MajorTom dark theme.
    var themeConfig: [String: String] {
        [
            "background": "#0d0d12",
            "foreground": "#e8e8e8",
            "cursor": "#f2a641",
            "cursorAccent": "#0d0d12",
            "selectionBackground": "#f2a64140",
            "black": "#1a1a24",
            "red": "#f24d4d",
            "green": "#4dd97a",
            "yellow": "#f2cc33",
            "blue": "#4d8af2",
            "magenta": "#b84df2",
            "cyan": "#4dd9d9",
            "white": "#e8e8e8",
            "brightBlack": "#666680",
            "brightRed": "#f27a7a",
            "brightGreen": "#7ae89e",
            "brightYellow": "#f2d966",
            "brightBlue": "#7ab3f2",
            "brightMagenta": "#cc7af2",
            "brightCyan": "#7ae8e8",
            "brightWhite": "#ffffff",
        ]
    }

    // MARK: - Bridge Message Handling

    /// Handle a message from the JS bridge.
    func handleBridgeMessage(_ message: TerminalBridgeMessage) {
        switch message {
        case .ready:
            isReady = true

        case .connected(let tabId):
            self.tabId = tabId
            connectionState = .connected

        case .disconnected(let code, let reason):
            connectionState = .disconnected
            if code != 1000 && code != 1001 {
                connectionState = .error("Disconnected: \(reason) (\(code))")
            }

        case .bell:
            HapticService.impact(.light)

        case .title(let title):
            terminalTitle = title.isEmpty ? "Terminal" : title

        case .selection(let text):
            UIPasteboard.general.string = text

        case .resize(let cols, let rows):
            self.cols = cols
            self.rows = rows
        }
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
