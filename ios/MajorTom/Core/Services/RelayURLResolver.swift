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

    /// A LAN address proven to belong to the pinned relay identity via
    /// challenge-response, **bound to the trust context it was proven in**.
    /// Only this — never an unverified mDNS responder — is handed to the
    /// cookie-bearing connections.
    ///
    /// The address alone is not a safe cache key: it is a forgeable string
    /// (`192.168.1.x:9090`, or a `.local` hostname an attacker can adopt), so a
    /// bare address cache would let a hostile responder on a *different* network
    /// inherit a proof issued on the network we verified at home. The bindings
    /// below are what make that impossible.
    private struct VerifiedLANHost {
        /// The `host:port` that signed our nonce.
        let address: String
        /// The pinned relay public key the signature was verified against.
        /// Unpair/re-pair rewrites `relay_public_key`, so a proof issued under
        /// relay A's key can never be reused for relay B — no caller has to
        /// remember to invalidate.
        let pinnedKey: String
        /// `BonjourBrowser.generation` at verification time. Any `stop()`/
        /// `start()` cycle — background→foreground being the important one, since
        /// that's the boundary across which the device can wake on a completely
        /// different LAN — bumps it and voids the proof.
        let browserGeneration: Int
    }

    /// Deliberately not observed: this is a security cache read from
    /// `bestRelayURL` on the connect path, not view state, and self-healing reads
    /// mutate it.
    @ObservationIgnored private var verifiedLAN: VerifiedLANHost?

    /// The resolve pass currently in flight, if any.
    ///
    /// `resolvePreferringLAN` now has two independent triggers — the
    /// `auth.isPaired` connect path and the scenePhase `.active` re-resolve —
    /// and on a cold launch of an already-paired device both fire within
    /// milliseconds of each other. Overlapping calls are therefore routine, not
    /// exotic. Two passes would each issue their own `/identity/challenge`
    /// round-trip to the same host: correct (nothing writes `verifiedLAN`
    /// without a signature that verified against the pinned key, and the two
    /// passes can only agree), but a wasted nonce round-trip per host and a log
    /// that reads like a double-connect. Joiners await this task instead.
    @ObservationIgnored private var inFlightResolve: Task<String, Never>?

    /// THE single gate for reusing a prior proof. Returns an address only when
    /// every part of the trust context still holds — same pinned key, same
    /// browse session, host still advertised — and drops the entry otherwise, so
    /// both callers fail closed to the tunnel. No path in this type returns a LAN
    /// address without either passing through here or completing a fresh
    /// challenge against the currently-pinned key.
    private var reusableVerifiedLANAddress: String? {
        guard let cached = verifiedLAN else { return nil }
        guard let pinned = KeychainService.load(.relayPublicKey), pinned == cached.pinnedKey else {
            resolveLog.notice("cached LAN host dropped: pinned relay identity changed")
            verifiedLAN = nil
            return nil
        }
        guard cached.browserGeneration == browser.generation else {
            resolveLog.notice("cached LAN host dropped: discovery restarted (possible network change)")
            verifiedLAN = nil
            return nil
        }
        // Not a trust failure — a service can flap — so keep the entry and let a
        // later browse result make it usable again.
        guard browser.services.contains(where: { $0.address == cached.address }) else { return nil }
        return cached.address
    }

    /// Drop any cached LAN proof. Called from the app when the trust context
    /// changes in a way the bindings above cannot see from the inside — currently
    /// app backgrounding, after which the device may return on a different
    /// network with an attacker advertising the same `host:port` string.
    ///
    /// Pairs with the scenePhase `.active` re-resolve in `MajorTomApp`: dropping
    /// the proof with no trigger to re-earn it would pin the process to the
    /// tunnel for the rest of its life, since `bestRelayURL` is synchronous and
    /// cannot challenge.
    func invalidateVerifiedLANHost() {
        // Cancel any pass still in flight, not just the cached entry. A resolve
        // that started before backgrounding captured the pre-`stop()`
        // `BonjourBrowser.generation`, so whatever it proves is already unusable
        // by the time it lands — and the foreground re-resolve would *join* it
        // (see `inFlightResolve`) and inherit that dead answer instead of
        // opening a fresh pass against the new browse session. Cancellation is
        // fail-closed: `performResolve` breaks out and returns the tunnel.
        inFlightResolve?.cancel()
        inFlightResolve = nil
        guard verifiedLAN != nil else { return }
        resolveLog.info("cached LAN host invalidated (app backgrounded)")
        verifiedLAN = nil
    }

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
    /// building its `/shell` URL): a LAN host whose proof is still bound to the
    /// current trust context (see `reusableVerifiedLANAddress`), else the frozen
    /// `auth.serverURL` (tunnel). Never returns an unverified host —
    /// verification happens only in the async `resolvePreferringLAN`. Returned in
    /// the same raw `host[:port]` form as `auth.serverURL`, so callers keep
    /// normalizing via `AuthService`.
    var bestRelayURL: String {
        reusableVerifiedLANAddress ?? auth.serverURL
    }

    /// How long Bonjour gets to show *any* sign of a local responder before we
    /// give up on the LAN — measured from the instant the **browser** started,
    /// not from the instant this resolve started (`BonjourBrowser.startedAt`).
    ///
    /// Anchoring at resolve start is what makes the window a straight tax: the
    /// browser and the resolve both begin within milliseconds of each other on a
    /// cold launch of an already-paired device, so the whole discover → TCP
    /// handshake → `.ready` pipeline has to fit inside it. Anchoring at browser
    /// start means the pre-warm actually counts — by sign-in time the browser has
    /// usually been running for seconds, so warm services are challenged
    /// immediately and a cellular device pays only `discoveryGraceFloor`.
    ///
    /// Deliberately NOT gated on `NetworkPathMonitor.reachability` — that starts
    /// at `.offline` until `NWPathMonitor` delivers its first update, so a
    /// launch-time check would skip the LAN exactly when we most want it.
    private static let discoveryGrace: Duration = .seconds(2)

    /// Minimum wait measured from *this* resolve's start, so a resolve that
    /// begins while the browser is still coming up isn't cut off before the first
    /// poll. Also the entire LAN cost for a device whose browser has been warm
    /// and empty for longer than `discoveryGrace` (cellular / remote).
    private static let discoveryGraceFloor: Duration = .milliseconds(250)

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
    /// **Timing policy (#183).** The old flat 2s window was measured from the
    /// resolve's own start, and the browser started at that same instant, so the
    /// whole discover → TCP-handshake → `.ready` pipeline had to fit inside it.
    /// The window is now *anchored at browser start* and *short when nothing is
    /// there, patient when something is*:
    ///
    /// - `discoveryGrace` (2s **from `browser.startedAt`**): if nothing local has
    ///   answered by then — nothing discovered, nothing mid-resolve — return the
    ///   tunnel. Because the browser is started when the UI scene appears, this
    ///   is mostly spent *before* a resolve even begins.
    /// - `discoveryGraceFloor` (250ms from this resolve's start) keeps a resolve
    ///   that fires while the browser is still coming up from being cut off, and
    ///   is the whole LAN cost once the browser has been warm and empty.
    /// - Extend past the grace window only while `browser.pendingResolveCount`
    ///   is non-zero, i.e. a discovered responder is genuinely mid-handshake.
    ///   `BonjourBrowser` caps each resolve at 3s (TCP timeout + wall-clock
    ///   watchdog), so a black-holed or path-less advertiser cannot hold the
    ///   window open indefinitely.
    /// - `maxWait` (4s from this resolve's start) is a hard ceiling: no *new*
    ///   challenge starts after it, which also bounds the old worst case where up
    ///   to 16 discovered hosts could each burn a 2s challenge timeout serially
    ///   inside one pass.
    ///
    /// Resulting cost, versus `main`'s flat 2s-from-resolve-start window:
    ///
    /// | Case | `main` | now |
    /// |---|---|---|
    /// | cold launch already paired, relay on LAN | 2s of browse time, all of it inside the connect wait | ~2s of browse time starting at scene appear, ~1.95s of connect wait |
    /// | fresh sign-in (browser warm for seconds) | 2s from a cold browser | warm services challenged on the first pass — no wait at all |
    /// | any later resolve in a warm process | 2s | ~250ms when nothing is on the LAN |
    /// | cellular, cold launch | 2s | ~1.95s — unchanged, because a cold browser is indistinguishable from a slow one without a transport signal |
    /// | cellular, after warm-up | 2s | ~250ms |
    ///
    /// Cutting the cold-launch cellular case needs a reachability gate, which is
    /// *not* the naive "skip the LAN when `.cellular`" that was rejected above
    /// (`NetworkPathMonitor` starts at `.offline`); it has to be an early *break*
    /// once reachability has positively reported `.cellular`. Deferred until the
    /// on-device instrumentation says what the real numbers are.
    ///
    /// A challenge already in flight is allowed to finish (it is the payoff),
    /// so the absolute worst case is `maxWait` + one challenge timeout.
    ///
    /// **Idempotent under concurrency.** Overlapping callers share a single pass
    /// (`inFlightResolve`) rather than each opening their own — see that
    /// property for why overlap is now the normal cold-launch shape.
    func resolvePreferringLAN() async -> String {
        if let inFlight = inFlightResolve {
            resolveLog.info("resolve joined a pass already in flight")
            return await inFlight.value
        }
        let pass = Task { await self.performResolve() }
        inFlightResolve = pass
        let result = await pass.value
        // Only the caller that opened the pass clears it, and only if it is
        // still the registered one — `invalidateVerifiedLANHost` may have
        // cancelled and replaced/cleared it while we were awaiting.
        if inFlightResolve == pass { inFlightResolve = nil }
        return result
    }

    private func performResolve() async -> String {
        let clock = ContinuousClock()
        let started = clock.now

        // Re-use a proof that is still bound to the current pinned key + browse
        // session, without re-challenging.
        if let cached = reusableVerifiedLANAddress {
            resolveLog.info("resolve → LAN \(cached, privacy: .public) (cached, still bound to the pinned identity)")
            return cached
        }
        verifiedLAN = nil

        guard let pinned = KeychainService.load(.relayPublicKey),
              let pinnedRaw = RelayIdentityVerifier.data(fromBase64url: pinned) else {
            resolveLog.notice("resolve → tunnel: no pinned relay identity (paired pre-/identity)")
            return auth.serverURL
        }
        let expectedFingerprint = RelayIdentityVerifier.fingerprint(forRawPublicKey: pinnedRaw)

        browser.start()
        resolveLog.info("resolve start: \(self.browser.services.count, privacy: .public) warm, \(self.browser.pendingResolveCount, privacy: .public) resolving, pinned fp \(BonjourBrowser.shortFingerprint(expectedFingerprint), privacy: .public)")

        // Capture the browse session BEFORE any challenge. If discovery restarts
        // mid-loop (a `.failed` browser tears itself down and rebuilds), a proof
        // earned against a service discovered in the old session must not be
        // cached under the new one — binding the stale generation makes the entry
        // immediately unusable, i.e. fail closed.
        let browseGeneration = browser.generation

        let ceiling = started.advanced(by: Self.maxWait)
        // Anchored at browser start (see `discoveryGrace`), floored relative to
        // this resolve, and clamped under the ceiling so the two can never
        // invert.
        let browserStart = browser.startedAt ?? started
        let graceDeadline = min(
            max(browserStart.advanced(by: Self.discoveryGrace),
                started.advanced(by: Self.discoveryGraceFloor)),
            ceiling
        )
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
                    // Cancellation is cooperative, so a challenge that was
                    // already in flight when `invalidateVerifiedLANHost()` ran
                    // resumes *after* it — and would otherwise write a cache
                    // entry over an invalidation that already happened, and hand
                    // a LAN address to a caller (or a joiner) that must fail
                    // closed. The signature itself was genuine; the trust context
                    // it was earned in is the thing that just went away.
                    //
                    // The `browserGeneration` binding would also catch this the
                    // next time the browser restarts, but that is a downstream
                    // guard for a *later* read. This is the one that keeps the
                    // return value of this call honest.
                    if Task.isCancelled {
                        resolveLog.notice("resolve → tunnel: \(service.address, privacy: .public) verified but the pass was cancelled mid-challenge")
                        return auth.serverURL
                    }
                    verifiedLAN = VerifiedLANHost(
                        address: service.address,
                        pinnedKey: pinned,
                        browserGeneration: browseGeneration
                    )
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
