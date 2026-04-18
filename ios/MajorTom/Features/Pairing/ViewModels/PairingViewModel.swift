import Foundation

@Observable
@MainActor
final class PairingViewModel {
    var pin: String = ""
    var serverAddress: String = ""
    var authMethods: AuthMethods?
    var isFetchingMethods = false

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
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
