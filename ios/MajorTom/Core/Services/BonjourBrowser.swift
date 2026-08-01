import Foundation
import Network
import OSLog

/// Discovery timing lives under `com.majortom.app` / `discovery` so an
/// on-device pass can be read straight out of Console.app. Only service
/// names, `.local` hostnames and NWError text are emitted — never keys,
/// cookies or tokens (this browser never sees any).
private let discoveryLog = Logger(subsystem: "com.majortom.app", category: "discovery")

/// Discovers Major Tom relay instances on the local network via Bonjour
/// (`_majortom._tcp`). Each discovered service is resolved to a `host:port`
/// string suitable for `AuthService.normalizeBaseURL` so the pairing UI
/// can populate the server-address field without the user typing the
/// Mac's LAN IP (which drifts on DHCP renewal — see PHASE-PAIRING-REBOOT).
@Observable
@MainActor
final class BonjourBrowser {
    struct DiscoveredService: Identifiable, Hashable {
        /// Stable across appearances of the same instance — derived from
        /// the Bonjour service name.
        let id: String
        /// Human-readable display name (the publisher's `name` field).
        let displayName: String
        /// Resolved `host:port` ready to feed into `AuthService`. Host may
        /// be a `.local` mDNS hostname or a literal IP — both are accepted
        /// by the system resolver on subsequent HTTP requests.
        let address: String
        /// Relay identity fingerprint advertised in the Bonjour TXT record
        /// (`fp` = base64url(sha256(pubKey))), or `nil` if the responder
        /// published none. A *discovery filter only* — the fingerprint is
        /// public multicast, so trust is established by `RelayIdentityVerifier`'s
        /// challenge-response, not by this value matching.
        let fingerprint: String?
    }

    private(set) var services: [DiscoveredService] = []
    private(set) var isBrowsing = false

    /// The instant the *current* browser was actually created. `start()` is
    /// idempotent, so a repeat call does NOT push this forward — it marks when
    /// mDNS browsing genuinely began. `RelayURLResolver` anchors its discovery
    /// grace window here instead of at its own start: a resolve that fires right
    /// after launch still gets a full browse window, while one that fires long
    /// after a warm start pays almost nothing (#183). `nil` while stopped.
    private(set) var startedAt: ContinuousClock.Instant?

    /// Bumped every time a NEW browser is created. Anything that caches a
    /// discovery-derived *trust* decision (see `RelayURLResolver.verifiedLAN`)
    /// binds to this, so a `stop()`/`start()` cycle — background→foreground, an
    /// explicit teardown — voids that cache by construction instead of relying
    /// on a caller remembering to clear it.
    private(set) var generation = 0

    /// Browse results currently mid-resolve (TCP handshake in flight).
    /// `RelayURLResolver` polls this to hold its LAN window open **only**
    /// while a local responder is genuinely being resolved — with nothing
    /// answering on the LAN (cellular / remote) it stays 0 and the resolver
    /// falls through to the tunnel as soon as its short grace window closes.
    /// Derived from `resolvers` rather than mirrored into a second stored
    /// property so the two can never desync (#183).
    var pendingResolveCount: Int { resolvers.count }

    /// Cap on concurrent resolvers + emitted services. A hostile peer on
    /// the LAN can flood the multicast group with unique `_majortom._tcp`
    /// names; without a cap each name opens an `NWConnection` and a chip
    /// row, eventually pressuring layout + fd state. 16 is plenty for any
    /// realistic deployment (home LAN typically has 1, lab setups <5).
    private static let maxServices = 16

