import Foundation
import UIKit

enum AuthState: Equatable {
    case unpaired
    case pairing
    case paired(deviceId: String)
    case error(String)

    var isPaired: Bool {
        if case .paired = self { return true }
        return false
    }

    var deviceId: String? {
        if case .paired(let id) = self { return id }
        return nil
    }
}

@Observable
@MainActor
final class AuthService {
    var authState: AuthState = .unpaired
    var deviceToken: String?
    var serverURL: String = "localhost:9090"

    init() {
        loadSavedCredentials()
    }

    var isPaired: Bool { authState.isPaired }

    var deviceId: String? { authState.deviceId }

    var deviceName: String {
        UIDevice.current.name
    }

    // MARK: - Credential Management

    func loadSavedCredentials() {
        if let url = KeychainService.load(.serverURL) {
            serverURL = url
        }

        if let token = KeychainService.load(.deviceToken),
           let deviceId = KeychainService.load(.deviceId) {
            deviceToken = token
            authState = .paired(deviceId: deviceId)
        } else {
            authState = .unpaired
        }
    }

    func saveServerURL(_ url: String) {
        serverURL = url
        try? KeychainService.save(url, for: .serverURL)
    }

    // MARK: - PIN Pairing

    func pair(pin: String) async {
        authState = .pairing

        let scheme = serverURL.contains("://") ? "" : "http://"
        let baseURL = "\(scheme)\(serverURL)"
        guard let url = URL(string: "\(baseURL)/api/pair") else {
            authState = .error("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "pin": pin,
            "deviceName": deviceName,
        ]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                authState = .error("Invalid response")
                return
            }

            if httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(PairResponse.self, from: data)
                try KeychainService.save(result.token, for: .deviceToken)
                try KeychainService.save(result.deviceId, for: .deviceId)
                try KeychainService.save(deviceName, for: .deviceName)
                deviceToken = result.token
                authState = .paired(deviceId: result.deviceId)
            } else if httpResponse.statusCode == 401 {
                authState = .error("Invalid PIN")
            } else if httpResponse.statusCode == 429 {
                authState = .error("Too many attempts. Try again later.")
            } else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                authState = .error("Pairing failed: \(errorBody)")
            }
        } catch {
            authState = .error("Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Unpair

    func unpair() {
        KeychainService.deleteAll()
        deviceToken = nil
        authState = .unpaired
    }
}

// MARK: - Pairing Response

private struct PairResponse: Codable {
    let token: String
    let deviceId: String
}
