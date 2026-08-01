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

    /// Remove the script message handler on teardown to break the
    /// WKWebView → userContentController → coordinator retain cycle.
    /// Without this, the Coordinator (and transitively the WKWebView)
    /// leaks every time SwiftUI recreates the view.
    ///
    /// Wave 5 memory leak audit:
    /// - Removes the majorTom message handler (breaks WKScriptMessageHandler retain)
    /// - Removes all user scripts (breaks WKUserScript references)
    /// - Nils the navigation delegate (breaks Coordinator ← WKWebView retain)
    /// - Stops loading to cancel any in-flight requests
    /// - Nils the ViewModel's weak webView reference
    /// - Disconnects the JS WebSocket before teardown
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Disconnect the JS WebSocket cleanly before tearing down
        webView.evaluateJavaScript("if(window.MajorTom && window.MajorTom.disconnect){window.MajorTom.disconnect()}") { _, _ in }
        webView.stopLoading()
        let contentController = webView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: "majorTom")
        contentController.removeAllUserScripts()
        webView.navigationDelegate = nil
        // Wave 1 Terminal UX: detach the touch gestures + edit-menu
        // interaction installed by attachTouchGestures(to:). UIKit would
        // tear these down on WKWebView dealloc, but being explicit avoids
        // the coordinator outliving the webview by one runloop and firing
        // a stale arrow-key emission.
        webView.gestureRecognizers?
            .filter { $0.delegate === coordinator }
            .forEach { webView.removeGestureRecognizer($0) }
        if let interaction = coordinator.editMenuInteraction {
            webView.removeInteraction(interaction)
            coordinator.editMenuInteraction = nil
        }
        // Nil the viewModel's weak reference to prevent stale calls
        coordinator.viewModel.webView = nil
        // Break WKWebViewConfiguration → WKUserContentController → Coordinator retain cycle
        webView.configuration.userContentController = WKUserContentController()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register the JS→Swift message handler.
        // The JS side calls: window.webkit.messageHandlers.majorTom.postMessage({...})
        contentController.add(context.coordinator, name: "majorTom")

        // Snapshot the relay endpoint ONCE for this connection attempt (#179).
        // `bestRelayURL` can flip tunnel→verified-LAN across the `await` inside
        // injectAuthCookie; deriving the JS config, the cookie domain, and the
        // secure flag from this single capture keeps the cookie host and the
        // socket host from diverging (which silently breaks /shell auth).
        let relaySnapshot = viewModel.snapshotRelay()

        // Inject the config as a WKUserScript that runs at document start,
        // so it's available before terminal.html's own scripts execute.
        let configJSON = serializeConfig(viewModel.bridgeConfig(for: relaySnapshot))
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

        // Store a weak reference in the view model so the native keybar
        // can forward key taps via evaluateJavaScript.
        viewModel.webView = webView

        // Wave 1 Terminal UX: swipe → arrow keys, long-press → Paste menu.
        // Gestures live on the WKWebView; the Coordinator owns their state
        // and the UIEditMenuInteraction so cleanup happens via dismantleUIView.
        context.coordinator.attachTouchGestures(to: webView)

        // Inject the auth cookie, then load the terminal page. The same
        // snapshot used for the JS config drives the cookie domain/secure
        // flag, so the two can't diverge if a LAN host is verified mid-await.
        Task { @MainActor in
            await injectAuthCookie(into: dataStore, relay: relaySnapshot)
            loadTerminalPage(webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // If the web content process terminated, reload.
        if viewModel.didTerminate {
            viewModel.resetAfterRecovery()
            loadTerminalPage(webView)
            return
        }

        // Tab switch: connect to the new tabId (connect() already closes the
        // existing WS internally, so we skip disconnect() to avoid poisoning
        // the reconnect counter).
        if let newTabId = viewModel.pendingTabSwitch {
            let escaped = newTabId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            // Call connect() directly — it closes the old socket and resets
            // reconnect state. Return true/false so we know if MajorTom was
            // available; only consume the pending switch on success.
            let js = """
            if(window.MajorTom){
              window.MajorTom.connect({tabId:'\(escaped)'});
              true;
            } else {
              false;
            }
            """
            webView.evaluateJavaScript(js) { result, error in
                guard error == nil, let didSwitch = result as? Bool, didSwitch else {
                    return
                }
                // Only clear the pending switch after the JS bridge confirmed
                // the reconnect path was invoked.
                if viewModel.pendingTabSwitch == newTabId {
                    viewModel.pendingTabSwitch = nil
                }
                viewModel.connectionState = .connecting
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Cookie Injection

    /// Inject the session JWT as an HTTPCookie into the WKWebsiteDataStore.
    /// This is the primary auth mechanism for the WebSocket connection.
    /// Cookie expiry matches the relay's 7-day JWT lifetime so reconnects
    /// don't fail with a dropped cookie while the token is still valid.
    ///
    /// The `relay` snapshot is captured once per connection attempt in
    /// `makeUIView` (#179) so the cookie's domain/secure flag are derived from
    /// the same host the `/shell` socket dials — they can't diverge even if a
    /// LAN host is verified during the `await` below.
    private func injectAuthCookie(
        into dataStore: WKWebsiteDataStore,
        relay: TerminalViewModel.RelaySnapshot
    ) async {
        guard let token = viewModel.authToken else { return }

        var cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: "mt-session",
            .value: token,
            .domain: relay.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(7 * 24 * 60 * 60), // 7 days — matches relay JWT lifetime
        ]

        // Mark secure when relay uses HTTPS/WSS; omit for local http/ws dev.
        if relay.isSecure {
            cookieProperties[.secure] = "TRUE"
        }

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

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate {
        /// Exposed (not private) so `dismantleUIView` can nil the viewModel's
        /// weak webView reference during teardown to prevent stale calls.
        let viewModel: TerminalViewModel

        // MARK: - Wave 1 Touch Gestures

        /// Locked axis for the active pan — set on first significant
        /// movement and cleared on gesture end. Prevents diagonal drags
        /// from spraying mixed arrow keys.
        fileprivate enum PanAxis { case horizontal, vertical }
        private var panAxis: PanAxis?

        /// Cumulative translation at the moment of the most recent arrow
        /// emission. Subtracting from the current translation gives the
        /// delta since the last emission, so emission rate stays uniform
        /// across the full drag.
        private var lastEmittedTranslation: CGPoint = .zero

        /// Owned interaction so dismantleUIView can detach it cleanly.
        var editMenuInteraction: UIEditMenuInteraction?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        /// Install the pan + long-press recognizers and the edit-menu
        /// interaction. Called once from `makeUIView`; teardown is mirrored
        /// in `dismantleUIView`.
        func attachTouchGestures(to webView: WKWebView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTerminalPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            webView.addGestureRecognizer(pan)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTerminalLongPress(_:)))
            longPress.minimumPressDuration = 0.5
            longPress.delegate = self
            webView.addGestureRecognizer(longPress)

            let interaction = UIEditMenuInteraction(delegate: self)
            webView.addInteraction(interaction)
            editMenuInteraction = interaction
        }

        /// Pan handler — converts dominant-axis movement into a stream of
        /// arrow-key bytes. Each ~one-character step along the locked axis
        /// emits one key, so a slow drag scrolls smoothly and a quick flick
        /// emits a burst. Sends batched escape sequences to minimise
        /// JS-bridge round-trips.
        @MainActor
        @objc func handleTerminalPan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began:
                panAxis = nil
                lastEmittedTranslation = .zero

            case .changed:
                let dx = translation.x - lastEmittedTranslation.x
                let dy = translation.y - lastEmittedTranslation.y
                // Steps roughly match the rendered glyph metrics so drag
                // distance lines up with on-screen movement. Monospace
                // glyphs are ~0.6 the height of their em-square.
                let fontSize = CGFloat(viewModel.keybarViewModel.fontSize)
                let verticalStep = max(16, fontSize * 1.2)
                let horizontalStep = max(10, fontSize * 0.65)

                if panAxis == nil {
                    // Wait until movement on either axis crosses the
                    // vertical step before committing — keeps small jitters
                    // from picking the wrong axis.
                    if abs(dx) < verticalStep && abs(dy) < verticalStep { return }
                    panAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                }

                guard let axis = panAxis else { return }
                switch axis {
                case .vertical:
                    let steps = Int(dy / verticalStep)
                    if steps == 0 { return }
                    // Drag down → cursor down (\e[B); drag up → cursor up (\e[A).
                    let key = steps < 0 ? "\u{1B}[A" : "\u{1B}[B"
                    viewModel.sendBytes(String(repeating: key, count: abs(steps)))
                    lastEmittedTranslation.y += CGFloat(steps) * verticalStep
                case .horizontal:
                    let steps = Int(dx / horizontalStep)
                    if steps == 0 { return }
                    let key = steps < 0 ? "\u{1B}[D" : "\u{1B}[C"
                    viewModel.sendBytes(String(repeating: key, count: abs(steps)))
                    lastEmittedTranslation.x += CGFloat(steps) * horizontalStep
                }

            case .ended, .cancelled, .failed:
                panAxis = nil
                lastEmittedTranslation = .zero

            default:
                break
            }
        }

        /// Long-press handler — surface the system Paste menu at the press
        /// location. Selection / Copy will land in Wave 2; this round only
        /// adds Paste so users stop relying on the keybar long-press as
        /// the only paste path.
        @MainActor
        @objc func handleTerminalLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            guard let interaction = editMenuInteraction else { return }
            let location = recognizer.location(in: recognizer.view)
            // Tactile confirmation that the long-press crossed the threshold and
            // the Paste menu is appearing. `.medium` matches the app's menu/mode
            // feedback; the lighter tap-confirmation haptic fires on Paste itself.
            // Gated on the same `hasStrings` check the menu delegate uses — with
            // an empty pasteboard it returns an empty menu (nothing renders), so
            // an unconditional buzz would promise UI that never shows.
            if UIPasteboard.general.hasStrings {
                HapticService.impact(.medium)
            }
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
            interaction.presentEditMenu(with: configuration)
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

        // MARK: - UIGestureRecognizerDelegate

        /// Run alongside the WKWebView's own recognizers so single taps still
        /// reach the focus path (which raises the keyboard). Our pan only
        /// engages once translation crosses its step threshold, and the long-
        /// press only fires after 0.5s — neither competes with a quick tap.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

    }
}

