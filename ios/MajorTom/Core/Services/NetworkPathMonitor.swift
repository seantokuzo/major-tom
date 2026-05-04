import Foundation
import Network

/// Observes the device's current network reachability so the pairing UI
/// can recommend a single relay endpoint instead of asking the user to
/// pick from a list of every possible URL.
///
/// QA-FIXES #21: prefer Tailscale (stable hostname, immune to LAN-IP
/// drift) when an `.other`-typed interface is present (Tailscale on iOS
/// is implemented as a `NetworkExtension` which presents that way).
/// Otherwise fall back to LAN on wifi/wired, or the public Cloudflare
/// tunnel when only cellular is available.
@Observable
@MainActor
final class NetworkPathMonitor {
    enum Reachability: String, Sendable {
        case tailscale
        case lan
        case cellular
        case offline
    }

    private(set) var reachability: Reachability = .offline

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.majortom.NetworkPathMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let next = Self.classify(path: path)
            Task { @MainActor [weak self] in
                self?.reachability = next
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    nonisolated private static func classify(path: NWPath) -> Reachability {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.other) {
            return .tailscale
        }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .lan
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .offline
    }
}
