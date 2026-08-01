import Foundation

// MARK: - Server Presets

/// Relay URL targets picked from the device's current reachability.
/// LAN deliberately falls through to the public tunnel: pre-pairing there is no
/// pinned relay identity to challenge a discovered host against, so an mDNS
/// responder can never be trusted here. LAN preference is applied *after*
/// pairing, by `RelayURLResolver`, where the Ed25519 challenge-response gate
/// exists. See `currentRelayURL`.
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

    /// `browser` is **required** and must be the app-level `BonjourBrowser`.
    /// A private instance would warm a cache `RelayURLResolver` never reads,
    /// silently reintroducing #183 with no compile error — and, since this type
    /// no longer has a `stopDiscovery`, would browse with no teardown path at
    /// all. Making it non-optional makes that mistake unrepresentable.
    init(
        auth: AuthService,
        browser: BonjourBrowser,
        network: NetworkPathMonitor? = nil,
        googleOAuth: GoogleOAuthService? = nil
    ) {
        self.auth = auth
        self.browser = browser
        self.network = network ?? NetworkPathMonitor()
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

    /// Resolve the relay URL for the *pre-pairing* flow:
    /// 1. Reachability-driven preset (Tailscale on VPN, tunnel otherwise).
    /// 2. Tunnel hostname as a final safety net so signin never has nothing to hit.
    ///
    /// SECURITY: deliberately **not** Bonjour-derived. Before pairing there is no
    /// pinned relay identity, so `RelayIdentityVerifier` cannot challenge a
    /// discovered host and any LAN peer advertising `_majortom._tcp` could be the
    /// first responder — it would serve `/auth/methods`, hand back *its own*
    /// Google `iosClientId`, and receive the resulting ID token (which
    /// `signInWithGoogle` POSTs to this same host after freezing it into
    /// `auth.serverURL`). Sharing the app-level browser (#183) keeps
    /// `browser.services` warm by the time this view runs, which is exactly what
    /// made that first-responder shortcut reachable. LAN preference belongs after
    /// pairing, in `RelayURLResolver`, where the challenge-response gate exists.
    var currentRelayURL: String {
        if let preset = ServerPreset(reachability: network.reachability) {
            return preset.address
        }
        return Secrets.tunnelURL
    }

    /// Start mDNS discovery. Idempotent — safe to call repeatedly on view appear.
    /// Nothing in the pairing flow *consumes* discovery (see `currentRelayURL`);
    /// this exists purely to guarantee the app-level browser is warm before
    /// sign-in flips `isPaired`, since that transition is what fires the first
    /// `RelayURLResolver.resolvePreferringLAN` (#183).
    ///
    /// There is no matching `stop` — the browser is the app-level one and
    /// `MajorTomApp`'s scenePhase handler owns its teardown. Stopping it when
    /// this view disappears would wipe the discovery cache at the exact moment
    /// pairing succeeds and `RelayURLResolver` needs it.
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
