import Foundation

@Observable
@MainActor
final class PairingViewModel {
    var pin: String = ""
    var serverAddress: String = ""
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
        self.serverAddress = auth.serverURL
    }

    var authState: AuthState { auth.authState }
    var isPairing: Bool { authState == .pairing }
    var isPaired: Bool { authState.isPaired }

    var errorMessage: String? {
        if case .error(let msg) = authState { return msg }
        return nil
    }

    var canSubmit: Bool {
        pin.count == 6 && !isPairing
    }

    /// Whether PIN auth is available (or auth methods haven't been fetched yet).
    var isPinEnabled: Bool {
        authMethods?.pin ?? true
    }

    /// Whether Google sign-in is offerable in the UI — relay must have Google
    /// auth enabled AND have an iOS client ID configured. The iOS app can't
    /// run the flow without a client ID, so we hide the button instead of
    /// surfacing a broken state.
    var isGoogleEnabled: Bool {
        (authMethods?.google ?? false) && (googleIOSClientID?.isEmpty == false)
    }

    /// Whether any auth method is available.
    var hasAnyAuthMethod: Bool {
        guard let methods = authMethods else { return true }
        return methods.pin || methods.google
    }

    /// Live list of relays discovered on the local network via Bonjour
    /// (`_majortom._tcp`). Empty when offline, browsing hasn't started,
    /// or local-network permission has been denied.
    var discoveredServices: [BonjourBrowser.DiscoveredService] {
        browser.services
    }

    /// Whether Bonjour discovery is actively browsing (`false` after
    /// stop or permission denial).
    var isBrowsing: Bool {
        browser.isBrowsing
    }

    /// Start mDNS discovery. Idempotent — safe to call repeatedly on
    /// view appear. Wraps the Bonjour service to preserve MVVM so the
    /// view doesn't reach into the discovery service directly.
    func startDiscovery() {
        browser.start()
    }

    /// Stop mDNS discovery and tear down active resolvers. Called on
    /// view disappear.
    func stopDiscovery() {
        browser.stop()
    }

    /// Single preset matched to the phone's current reachability — `nil`
    /// when offline or before the path monitor has fired its first update.
    var recommendedPreset: ServerPreset? {
        ServerPreset(reachability: network.reachability)
    }

    /// Apply the auto-picked URL and refetch auth methods.
    func useRecommended() async {
        guard let preset = recommendedPreset else { return }
        await applyAddress(preset.address)
    }

    /// Apply a Bonjour-discovered relay and refetch auth methods.
    func useDiscovered(_ service: BonjourBrowser.DiscoveredService) async {
        await applyAddress(service.address)
    }

    /// On first appear, if the user has no saved server URL, seed the field
    /// with the first discovered service if one exists, falling back to the
    /// path monitor's recommendation. Subsequent reachability changes do
    /// NOT auto-overwrite — the user can tap a chip to refresh on demand.
    func applyInitialRecommendationIfNeeded() {
        guard serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let discovered = discoveredServices.first {
            serverAddress = discovered.address
            return
        }
        if let preset = recommendedPreset {
            serverAddress = preset.address
        }
    }

    /// Fetch auth methods from the relay to adapt the login UI.
    /// Also fetches the Google client-id payload when Google is enabled so
    /// the iOS app knows whether the relay is set up for native sign-in.
    func fetchAuthMethods() async {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isFetchingMethods = true
        defer { isFetchingMethods = false }

        let baseURL = AuthService.normalizeBaseURL(trimmed)
        guard let url = URL(string: "\(baseURL)/auth/methods") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }
            authMethods = try JSONDecoder().decode(AuthMethods.self, from: data)
        } catch {
            // Older relays may not have this endpoint — show all methods
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
    /// stays hidden and the user falls back to PIN.
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
    /// the user picked a stale chip.
    func signInWithGoogle() async {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let clientID = googleIOSClientID, !clientID.isEmpty else {
            auth.authState = .error("Relay isn't configured for iOS Google sign-in")
            return
        }

        if !(await reachable(trimmed)) {
            auth.authState = .error("Server unreachable at \(trimmed). Pick a different relay or check your network.")
            HapticService.deny()
            return
        }

        auth.saveServerURL(trimmed)
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

    func submitPIN() async {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Pre-flight reachability ping — turns silent "Connection failed" into
        // a specific "Server unreachable at <URL>" so the user knows whether
        // to fix the URL or the PIN.
        if !(await reachable(trimmed)) {
            auth.authState = .error("Server unreachable at \(trimmed). Pick a different relay or check your network.")
            HapticService.deny()
            return
        }

        auth.saveServerURL(trimmed)
        await auth.pair(pin: pin)

        if auth.isPaired {
            HapticService.celebrate()
        } else {
            HapticService.deny()
            pin = ""
        }
    }

    func appendDigit(_ digit: String) {
        guard pin.count < 6 else { return }
        pin += digit
        HapticService.buttonTap()
    }

    func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
        HapticService.buttonTap()
    }

    func clearPIN() {
        pin = ""
    }

    // MARK: - Helpers

    private func applyAddress(_ address: String) async {
        serverAddress = address
        // Surface "Server unreachable at <URL>" on chip-tap the same way
        // submitPIN does — keeps the spec's targeted error path consistent
        // whether the user reaches the relay via chip or PIN submit.
        if !(await reachable(address)) {
            auth.authState = .error("Server unreachable at \(address). Pick a different relay or check your network.")
            return
        }
        await fetchAuthMethods()
    }

    /// 2-second probe against `/auth/methods`. Returns `true` for any
    /// HTTP response (including 4xx/5xx) — only transport errors mean
    /// unreachable. A reachable-but-broken server still gets the user
    /// past the targeted "Server unreachable at <URL>" message into the
    /// PIN-exchange path where downstream errors carry more detail.
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
