import Foundation
import AuthenticationServices
import CryptoKit
import Security
import GitPilotCore

/// RC3 GitHub App OAuth + PKCE, never a client secret in the iOS application.
/// HTTPS callback handling requires iOS 17.4+ and an operator-owned domain.
@MainActor
final class OAuthLogin: NSObject {
    static let shared = OAuthLogin()
    private var browserSession: ASWebAuthenticationSession?

    enum LoginError: LocalizedError {
        case notConfigured, randomFailure, invalidCallback, cannotStart, unsupportedOS
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Configure the GitHub App and HTTPS OAuth gateway before signing in."
            case .randomFailure: return "Cannot generate a secure OAuth nonce."
            case .invalidCallback: return "GitHub sign-in returned an invalid callback or state."
            case .cannotStart: return "Cannot open the system GitHub sign-in window."
            case .unsupportedOS: return "Secure GitHub OAuth requires iOS 17.4 or later."
            }
        }
    }

    private func nonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw LoginError.randomFailure
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var isConfigured: Bool {
        OAuthConfiguration.isConfigured &&
            OAuthConfiguration.backendURL.map(GitHubOAuthGatewayPolicy.trustedBackend) == true
    }

    func signIn() async throws -> OAuthCredentials {
        guard isConfigured, let clientID = OAuthConfiguration.clientID,
              let backend = OAuthConfiguration.backendURL,
              let callbackURL = OAuthConfiguration.callbackURL else { throw LoginError.notConfigured }
        guard #available(iOS 17.4, *) else { throw LoginError.unsupportedOS }
        let state = try nonce()
        let verifier = try nonce()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let url = try OAuthAuthorizationPolicy.authorizeURL(
            clientID: clientID, callback: callbackURL, state: state, codeChallenge: challenge
        )
        let callback: URL = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url, callback: .https(host: callbackURL.host!, path: callbackURL.path)
            ) { [weak self] responseURL, error in
                Task { @MainActor in
                    self?.browserSession = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let responseURL { continuation.resume(returning: responseURL) }
                    else { continuation.resume(throwing: LoginError.invalidCallback) }
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            browserSession = session
            if !session.start() {
                browserSession = nil
                continuation.resume(throwing: LoginError.cannotStart)
            }
        }
        guard let code = OAuthValidation.code(from: callback, state: state,
                                               expectedCallback: callbackURL) else {
            throw LoginError.invalidCallback
        }
        return try await GitHubOAuthGateway(base: backend).exchange(code: code, verifier: verifier)
    }

    func cancelSignIn() {
        browserSession?.cancel()
        browserSession = nil
    }

    func refresh(_ credential: OAuthCredentials) async throws -> OAuthCredentials {
        guard let backend = OAuthConfiguration.backendURL else { throw LoginError.notConfigured }
        return try await GitHubOAuthGateway(base: backend).refresh(credential)
    }
}
