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

    /// Hard bound on a single resolve's TCP handshake. Without it a peer that
    /// black-holes SYNs to `:9090` keeps `pendingResolveCount` above zero for
    /// the platform default (tens of seconds), which would pin
    /// `RelayURLResolver`'s adaptive window at its ceiling on every connect.
    /// 3s is far above a real LAN handshake (single-digit ms).
    private static let resolveConnectTimeoutSeconds = 3

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    private let clock = ContinuousClock()

    func start() {
        guard browser == nil else { return }
        discoveryLog.info("browser starting")
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_majortom._tcp", domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: descriptor, using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleResults(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    discoveryLog.info("browser ready")
                case .waiting(let error):
                    // The tell-tale for a denied/undetermined Local Network
                    // permission — worth its own line in the #183 timing pass.
                    discoveryLog.notice("browser waiting: \(error.localizedDescription, privacy: .public)")
                case .failed(let error):
                    discoveryLog.error("browser failed: \(error.localizedDescription, privacy: .public)")
                    self?.isBrowsing = false
                case .cancelled:
                    discoveryLog.info("browser cancelled")
                default:
                    break
                }
            }
        }
        self.browser = browser
        isBrowsing = true
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
        for conn in resolvers.values { conn.cancel() }
        resolvers.removeAll()
        services.removeAll()
        isBrowsing = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        let activeNames = Set(results.compactMap(Self.serviceName(from:)))
        discoveryLog.info("browse results: \(activeNames.count, privacy: .public) advertised, \(self.services.count, privacy: .public) resolved, \(self.resolvers.count, privacy: .public) resolving")

        // Drop services that no longer appear in the browse results.
        services.removeAll { !activeNames.contains($0.id) }
        for name in Array(resolvers.keys) where !activeNames.contains(name) {
            resolvers[name]?.cancel()
            resolvers.removeValue(forKey: name)
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
            tcp.connectionTimeout = Self.resolveConnectTimeoutSeconds
        }
        let conn = NWConnection(to: result.endpoint, using: params)
        let startedAt = clock.now
        resolvers[name] = conn
        discoveryLog.info("resolve start \(name, privacy: .public) (fp \(Self.shortFingerprint(fingerprint), privacy: .public))")

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let elapsed = Self.elapsedMS(from: startedAt, clock: self.clock)
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
                case .failed(let error):
                    discoveryLog.notice("resolve failed \(name, privacy: .public) after \(elapsed, privacy: .public)ms: \(error.localizedDescription, privacy: .public)")
                    self.clearResolver(name, ifIdenticalTo: conn)
                case .cancelled:
                    self.clearResolver(name, ifIdenticalTo: conn)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
    }

    /// Drop a finished resolver, but only if the slot still holds *this*
    /// connection. `.ready` cancels the connection, so a `.cancelled` callback
    /// always trails it; without the identity check that trailing callback
    /// would evict a fresh resolver started for the same service name in
    /// between (service flap), silently zeroing `pendingResolveCount`.
    private func clearResolver(_ name: String, ifIdenticalTo conn: NWConnection) {
        guard resolvers[name] === conn else { return }
        resolvers.removeValue(forKey: name)
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
