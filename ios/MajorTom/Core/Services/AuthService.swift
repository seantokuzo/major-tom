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
    /// Session cookie value obtained from PIN login (used for WebSocket auth).
    var sessionCookie: String?
    var serverURL: String = "majortom.seantokuzodevtunnel.space"
    /// User ID from the relay (populated after login).
    var userId: String?
    /// User role from the relay (populated after login).
    var userRole: UserRole?

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

        if let cookie = KeychainService.load(.deviceToken),
           let deviceId = KeychainService.load(.deviceId) {
            sessionCookie = cookie
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
        guard let url = URL(string: "\(baseURL)/auth/pin/login") else {
            authState = .error("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["pin": pin]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                authState = .error("Invalid response")
                return
            }

            if httpResponse.statusCode == 200 {
                // Extract session cookie from Set-Cookie header
                let cookie = extractSessionCookie(from: httpResponse)

                guard let cookie else {
                    authState = .error("No session cookie received")
                    return
                }

                let deviceId = UUID().uuidString
                try KeychainService.save(cookie, for: .deviceToken)
                try KeychainService.save(deviceId, for: .deviceId)
                try KeychainService.save(deviceName, for: .deviceName)
                sessionCookie = cookie
                authState = .paired(deviceId: deviceId)

                // Decode the response for user info
                if let loginResponse = try? JSONDecoder().decode(PinLoginResponse.self, from: data) {
                    userId = loginResponse.userId
                    userRole = loginResponse.role.flatMap { UserRole(rawValue: $0) }
                }
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

    // MARK: - Cookie Extraction

    private func extractSessionCookie(from response: HTTPURLResponse) -> String? {
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url else { return nil }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        // Look for the session cookie (relay uses "mt-session")
        return cookies.first(where: { $0.name == "mt-session" })?.value
            ?? cookies.first?.value
    }

    // MARK: - Unpair

    func unpair() {
        KeychainService.deleteAll()
        sessionCookie = nil
        userId = nil
        userRole = nil
        authState = .unpaired
    }
}

// MARK: - PIN Login Response

private struct PinLoginResponse: Codable {
    let email: String
    let name: String?
    let userId: String?
    let role: String?
}
