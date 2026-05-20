import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum GoogleOAuthError: LocalizedError {
    case malformedClientID(String)
    case userCanceled
    case missingAuthorizationCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case missingIDToken
    case presentationUnavailable

    var errorDescription: String? {
        switch self {
        case .malformedClientID(let id):
            return "Google iOS client ID is malformed: \(id)"
        case .userCanceled:
            return "Sign-in canceled"
        case .missingAuthorizationCode:
            return "Google did not return an authorization code"
        case .stateMismatch:
            return "OAuth state mismatch — possible CSRF attempt"
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        case .missingIDToken:
            return "Token response missing id_token"
        case .presentationUnavailable:
            return "Could not present sign-in UI"
        }
    }
}

/// Google OAuth via ASWebAuthenticationSession + PKCE (no SDK).
///
/// Drives the Google sign-in flow for the iOS pairing view. PKCE is used
/// because installed apps are public clients — there's no `client_secret`
/// to keep safe. The flow:
///
/// 1. Generate a code verifier + S256 challenge + opaque `state`.
/// 2. Open `accounts.google.com/o/oauth2/v2/auth` in an in-app Safari sheet,
///    redirect URI = `<reverse-client-id>:/oauth2redirect`.
/// 3. Receive the auth code on the custom URL scheme.
/// 4. POST to `oauth2.googleapis.com/token` with the verifier; pull `id_token`.
///
/// The returned ID token's `aud` claim equals the iOS client ID and is
/// posted to the relay's existing `/auth/google` endpoint, which now
/// accepts both web and iOS audiences (see `GOOGLE_CLIENT_ID_IOS` in
/// the relay env).
@MainActor
final class GoogleOAuthService: NSObject {

    /// Runs the full flow and returns the Google ID token string.
    /// Throws `GoogleOAuthError.userCanceled` when the user dismisses
    /// the sheet — callers should swallow that one silently.
    func signIn(iosClientID: String) async throws -> String {
        let reverseClientID = try GoogleOAuthService.reverseClientID(from: iosClientID)
        // Reverse-client-ID scheme + a path component — Google's iOS clients
        // accept any path on this scheme. Match what gets registered in
        // Google Cloud Console out of the box.
        let redirectURI = "\(reverseClientID):/oauth2redirect"

        let codeVerifier = GoogleOAuthService.generateCodeVerifier()
        let codeChallenge = GoogleOAuthService.codeChallenge(for: codeVerifier)
        let state = GoogleOAuthService.randomURLSafeString(length: 32)
        let nonce = GoogleOAuthService.randomURLSafeString(length: 32)

        let authURL = try GoogleOAuthService.buildAuthURL(
            clientID: iosClientID,
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            state: state,
            nonce: nonce
        )

        let callbackURL = try await presentAuthSession(
            authURL: authURL,
            callbackScheme: reverseClientID
        )

        let (code, returnedState) = try GoogleOAuthService.parseCallback(callbackURL)
        guard returnedState == state else {
            throw GoogleOAuthError.stateMismatch
        }

        let idToken = try await exchangeCodeForIDToken(
            code: code,
            codeVerifier: codeVerifier,
            clientID: iosClientID,
            redirectURI: redirectURI
        )
        return idToken
    }

    // MARK: - Helpers (static so they're unit-testable without a presentation context)

    static func reverseClientID(from clientID: String) throws -> String {
        // `1234567890-abcdefg.apps.googleusercontent.com`
        //   → `com.googleusercontent.apps.1234567890-abcdefg`
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            throw GoogleOAuthError.malformedClientID(clientID)
        }
        let base = String(clientID.dropLast(suffix.count))
        guard !base.isEmpty else {
            throw GoogleOAuthError.malformedClientID(clientID)
        }
        return "com.googleusercontent.apps.\(base)"
    }

    static func generateCodeVerifier() -> String {
        // RFC 7636 — 43–128 chars from the unreserved set. 32 random bytes
        // base64url-encoded lands in that range and exceeds the 256-bit
        // entropy floor Google recommends.
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func buildAuthURL(
        clientID: String,
        redirectURI: String,
        codeChallenge: String,
        state: String,
        nonce: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let url = components.url else {
            throw GoogleOAuthError.tokenExchangeFailed("Failed to build authorize URL")
        }
        return url
    }

    static func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        // Google can return either query (`?code=...`) or fragment params
        // depending on the response_type. For `code` it's the query string.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        if let errorParam = items.first(where: { $0.name == "error" })?.value {
            if errorParam == "access_denied" {
                throw GoogleOAuthError.userCanceled
            }
            throw GoogleOAuthError.tokenExchangeFailed("Google returned error: \(errorParam)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GoogleOAuthError.missingAuthorizationCode
        }
        let state = items.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    // MARK: - Presentation

    private func presentAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: GoogleOAuthError.userCanceled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.missingAuthorizationCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Avoid sharing cookies with Safari — keeps the relay sign-in
            // scoped to the app and prevents leaking the previous Google
            // session in the in-app sheet.
            session.prefersEphemeralWebBrowserSession = true
            guard session.start() else {
                continuation.resume(throwing: GoogleOAuthError.presentationUnavailable)
                return
            }
        }
    }

    // MARK: - Token exchange

    private func exchangeCodeForIDToken(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String
    ) async throws -> String {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthError.tokenExchangeFailed("Invalid token URL")
        }

        let bodyItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = bodyItems
        let bodyString = bodyComponents.percentEncodedQuery ?? ""

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleOAuthError.tokenExchangeFailed("Non-HTTP response")
        }
        if http.statusCode != 200 {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            throw GoogleOAuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(snippet.prefix(200))")
        }
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        guard let idToken = decoded.idToken, !idToken.isEmpty else {
            throw GoogleOAuthError.missingIDToken
        }
        return idToken
    }

    private struct GoogleTokenResponse: Decodable {
        let idToken: String?
        let accessToken: String?
        let expiresIn: Int?
        let tokenType: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }
}

// MARK: - Base64URL helper

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession calls this on the main actor in practice
        // but the protocol isn't annotated. Hop to MainActor synchronously
        // via DispatchQueue.main.sync would deadlock; instead capture from
        // the connected scenes API directly — it's safe from any thread.
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }
}
