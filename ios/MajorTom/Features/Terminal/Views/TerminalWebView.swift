import SwiftUI
import WebKit

/// UIViewRepresentable wrapping a WKWebView that loads the bundled terminal.html.
///
/// Responsibilities:
/// - Creates WKWebViewConfiguration with WKUserContentController
/// - Registers `majorTom` message handler (WKScriptMessageHandler)
/// - Injects config via WKUserScript (relay URL, auth token, tab ID, theme)
/// - Cookie injection for auth (session JWT into WKWebsiteDataStore)
/// - Handles webViewWebContentProcessDidTerminate for recovery
/// - Routes bridge messages to TerminalViewModel
struct TerminalWebView: UIViewRepresentable {
    let viewModel: TerminalViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register the JS→Swift message handler.
        // The JS side calls: window.webkit.messageHandlers.majorTom.postMessage({...})
        contentController.add(context.coordinator, name: "majorTom")

        // Inject the config as a WKUserScript that runs at document start,
        // so it's available before terminal.html's own scripts execute.
        let configJSON = serializeConfig(viewModel.bridgeConfig)
        let configScript = WKUserScript(
            source: "window.__MAJOR_TOM_CONFIG__ = \(configJSON);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(configScript)

        config.userContentController = contentController

        // Allow inline media playback (bell sounds, if ever added)
        config.allowsInlineMediaPlayback = true

        // Use a non-persistent data store so we can inject cookies cleanly.
        // This avoids stale cookies from previous sessions leaking in.
        let dataStore = WKWebsiteDataStore.nonPersistent()
        config.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)

        // Disable the web inspector in production; enable in debug.
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Inject the auth cookie, then load the terminal page.
        Task { @MainActor in
            await injectAuthCookie(into: dataStore)
            loadTerminalPage(webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // If the web content process terminated, reload.
        if viewModel.didTerminate {
            viewModel.resetAfterRecovery()
            loadTerminalPage(webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Cookie Injection

    /// Inject the session JWT as an HTTPCookie into the WKWebsiteDataStore.
    /// This is the primary auth mechanism for the WebSocket connection.
    private func injectAuthCookie(into dataStore: WKWebsiteDataStore) async {
        guard let token = viewModel.authToken else { return }

        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: "mt-session",
            .value: token,
            .domain: viewModel.relayDomain,
            .path: "/",
            .secure: "FALSE",
            .expires: Date().addingTimeInterval(86400), // 24h
        ]

        guard let cookie = HTTPCookie(properties: cookieProperties) else { return }
        await dataStore.httpCookieStore.setCookie(cookie)
    }

    // MARK: - Page Loading

    /// Load the bundled terminal.html from the app bundle.
    private func loadTerminalPage(_ webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(
            forResource: "terminal",
            withExtension: "html",
            subdirectory: nil
        ) else {
            // Try alternative bundle path (Xcode sometimes nests resources)
            if let altURL = Bundle.main.url(forResource: "terminal", withExtension: "html") {
                webView.loadFileURL(altURL, allowingReadAccessTo: altURL.deletingLastPathComponent())
                return
            }
            return
        }

        // Allow read access to the directory so xterm.js/css can be loaded.
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }

    // MARK: - Config Serialization

    /// Serialize the bridge config dictionary to a JSON string for injection.
    private func serializeConfig(_ config: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let viewModel: TerminalViewModel

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        // MARK: - WKScriptMessageHandler

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "majorTom" else { return }
            guard let bridgeMessage = TerminalBridgeMessage.parse(message.body) else { return }
            viewModel.handleBridgeMessage(bridgeMessage)
        }

        // MARK: - WKNavigationDelegate

        @MainActor
        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            // Page loaded — the JS will send a "ready" message when xterm is initialized.
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            viewModel.connectionState = .error("Page load failed: \(error.localizedDescription)")
        }

        @MainActor
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS killed the WKWebView render process under memory pressure.
            // Signal the view model to show recovery UI and reload on next update.
            viewModel.handleProcessTermination()
        }
    }
}
