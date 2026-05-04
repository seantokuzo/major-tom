import Foundation

@Observable
@MainActor
final class PairingViewModel {
    var pin: String = ""
    var serverAddress: String = ""
    var authMethods: AuthMethods?
    var isFetchingMethods = false
    let network: NetworkPathMonitor

    private let auth: AuthService

    init(auth: AuthService, network: NetworkPathMonitor? = nil) {
        self.auth = auth
        self.network = network ?? NetworkPathMonitor()
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

    /// Whether any auth method is available.
    var hasAnyAuthMethod: Bool {
        guard let methods = authMethods else { return true }
        return methods.pin || methods.google
    }

    /// Single preset matched to the phone's current reachability — `nil`
    /// when offline or before the path monitor has fired its first update.
    var recommendedPreset: ServerPreset? {
        ServerPreset(reachability: network.reachability)
    }

    /// Apply the auto-picked URL and refetch auth methods.
    func useRecommended() async {
        guard let preset = recommendedPreset else { return }
        serverAddress = preset.address
        await fetchAuthMethods()
    }

    /// On first appear, if the user has no saved server URL, seed the field
    /// with whatever the path monitor is currently recommending. Subsequent
    /// reachability changes do NOT auto-overwrite — the user can tap the
    /// recommendation chip to refresh on demand.
    func applyInitialRecommendationIfNeeded() {
        guard serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let preset = recommendedPreset else { return }
        serverAddress = preset.address
    }

    /// Fetch auth methods from the relay to adapt the login UI.
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
    }

    func submitPIN() async {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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
}
