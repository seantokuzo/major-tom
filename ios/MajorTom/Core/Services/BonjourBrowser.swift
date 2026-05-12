import Foundation
import Network

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
    }

    private(set) var services: [DiscoveredService] = []
    private(set) var isBrowsing = false

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    func start() {
        guard browser == nil else { return }
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
                if case .failed = state {
                    self?.isBrowsing = false
                }
            }
        }
        self.browser = browser
        isBrowsing = true
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for conn in resolvers.values { conn.cancel() }
        resolvers.removeAll()
        services.removeAll()
        isBrowsing = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        let activeNames = Set(results.compactMap(Self.serviceName(from:)))

        // Drop services that no longer appear in the browse results.
        services.removeAll { !activeNames.contains($0.id) }
        for name in Array(resolvers.keys) where !activeNames.contains(name) {
            resolvers[name]?.cancel()
            resolvers.removeValue(forKey: name)
        }

        // Resolve newly-seen services.
        for result in results {
            guard let name = Self.serviceName(from: result) else { continue }
            if services.contains(where: { $0.id == name }) { continue }
            if resolvers[name] != nil { continue }
            startResolve(for: result, name: name)
        }
    }

    private func startResolve(for result: NWBrowser.Result, name: String) {
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        let conn = NWConnection(to: result.endpoint, using: params)
        resolvers[name] = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    if let address = Self.address(from: conn.currentPath?.remoteEndpoint) {
                        let entry = DiscoveredService(id: name, displayName: name, address: address)
                        if !self.services.contains(entry) {
                            self.services.append(entry)
                        }
                    }
                    conn.cancel()
                    self.resolvers.removeValue(forKey: name)
                case .failed, .cancelled:
                    self.resolvers.removeValue(forKey: name)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
    }

    private static func serviceName(from result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    /// Convert an NWEndpoint's resolved peer to a "host:port" string
    /// suitable for `AuthService.normalizeBaseURL`. Hostnames are
    /// preferred over raw IPs so the value survives DHCP renewals.
    private static func address(from endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        let hostString: String
        switch host {
        case .name(let name, _):
            hostString = name
        case .ipv4(let ip):
            hostString = "\(ip)"
        case .ipv6(let ip):
            hostString = "[\(ip)]"
        @unknown default:
            return nil
        }
        return "\(hostString):\(port.rawValue)"
    }
}