    /// Hard bound on a single resolve. Applied twice, because one mechanism is
    /// not enough:
    ///
    /// - As `NWProtocolTCP.Options.connectionTimeout`, which bounds the TCP
    ///   handshake — without it a peer that black-holes SYNs to `:9090` keeps
    ///   `pendingResolveCount` above zero for the platform default (tens of
    ///   seconds) and pins `RelayURLResolver`'s window at its ceiling.
    /// - As a wall-clock watchdog (`watchdogs`), because `connectionTimeout`
    ///   bounds neither `.waiting` (an `NWConnection` with no viable path — easy
    ///   to hit, since `.cellular` is prohibited below, so dropping Wi-Fi parks
    ///   the connection there indefinitely) nor the mDNS/DNS resolution phase of
    ///   a `.service` endpoint.
    ///
    /// 3s is far above a real LAN handshake (single-digit ms) and strictly below
    /// `RelayURLResolver.maxWait` (4s), which the adaptive window depends on.
    private static let resolveDeadlineSeconds = 3

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]
    /// One per in-flight resolver, keyed identically to `resolvers`.
    private var watchdogs: [String: Task<Void, Never>] = [:]

    private let clock = ContinuousClock()

    func start() {
        guard browser == nil else { return }
        discoveryLog.info("browser starting")
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_majortom._tcp", domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: descriptor, using: params)

        // Both handlers hop through a `Task`, so a delivery can land after a
        // `stop()` (or after a *replacement* browser was started). Without the
        // identity guard, a queued browse result would call `startResolve` while
        // `browser == nil`, registering a resolver that browse-result eviction
        // can never reach — and whose name the next browser then skips
        // (`resolvers[name] != nil`), so the service never resolves again and
        // every connect falls back to the tunnel for the rest of the session.
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor in
                guard let self, let browser, self.browser === browser else { return }
                self.handleResults(results)
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor in
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .ready:
                    discoveryLog.info("browser ready")
                case .waiting(let error):
                    // The tell-tale for a denied/undetermined Local Network
                    // permission — worth its own line in the #183 timing pass.
                    discoveryLog.notice("browser waiting: \(error.localizedDescription, privacy: .public)")
                case .failed(let error):
                    // Tear the failed browser down completely. Merely flipping
                    // `isBrowsing` would leave `browser` non-nil, making
                    // `start()`'s `guard browser == nil` a permanent no-op — so
                    // discovery would stay dead for the whole process and every
                    // resolve would silently ride the tunnel (#183 reproduced for
                    // that launch). `start()` is now the recovery mechanism, so
                    // it has to be able to build a fresh browser.
                    discoveryLog.error("browser failed: \(error.localizedDescription, privacy: .public)")
                    self.stop()
                case .cancelled:
                    discoveryLog.info("browser cancelled")
                default:
                    break
                }
            }
        }
        self.browser = browser
        isBrowsing = true
        generation &+= 1
        startedAt = clock.now
        browser.start(queue: .main)
    }

    func stop() {
        // Log only when there was something to tear down, but ALWAYS run the
        // teardown below — an early return here could strand a `services` entry
        // appended by a resolver callback that landed after a previous `stop()`.
        if browser != nil || !resolvers.isEmpty {
            discoveryLog.info("browser stopping (\(self.services.count, privacy: .public) discovered, \(self.resolvers.count, privacy: .public) resolving)")
        }
        browser?.cancel()
        browser = nil
        startedAt = nil
        for name in Array(resolvers.keys) { cancelResolver(name) }
        services.removeAll()
        isBrowsing = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        let activeNames = Set(results.compactMap(Self.serviceName(from:)))
        discoveryLog.info("browse results: \(activeNames.count, privacy: .public) advertised, \(self.services.count, privacy: .public) resolved, \(self.resolvers.count, privacy: .public) resolving")

        // Drop services that no longer appear in the browse results.
        services.removeAll { !activeNames.contains($0.id) }
        for name in Array(resolvers.keys) where !activeNames.contains(name) {
            cancelResolver(name)
        }

        // Resolve newly-seen services, bounded by `maxServices` so
        // multicast flood from a hostile peer can't grow the chip list.
        for result in results {
            guard let name = Self.serviceName(from: result) else { continue }
            if services.contains(where: { $0.id == name }) { continue }
            if resolvers[name] != nil { continue }
            if services.count + resolvers.count >= Self.maxServices { break }
            startResolve(for: result, name: name, fingerprint: Self.fingerprint(from: result))
        }
    }

    private func startResolve(for result: NWBrowser.Result, name: String, fingerprint: String?) {
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = Self.resolveDeadlineSeconds
        }
        let conn = NWConnection(to: result.endpoint, using: params)
        let resolveStartedAt = clock.now
        resolvers[name] = conn
        discoveryLog.info("resolve start \(name, privacy: .public) (fp \(Self.shortFingerprint(fingerprint), privacy: .public))")

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let elapsed = Self.elapsedMS(from: resolveStartedAt, clock: self.clock)
                switch state {
                case .ready:
                    // State callbacks hop through a `Task`, so a `stop()` or a
                    // browse-result eviction can land first. If this resolver is
                    // no longer the registered one, don't resurrect a service
                    // that was torn down — just release the connection.
                    guard self.resolvers[name] === conn else {
                        conn.cancel()
                        return
                    }
                    if let address = Self.address(from: conn.currentPath?.remoteEndpoint) {
                        discoveryLog.info("resolve ready \(name, privacy: .public) → \(address, privacy: .public) in \(elapsed, privacy: .public)ms")
                        let entry = DiscoveredService(id: name, displayName: name, address: address, fingerprint: fingerprint)
                        if !self.services.contains(entry) {
                            self.services.append(entry)
                        }
                    } else {
                        discoveryLog.notice("resolve ready \(name, privacy: .public) but no usable host:port in \(elapsed, privacy: .public)ms")
                    }
                    conn.cancel()
                    self.clearResolver(name, ifIdenticalTo: conn)
                case .waiting(let error):
                    // NOT terminal and NOT bounded by `connectionTimeout`: an
                    // `NWConnection` with no viable path parks here until one
                    // appears. Logged rather than cancelled so a transient
                    // ECONNREFUSED can still recover; the watchdog below is what
                    // guarantees the slot is eventually freed.
                    discoveryLog.notice("resolve waiting \(name, privacy: .public) after \(elapsed, privacy: .public)ms: \(error.localizedDescription, privacy: .public)")
                case .failed(let error):
                    discoveryLog.notice("resolve failed \(name, privacy: .public) after \(elapsed, privacy: .public)ms: \(error.localizedDescription, privacy: .public)")
                    // `NWConnection` releases its state handler only after
                    // `.cancelled`, and that handler captures `conn` — so
                    // dropping the dictionary entry without cancelling strands
                    // the connection + handler for the life of the process. With
                    // a relay asleep behind a Bonjour sleep proxy (still
                    // advertised, SYNs unanswered) that is one leak per mDNS TTL
                    // refresh.
                    conn.cancel()
                    self.clearResolver(name, ifIdenticalTo: conn)
                case .cancelled:
                    self.clearResolver(name, ifIdenticalTo: conn)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)

        // Wall-clock backstop for every state `connectionTimeout` doesn't cover
        // (`.waiting`, a stalled mDNS/DNS resolution phase). Without it a
        // connection that loses its path — Wi-Fi → cellular mid-resolve, with
        // `.cellular` prohibited — holds a `maxServices` slot and a non-zero
        // `pendingResolveCount` forever, which then defeats `RelayURLResolver`'s
        // grace break and stalls every later connect out to its 4s ceiling.
        watchdogs[name] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.resolveDeadlineSeconds))
            guard !Task.isCancelled, let self, self.resolvers[name] === conn else { return }
            discoveryLog.notice("resolve watchdog \(name, privacy: .public): cancelling after \(Self.resolveDeadlineSeconds, privacy: .public)s")
            conn.cancel()
            self.clearResolver(name, ifIdenticalTo: conn)
        }
    }

    /// Drop a finished resolver, but only if the slot still holds *this*
    /// connection. `.ready` cancels the connection, so a `.cancelled` callback
    /// always trails it; without the identity check that trailing callback
    /// would evict a fresh resolver started for the same service name in
    /// between (service flap), silently zeroing `pendingResolveCount`.
    private func clearResolver(_ name: String, ifIdenticalTo conn: NWConnection) {
        guard resolvers[name] === conn else { return }
        resolvers.removeValue(forKey: name)
        watchdogs.removeValue(forKey: name)?.cancel()
    }

    /// Unconditionally tear down the resolver registered for `name` — connection
    /// cancelled, watchdog cancelled, slot freed. Used where the *slot* is being
    /// reclaimed (browse eviction, `stop()`) rather than a specific connection
    /// finishing.
    private func cancelResolver(_ name: String) {
        resolvers.removeValue(forKey: name)?.cancel()
        watchdogs.removeValue(forKey: name)?.cancel()
    }

    /// Whole milliseconds since `start` — the unit every discovery/resolve log
    /// line reports so an on-device pass can be read without arithmetic.
    static func elapsedMS(from start: ContinuousClock.Instant, clock: ContinuousClock) -> Int {
        let elapsed = start.duration(to: clock.now)
        let (seconds, attoseconds) = elapsed.components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }

    /// First 8 chars of a relay fingerprint for log correlation. The
    /// fingerprint is public data (plaintext mDNS TXT), but a prefix is
    /// enough to correlate lines and keeps them short.
    static func shortFingerprint(_ fingerprint: String?) -> String {
        guard let fingerprint, !fingerprint.isEmpty else { return "none" }
        return String(fingerprint.prefix(8))
    }

    private static func serviceName(from result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    /// Pull the relay identity fingerprint (`fp`) from the Bonjour TXT record
    /// carried on the browse result, if present. Absent for responders that
    /// publish no TXT record — in which case the resolver still challenges the
    /// host (the signature, not the fingerprint, is the trust anchor).
    private static func fingerprint(from result: NWBrowser.Result) -> String? {
        guard case .bonjour(let txtRecord) = result.metadata else { return nil }
        if case .string(let fp) = txtRecord.getEntry(for: "fp") { return fp }
        return nil
    }

    /// Convert an NWEndpoint's resolved peer to a "host:port" string
    /// suitable for `AuthService.normalizeBaseURL`. Hostnames are
    /// preferred over raw IPs so the value survives DHCP renewals.
    /// Link-local IPv6 with a zone identifier (`fe80::1%en0`) is
    /// intentionally skipped — the percent sign breaks `URL(string:)`
    /// and the `.name` / `.ipv4` branches dominate Bonjour resolution.
    private static func address(from endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        let hostString: String
        switch host {
        case .name(let name, _):
            hostString = name
        case .ipv4(let ip):
            // IPv4Address interpolation can append a "%en0" zone id; the '%'
            // breaks URL(string:), and a literal IPv4 never needs one.
            hostString = String("\(ip)".prefix { $0 != "%" })
        case .ipv6:
            return nil
        @unknown default:
            return nil
        }
        return "\(hostString):\(port.rawValue)"
    }
}
