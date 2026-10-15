import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The OAuth gateway owns the GitHub App client secret. iOS supplies only
/// one-time code + PKCE verifier or a refresh token over HTTPS.
public enum GitHubOAuthGatewayError: Error, LocalizedError, Equatable {
    case unsafeConfiguration, invalidResponse, accessRevoked, unavailable
    public var errorDescription: String? {
        switch self {
        case .unsafeConfiguration: return "Configure a trusted HTTPS OAuth gateway and callback."
        case .invalidResponse: return "The OAuth server returned invalid credentials."
        case .accessRevoked: return "GitHub authorization expired or was revoked. Sign in again."
        case .unavailable: return "GitHub authorization is temporarily unavailable."
        }
    }
}

public enum GitHubOAuthGatewayPolicy {
    public static func trustedBackend(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard url.scheme?.lowercased() == "https", host.contains("."),
              host != "example.com", host != "localhost", !host.hasSuffix(".invalid"),
              !host.hasSuffix(".example"), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
    }

    public static func endpoint(base: URL, operation: String) -> URL? {
        guard trustedBackend(base), operation == "exchange" || operation == "refresh" else {
            return nil
        }
        let url = base.appendingPathComponent("oauth").appendingPathComponent(operation)
        return trustedBackend(url) ? url : nil
    }
}

/// URLSession delegate must not follow a 30x that could forward a refresh token.
private final class DenyOAuthRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GitHubOAuthGateway {
    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let base: URL
    private let transport: Transport

    public init(base: URL) throws {
        try self.init(base: base, transport: { request in
            let session = URLSession(configuration: .ephemeral,
                                     delegate: DenyOAuthRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            return try await session.data(for: request)
        })
    }

    public init(base: URL, transport: @escaping Transport) throws {
        guard GitHubOAuthGatewayPolicy.trustedBackend(base) else {
            throw GitHubOAuthGatewayError.unsafeConfiguration
        }
        self.base = base
        self.transport = transport
    }

    public func exchange(code: String, verifier: String) async throws -> OAuthCredentials {
        try await request("exchange", payload: ["code": code, "code_verifier": verifier])
    }

    public func refresh(_ credential: OAuthCredentials) async throws -> OAuthCredentials {
        guard credential.canRefresh, let refreshToken = credential.refreshToken else {
            throw GitHubOAuthGatewayError.accessRevoked
        }
        return try await request("refresh", payload: ["refresh_token": refreshToken])
    }

    private func request(_ operation: String, payload: [String: String]) async throws -> OAuthCredentials {
        guard let url = GitHubOAuthGatewayPolicy.endpoint(base: base, operation: operation),
              payload.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }) else {
            throw GitHubOAuthGatewayError.unsafeConfiguration
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.url == url else { throw GitHubOAuthGatewayError.invalidResponse }
        if http.statusCode == 401 { throw GitHubOAuthGatewayError.accessRevoked }
        guard http.statusCode == 200, data.count <= 32_768 else {
            throw GitHubOAuthGatewayError.unavailable
        }
        guard let token = try? JSONDecoder().decode(OAuthTokenPayload.self, from: data),
              let credentials = try? token.validatedCredentials(),
              credentials.refreshToken != nil else {
            throw GitHubOAuthGatewayError.invalidResponse
        }
        return credentials
    }
}
