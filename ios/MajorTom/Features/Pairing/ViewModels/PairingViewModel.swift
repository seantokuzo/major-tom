import Foundation

@Observable
@MainActor
final class PairingViewModel {
    var pin: String = ""
    var serverAddress: String = ""

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
