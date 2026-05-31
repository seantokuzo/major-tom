import CryptoKit
import Foundation

/// Verifies that a discovered LAN host is the *same relay this device paired
/// with*, by challenging it to sign a fresh nonce with the relay identity
/// private key and checking the signature against the pinned public key.
///
/// mDNS is unauthenticated: any LAN peer can advertise `_majortom._tcp` and
/// echo the relay's (public) fingerprint. The trust anchor is therefore not the
/// fingerprint but *possession of the private key*, proven here. A host that
/// merely replays the fingerprint cannot produce a valid signature, so it fails
/// the challenge and never receives the session cookie. (This defeats an
/// impersonating "first responder"; it does NOT by itself defeat an on-path
/// MITM that forwards the nonce to the real relay — that needs TLS channel
/// binding, tracked as follow-up hardening.)
enum RelayIdentityVerifier {
    /// Domain-separation prefix for challenge signatures. The relay signs
    /// `challengeContext || nonce` (never the bare nonce), so we verify over the
    /// identical byte construction.
    ///
    /// CANONICAL SOURCE: `relay/src/routes/identity.ts` (`CHALLENGE_CONTEXT`).
    /// This string MUST stay byte-for-byte identical to it — a drift silently
    /// breaks every LAN verification. The DEBUG `runSelfTest()` below verifies a
    /// real relay-produced signature through this exact path so such a drift
    /// trips immediately in a debug build.
    static let challengeContext = "major-tom/relay-identity/v1:"

    // MARK: - base64url

    /// Decode a base64url string (unpadded) to `Data`. Foundation's
    /// `Data(base64Encoded:)` only accepts *standard* base64, so translate the
    /// alphabet and re-pad first. The relay sends `publicKey`/`signature` as
    /// base64url.
    static func data(fromBase64url s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder != 0 {
            b64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: b64)
    }

    /// Encode `Data` as unpadded base64url.
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Fingerprint

    /// `base64url(SHA256(rawPublicKey))` — matches the relay's mDNS TXT `fp`.
    /// Used only as a fast discovery filter; the signature is the real anchor.
    static func fingerprint(forRawPublicKey raw: Data) -> String {
        base64url(Data(SHA256.hash(data: raw)))
    }

    // MARK: - Pure verification

    /// Verify an Ed25519 `signature` over `challengeContext || nonce` against a
    /// pinned raw (32-byte) public key. Pure — no I/O — so it is exercised
    /// directly by `runSelfTest()` with a real relay vector.
    static func isValidSignature(_ signature: Data, nonce: Data, pinnedRawPublicKey raw: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            return false
        }
        var message = Data(challengeContext.utf8)
        message.append(nonce)
        return key.isValidSignature(signature, for: message)
    }

    // MARK: - Networked challenge

    /// POST a fresh 32-byte nonce to `<baseURL>/identity/challenge` and verify
    /// the returned signature against the pinned public key. Returns `true` ONLY
    /// if the host proves possession of the pinned identity's private key.
    /// Best-effort: any transport/parse error or non-200 returns `false`
    /// (caller falls back to the tunnel).
    static func challenge(baseURL: String, pinnedPublicKeyBase64url pinned: String) async -> Bool {
        guard let pinnedRaw = data(fromBase64url: pinned),
              let url = URL(string: "\(baseURL)/identity/challenge") else {
            return false
        }

        // SystemRandomNumberGenerator is the platform CSPRNG on Apple OSes.
        let nonce = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The relay decodes the nonce with `Buffer.from(nonce, 'base64')` —
        // send STANDARD base64 (not base64url).
        request.httpBody = try? JSONEncoder().encode(["nonce": nonce.base64EncodedString()])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChallengeResponse.self, from: data),
              let signature = self.data(fromBase64url: parsed.signature) else {
            return false
        }

        // Verify against the PINNED key (not the key the host reports): a host
        // that signs with some other key it controls fails here.
        return isValidSignature(signature, nonce: nonce, pinnedRawPublicKey: pinnedRaw)
    }

    private struct ChallengeResponse: Decodable {
        let signature: String
    }

    #if DEBUG
    /// In-process end-to-end guard (advisory #3 in
    /// docs/HANDOFF-RELAY-IDENTITY-BINDING.md): verify a REAL relay-produced
    /// Ed25519 vector through the exact path the app uses. If `challengeContext`,
    /// the base64url decode, or the CryptoKit wiring ever drift from the relay,
    /// this trips immediately in a debug build.
    ///
    /// SINGLE SOURCE OF TRUTH (#180): this quadruple is pinned identically in the
    /// relay CI lane — `relay/src/routes/__tests__/identity.test.ts`, the
    /// "canonical /identity/challenge signed-byte vector" suite. Both sides
    /// derive it from the SAME deterministic Ed25519 key (PKCS#8 from raw seed
    /// 0x01..0x20) over the SAME byte construction as
    /// `relay/src/identity/relay-identity.ts`
    /// (`sign(null, utf8(CHALLENGE_CONTEXT) || nonce, ed25519PrivKey)`), with the
    /// nonce expressed as STANDARD base64. If you regenerate one side, regenerate
    /// the other identically or the iOS↔relay handshake desyncs silently.
    static func runSelfTest() {
        let publicKeyB64u = "ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ"
        let nonceB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
        let signatureB64u = "Q7L_CUIA7y7nO6T7uOd0ipZjlKvVA_wKGXGgZK0ZkEz5aei-B1jB1gRXHYcoLrOUaLKFWysFS84zOdAjpcfmCQ"
        let expectedFingerprint = "ZbYGc9btiEvwHCwiLYKtoHQPKawzVdapJcgfF_R6J7g"

        guard let raw = data(fromBase64url: publicKeyB64u),
              let nonce = Data(base64Encoded: nonceB64),
              let signature = data(fromBase64url: signatureB64u) else {
            assertionFailure("RelayIdentityVerifier self-test: fixture failed to decode")
            return
        }
        assert(
            isValidSignature(signature, nonce: nonce, pinnedRawPublicKey: raw),
            "RelayIdentityVerifier self-test FAILED — challengeContext/base64url/CryptoKit drifted from the relay"
        )
        assert(
            fingerprint(forRawPublicKey: raw) == expectedFingerprint,
            "RelayIdentityVerifier fingerprint self-test FAILED — SHA256/base64url drifted from the relay"
        )
    }
    #endif
}
