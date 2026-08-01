import Foundation
import OSLog

/// Connect-time LAN-vs-tunnel decisions land under `com.majortom.app` /
/// `resolve`. Only addresses, fingerprint prefixes (public mDNS data) and
/// elapsed milliseconds are emitted — never the session cookie, the pinned
/// key, a nonce or a signature.
private let resolveLog = Logger(subsystem: "com.majortom.app", category: "resolve")

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

    /// How long we wait for Bonjour to show *any* sign of a local responder
    /// before giving up on the LAN. Sized for the cellular / remote case: with
    /// nothing advertising `_majortom._tcp` this is the entire cost added to
    /// connect (down from the old flat 2s window). Deliberately NOT gated on
    /// `NetworkPathMonitor.reachability` — that starts at `.offline` until
    /// `NWPathMonitor` delivers its first update, so a launch-time check would
    /// skip the LAN exactly when we most want it.
    private static let discoveryGrace: Duration = .seconds(1)

    /// Hard ceiling on the LAN window. Only reachable when a responder is
    /// actually mid-resolve or mid-challenge — the grace window ends the wait
    /// otherwise. Sized to cover mDNS browse + TCP handshake + one challenge
    /// round-trip on a slow/busy Wi-Fi network.
    private static let maxWait: Duration = .seconds(4)

    /// Re-check cadence while the window is open.
    private static let pollInterval: Duration = .milliseconds(150)

    /// Resolve preferring the LAN, but only after proving a discovered host is
    /// the relay we paired with. Gives Bonjour a window to answer, then for each
    /// discovered host fast-filters on the advertised fingerprint and challenges
    /// it to sign a fresh nonce (`RelayIdentityVerifier`). The first host that
    /// returns a valid signature against the pinned key is cached and returned;
    /// otherwise we fall back to the tunnel. With no pinned identity (paired
    /// against a relay that predates `/identity`) we never trust a LAN host and
    /// always return the tunnel. Idempotently starts discovery.
    ///
    /// **Timing policy (#183).** The old flat 2s window routinely expired before
    /// `BonjourBrowser` had finished its discover → TCP-handshake → `.ready`
    /// pipeline, so the LAN never won on Wi-Fi. It is replaced by a window that
    /// is *short when nothing is there* and *patient when something is*:
    ///
    /// - `discoveryGrace` (1s): if nothing local has answered by then — nothing
    ///   discovered, nothing mid-resolve — return the tunnel. Cellular and
    ///   remote users pay 1s instead of the old 2s.
    /// - Extend past the grace window only while `browser.pendingResolveCount`
    ///   is non-zero, i.e. a discovered responder is genuinely mid-handshake.
    ///   `BonjourBrowser` caps each handshake at 3s, so a black-holed advertiser
    ///   cannot hold the window open indefinitely.
    /// - `maxWait` (4s) is a hard ceiling: no *new* challenge starts after it,
    ///   which also bounds the old worst case where up to 16 discovered hosts
    ///   could each burn a 2s challenge timeout serially inside one pass.
    ///
    /// A challenge already in flight is allowed to finish (it is the payoff),
    /// so the absolute worst case is `maxWait` + one challenge timeout.
    func resolvePreferringLAN() async -> String {
        let clock = ContinuousClock()
        let started = clock.now

        // Re-use a still-advertised verified host without re-challenging.
        if let verified = verifiedLANAddress,
           browser.services.contains(where: { $0.address == verified }) {
            resolveLog.info("resolve → LAN \(verified, privacy: .public) (cached, verified this session)")
            return verified
        }
        verifiedLANAddress = nil

        guard let pinned = KeychainService.load(.relayPublicKey),
              let pinnedRaw = RelayIdentityVerifier.data(fromBase64url: pinned) else {
            resolveLog.notice("resolve → tunnel: no pinned relay identity (paired pre-/identity)")
            return auth.serverURL
        }
        let expectedFingerprint = RelayIdentityVerifier.fingerprint(forRawPublicKey: pinnedRaw)

        browser.start()
        resolveLog.info("resolve start: \(self.browser.services.count, privacy: .public) warm, \(self.browser.pendingResolveCount, privacy: .public) resolving, pinned fp \(BonjourBrowser.shortFingerprint(expectedFingerprint), privacy: .public)")

        let graceDeadline = started.advanced(by: Self.discoveryGrace)
        let ceiling = started.advanced(by: Self.maxWait)
        var challenged: Set<String> = []

        while true {
            // `browser.services` is snapshotted per for-loop; hosts that appear
            // during an await are picked up on the next outer pass. `challenged`
            // prevents re-issuing a challenge to the same address.
            for service in browser.services where !challenged.contains(service.address) {
                // Don't *start* a new challenge past the ceiling — each one can
                // burn its own HTTP timeout, so an unbounded pass over many
                // discovered hosts would stall the connect path.
                if clock.now >= ceiling { break }
                challenged.insert(service.address)
                // A mismatched advertised fingerprint can't be our relay — skip
                // the round-trip. A *missing* fingerprint is still challenged;
                // the signature, not the fingerprint, is the trust anchor.
                if let fp = service.fingerprint, fp != expectedFingerprint {
                    resolveLog.notice("skip \(service.address, privacy: .public): advertised fp \(BonjourBrowser.shortFingerprint(fp), privacy: .public) ≠ pinned")
                    continue
                }
                let base = AuthService.normalizeBaseURL(service.address)
                let challengeStart = clock.now
                let verified = await RelayIdentityVerifier.challenge(baseURL: base, pinnedPublicKeyBase64url: pinned)
                resolveLog.info("challenge \(service.address, privacy: .public) → \(verified ? "VERIFIED" : "rejected", privacy: .public) in \(BonjourBrowser.elapsedMS(from: challengeStart, clock: clock), privacy: .public)ms")
                if verified {
                    verifiedLANAddress = service.address
                    resolveLog.info("resolve → LAN \(service.address, privacy: .public) in \(BonjourBrowser.elapsedMS(from: started, clock: clock), privacy: .public)ms")
                    return service.address
                }
            }

            let now = clock.now
            if now >= ceiling {
                resolveLog.notice("resolve → tunnel: hit \(Self.maxWait.description, privacy: .public) ceiling after \(challenged.count, privacy: .public) challenge(s)")
                break
            }
            // Hold the window open past the grace period only while a discovered
            // responder is still mid-handshake. Nothing pending == nothing local
            // is coming, so cellular/remote falls through immediately.
            if now >= graceDeadline && browser.pendingResolveCount == 0 {
                resolveLog.info("resolve → tunnel: no local responder after \(BonjourBrowser.elapsedMS(from: started, clock: clock), privacy: .public)ms (\(challenged.count, privacy: .public) challenged)")
                break
            }
            // Break (don't busy-spin) if the task is cancelled mid-wait.
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                resolveLog.notice("resolve → tunnel: cancelled after \(BonjourBrowser.elapsedMS(from: started, clock: clock), privacy: .public)ms")
                break
            }
        }
        return auth.serverURL
    }
}
