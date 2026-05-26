import Foundation

/// Resolves the best relay base URL to connect to *at connect time*,
/// preferring a live Bonjour-discovered LAN address over the frozen
/// `auth.serverURL` (the tunnel/last-used host captured at login).
///
/// Login freezes one URL into `auth.serverURL`. On Wi-Fi that's often the
/// public Cloudflare tunnel — Bonjour can be racy at the moment of the
/// sign-in tap — so every later connection needlessly rode the tunnel.
/// Keeping an app-level `BonjourBrowser` alive and consulting it here lets
/// the main socket and the terminal `/shell` socket prefer the LAN whenever
/// the relay is reachable locally, falling back to the tunnel only when
/// there's genuinely no local path (cellular/remote).
@Observable
@MainActor
final class RelayURLResolver {
    private let auth: AuthService
    private let browser: BonjourBrowser

    init(auth: AuthService, browser: BonjourBrowser) {
        self.auth = auth
        self.browser = browser
    }

    /// Best relay base URL right now: a live LAN address if Bonjour has
    /// discovered one, else the frozen `auth.serverURL`. Returned in the
    /// same raw `host[:port]` / hostname form as `auth.serverURL`, so
    /// callers keep running it through `AuthService.normalizeBaseURL`.
    var bestRelayURL: String {
        browser.services.first?.address ?? auth.serverURL
    }

    /// Resolve preferring the LAN, giving Bonjour a brief window to answer.
    /// Returns the moment a LAN service is known (typical on a quiet home
    /// network) and caps the wait at `timeout`, so a relay-less network
    /// (cellular/remote) pays the delay at most once before falling back to
    /// the tunnel. Idempotently starts discovery if it isn't already running.
    func resolvePreferringLAN(timeout: Duration = .seconds(2)) async -> String {
        if let lan = browser.services.first?.address { return lan }
        browser.start()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            if let lan = browser.services.first?.address { return lan }
        }
        return auth.serverURL
    }
}
