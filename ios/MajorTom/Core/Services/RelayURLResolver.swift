import Foundation

/// Resolves the best relay base URL to connect to *at connect time*,
/// preferring a Bonjour-discovered LAN host over the frozen `auth.serverURL`
/// (the tunnel/last-used host captured at login) — but ONLY after that host
/// proves it is the relay we paired with.
///
/// Login freezes one URL into `auth.serverURL`. On Wi-Fi that's often the
/// public Cloudflare tunnel — Bonjour can be racy at the moment of the
/// sign-in tap — so every later connection needlessly rode the tunnel.
/// Keeping an app-level `BonjourBrowser` alive and consulting it here lets
/// the main socket and the terminal `/shell` socket prefer the LAN whenever
/// the relay is reachable locally, falling back to the tunnel when there's no
/// local path (cellular/remote) OR when a discovered host fails identity
/// verification.
///
/// SECURITY: mDNS is unauthenticated, so a LAN peer can advertise
/// `_majortom._tcp` and be the "first responder." Handing it the session
/// cookie would let it replay the cookie to the real relay and get a shell.
/// We therefore challenge a discovered host to sign a fresh nonce with the
/// relay identity key (pinned at pairing) and verify it before trusting it —
/// see `RelayIdentityVerifier`.
@Observable
@MainActor
final class RelayURLResolver {
    private let auth: AuthService
    private let browser: BonjourBrowser

    /// A LAN address proven THIS SESSION to belong to the pinned relay identity
    /// via challenge-response. Only this — never an unverified mDNS responder —
    /// is handed to the cookie-bearing connections.
    private var verifiedLANAddress: String?

    init(auth: AuthService, browser: BonjourBrowser) {
        self.auth = auth
        self.browser = browser
        #if DEBUG
        // Trip immediately if our crypto / signed-byte construction ever drifts
        // from the relay (verifies a real relay-produced signature).
        RelayIdentityVerifier.runSelfTest()
        #endif
    }

    /// Best relay base URL for a *synchronous* caller (e.g. the terminal
    /// building its `/shell` URL): a LAN host we already verified this session
    /// AND that is still being advertised, else the frozen `auth.serverURL`
    /// (tunnel). Never returns an unverified host — verification happens only in
    /// the async `resolvePreferringLAN`. Returned in the same raw `host[:port]`
    /// form as `auth.serverURL`, so callers keep normalizing via `AuthService`.
    var bestRelayURL: String {
        if let verified = verifiedLANAddress,
           browser.services.contains(where: { $0.address == verified }) {
            return verified
        }
        return auth.serverURL
    }

    /// Resolve preferring the LAN, but only after proving a discovered host is
    /// the relay we paired with. Gives Bonjour a brief window to answer, then
    /// for each discovered host fast-filters on the advertised fingerprint and
    /// challenges it to sign a fresh nonce (`RelayIdentityVerifier`). The first
    /// host that returns a valid signature against the pinned key is cached and
    /// returned; otherwise we fall back to the tunnel. With no pinned identity
    /// (paired against a relay that predates `/identity`) we never trust a LAN
    /// host and always return the tunnel. Idempotently starts discovery.
    func resolvePreferringLAN(timeout: Duration = .seconds(2)) async -> String {
        // Re-use a still-advertised verified host without re-challenging.
        if let verified = verifiedLANAddress,
           browser.services.contains(where: { $0.address == verified }) {
            return verified
        }
        verifiedLANAddress = nil

        guard let pinned = KeychainService.load(.relayPublicKey),
              let pinnedRaw = RelayIdentityVerifier.data(fromBase64url: pinned) else {
            return auth.serverURL
        }
        let expectedFingerprint = RelayIdentityVerifier.fingerprint(forRawPublicKey: pinnedRaw)

        browser.start()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var challenged: Set<String> = []

        while true {
            // `browser.services` is snapshotted per for-loop; hosts that appear
            // during an await are picked up on the next outer pass. `challenged`
            // prevents re-issuing a challenge to the same address.
            for service in browser.services where !challenged.contains(service.address) {
                challenged.insert(service.address)
                // A mismatched advertised fingerprint can't be our relay — skip
                // the round-trip. A *missing* fingerprint is still challenged;
                // the signature, not the fingerprint, is the trust anchor.
                if let fp = service.fingerprint, fp != expectedFingerprint { continue }
                let base = AuthService.normalizeBaseURL(service.address)
                if await RelayIdentityVerifier.challenge(baseURL: base, pinnedPublicKeyBase64url: pinned) {
                    verifiedLANAddress = service.address
                    return service.address
                }
            }
            if clock.now >= deadline { break }
            // Break (don't busy-spin) if the task is cancelled mid-wait.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
        }
        return auth.serverURL
    }
}
