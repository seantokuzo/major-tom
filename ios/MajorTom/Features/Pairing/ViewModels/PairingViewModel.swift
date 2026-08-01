import Foundation

// MARK: - Server Presets

/// Relay URL targets picked from the device's current reachability.
/// LAN deliberately falls through to the public tunnel — Bonjour
/// discovery (see `currentRelayURL`) takes precedence when an mDNS
/// broadcast is visible, so the tunnel is only used as a safety net
/// when Bonjour can't see the relay (mDNS blocked, Mac asleep).
enum ServerPreset {
    case cloudflare
    case tailscale

    var address: String {
        switch self {
        case .cloudflare: return Secrets.tunnelURL
        case .tailscale:  return Secrets.tailscaleAddress
        }
    }

    init?(reachability: NetworkPathMonitor.Reachability) {
        switch reachability {
        case .tailscale: self = .tailscale
        case .lan:       self = .cloudflare
        case .cellular:  self = .cloudflare
        case .offline:   return nil
        }
    }
}

@Observable
@MainActor
final class PairingViewModel {
    var authMethods: AuthMethods?
    var isFetchingMethods = false
    /// Google iOS OAuth client ID surfaced by the relay (`/auth/google/client-id`).
    /// `nil` when the relay hasn't enabled iOS Google auth — the Google
    /// button stays hidden in that case rather than offering a broken flow.
    var googleIOSClientID: String?
    /// Set while the Google OAuth sheet is presented or the relay is
    /// exchanging the ID token. Drives the spinner on the Google button.
    var isSigningInWithGoogle = false

    private let auth: AuthService
    private let network: NetworkPathMonitor
    private let browser: BonjourBrowser
    private let googleOAuth: GoogleOAuthService

    init(
        auth: AuthService,
        network: NetworkPathMonitor? = nil,
        browser: BonjourBrowser? = nil,
        googleOAuth: GoogleOAuthService? = nil
    ) {
        self.auth = auth
        self.network = network ?? NetworkPathMonitor()
        self.browser = browser ?? BonjourBrowser()
        self.googleOAuth = googleOAuth ?? GoogleOAuthService()
    }

    var authState: AuthState { auth.authState }
    var isPairing: Bool { authState == .pairing }
    var isPaired: Bool { authState.isPaired }

    var errorMessage: String? {
        if case .error(let msg) = authState { return msg }
        return nil
    }

    /// Whether Google sign-in is offerable in the UI — relay must have Google
    /// auth enabled AND have an iOS client ID configured. The iOS app can't
    /// run the flow without a client ID, so we hide the button instead of
    /// surfacing a broken state.
    var isGoogleEnabled: Bool {
        (authMethods?.google ?? false) && (googleIOSClientID?.isEmpty == false)
    }

    /// Resolve the relay URL at call-time:
    /// 1. First Bonjour-discovered service if any (lowest latency on LAN).
    /// 2. Reachability-driven preset (Tailscale on VPN, tunnel otherwise).
    /// 3. Tunnel hostname as a final safety net so signin never has nothing to hit.
    var currentRelayURL: String {
        if let discovered = browser.services.first {
            return discovered.address
        }
        if let preset = ServerPreset(reachability: network.reachability) {
            return preset.address
        }
        return Secrets.tunnelURL
    }

    /// Start mDNS discovery. Idempotent — safe to call repeatedly on
    /// view appear. The pairing UI no longer surfaces the discovered
    /// services, but they still drive `currentRelayURL` so an on-LAN
    /// relay is preferred over the tunnel.
    ///
    /// There is no matching `stop` — the browser is the app-level one and
    /// `MajorTomApp`'s scenePhase handler owns its teardown. Stopping it when
    /// this view disappears would wipe the discovery cache at the exact moment
    /// pairing succeeds and `RelayURLResolver` needs it (#183).
    func startDiscovery() {
        browser.start()
    }

    /// Fetch auth methods from the relay to adapt the login UI.
    /// Also fetches the Google client-id payload when Google is enabled so
    /// the iOS app knows whether the relay is set up for native sign-in.
    func fetchAuthMethods() async {
        let target = currentRelayURL
        guard !target.isEmpty else { return }

        isFetchingMethods = true
        defer { isFetchingMethods = false }

        let baseURL = AuthService.normalizeBaseURL(target)
        guard let url = URL(string: "\(baseURL)/auth/methods") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }
            authMethods = try JSONDecoder().decode(AuthMethods.self, from: data)
        } catch {
            authMethods = nil
        }

        if authMethods?.google == true {
            await fetchGoogleClientID(baseURL: baseURL)
        } else {
            googleIOSClientID = nil
        }
    }

    /// Pull the relay's iOS Google client ID. Optional endpoint — older
    /// relays don't return `iosClientId`, in which case the Google button
    /// stays hidden and the user sees the "Google sign-in not available"
    /// fallback.
    private func fetchGoogleClientID(baseURL: String) async {
        guard let url = URL(string: "\(baseURL)/auth/google/client-id") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                googleIOSClientID = nil
                return
            }
            let payload = try JSONDecoder().decode(GoogleClientIDResponse.self, from: data)
            let trimmed = payload.iosClientId?.trimmingCharacters(in: .whitespacesAndNewlines)
            googleIOSClientID = (trimmed?.isEmpty == false) ? trimmed : nil
        } catch {
            googleIOSClientID = nil
        }
    }

    private struct GoogleClientIDResponse: Decodable {
        let clientId: String?
        let iosClientId: String?
    }

    /// Run the full Google sign-in flow: present the OAuth sheet, exchange
    /// the auth code for an ID token, then exchange the ID token for a
    /// relay session cookie. Pre-flights reachability so we surface
    /// "Server unreachable at <URL>" instead of "Connection failed" when
    /// the auto-picked relay can't be reached.
    func signInWithGoogle() async {
        let target = currentRelayURL
        guard !target.isEmpty else { return }
        guard let clientID = googleIOSClientID, !clientID.isEmpty else {
            auth.authState = .error("Relay isn't configured for iOS Google sign-in")
            return
        }

        if !(await reachable(target)) {
            auth.authState = .error("Server unreachable at \(target). Check your network or relay status.")
            HapticService.deny()
            return
        }

        auth.saveServerURL(target)
        isSigningInWithGoogle = true
        defer { isSigningInWithGoogle = false }

        do {
            let idToken = try await googleOAuth.signIn(iosClientID: clientID)
            await auth.signInWithGoogle(idToken: idToken)
            if auth.isPaired {
                HapticService.celebrate()
            } else {
                HapticService.deny()
            }
        } catch GoogleOAuthError.userCanceled {
            // Silent — the user dismissed the sheet on purpose.
        } catch {
            auth.authState = .error(error.localizedDescription)
            HapticService.deny()
        }
    }

    // MARK: - Helpers

    /// 2-second probe against `/auth/methods`. Returns `true` for any
    /// HTTP response (including 4xx/5xx) — only transport errors mean
    /// unreachable. A reachable-but-broken server still gets the user
    /// past the targeted "Server unreachable at <URL>" message into the
    /// sign-in path where downstream errors carry more detail.
    private func reachable(_ address: String) async -> Bool {
        let baseURL = AuthService.normalizeBaseURL(address)
        guard let url = URL(string: "\(baseURL)/auth/methods") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