// MARK: - UIEditMenuInteractionDelegate
//
// Pulled out into its own `@preconcurrency` extension because the protocol
// itself isn't `@MainActor`-isolated in the iOS 17 SDK headers, so adding it
// to the class declaration triggers a Swift 6 actor-isolation warning. UIKit
// always invokes this delegate on the main thread in practice, so `@MainActor`
// on the method is safe — `@preconcurrency` tells the compiler to relax the
// strict-Swift-6 conformance check for this one protocol.
extension TerminalWebView.Coordinator: @preconcurrency UIEditMenuInteractionDelegate {
    @MainActor
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard UIPasteboard.general.hasStrings else { return UIMenu(children: []) }
        // `identifier: .paste` is load-bearing, not cosmetic. Reading
        // `UIPasteboard.general.string` programmatically trips the iOS 16
        // "Allow Paste?" modal; the system waives it only for UIPasteControl,
        // the standard `paste(_:)` responder command, or — as here — a
        // UIAction tagged with the standard paste identifier. UIPasteControl
        // is a UIView and can't live inside a UIMenu, so this identifier is
        // the only exemption available on this path. Without it, tapping
        // "Don't Allow" makes the `guard let text` below fail silently, which
        // is indistinguishable from the dead-paste bug this file just fixed.
        let paste = UIAction(
            title: "Paste",
            image: UIImage(systemName: "doc.on.clipboard"),
            identifier: .paste
        ) { [weak self] _ in
            guard let self,
                  let text = UIPasteboard.general.string,
                  !text.isEmpty else { return }
            self.viewModel.pasteText(text)
            HapticService.impact(.light)
        }
        return UIMenu(children: [paste])
    }
}
