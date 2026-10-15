import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A deliberately read-only boundary for authenticated GitHub API calls.
/// Only /user/repos is exposed. No arbitrary URL, method or Authorization host.
public struct AuthenticatedRepositoryAPI {
    public enum APIError: Error, LocalizedError, Equatable {
        case invalidCredentials, revoked, forbidden, unavailable
        case untrustedResponse, invalidPayload, oversizedResponse, invalidPage
        public var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "GitHub authentication is missing."
            case .revoked: return "GitHub authorization expired. Sign in again."
            case .forbidden: return "GitHub did not authorize access to these repositories."
            case .unavailable: return "Cannot retrieve GitHub repositories right now."
            case .untrustedResponse: return "GitHub returned an untrusted repository response."
            case .invalidPayload: return "GitHub returned invalid repository metadata."
            case .oversizedResponse: return "GitHub returned too much repository data."
            case .invalidPage: return "The repository page is outside the supported limit."
            }
        }
    }

    public struct Page {
        public let items: [PublicRepository]
        public let hasMore: Bool
    }

    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init() {
        self.transport = { request in
            let session = URLSession(configuration: .ephemeral,
                                     delegate: DenyRepositoryRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            return try await session.data(for: request)
        }
    }

    /// Test-only transport injection; production uses ephemeral no-redirect URLSession.
    public init(transport: @escaping Transport) { self.transport = transport }

    public func repositories(token: String, page: Int = 1) async throws -> Page {
        guard page >= 1 && page <= 3 else { throw APIError.invalidPage }
        guard !token.isEmpty, token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) ||
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw APIError.invalidCredentials }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/user/repos"
        components.queryItems = [
            .init(name: "visibility", value: "all"),
            .init(name: "affiliation", value: "owner,collaborator,organization_member"),
            .init(name: "sort", value: "updated"),
            .init(name: "per_page", value: "20"),
            .init(name: "page", value: String(page))
        ]
        guard let url = components.url, GitHubURLPolicy.trustedAPI(url) else {
            throw APIError.untrustedResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitPilot-iOS-authenticated-readonly", forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw APIError.untrustedResponse
        }
        if http.statusCode == 401 { throw APIError.revoked }
        if http.statusCode == 403 { throw APIError.forbidden }
        guard http.statusCode == 200 else { throw APIError.unavailable }
        guard data.count <= 1_500_000 else { throw APIError.oversizedResponse }
        if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let length = Int(contentLength), length > 1_500_000 {
            throw APIError.oversizedResponse
        }
        let results: [PublicRepository]
        do { results = try JSONDecoder().decode([PublicRepository].self, from: data) }
        catch { throw APIError.invalidPayload }
        guard results.count <= 20,
              results.allSatisfy({
                  $0.id > 0 && PublicGitHubAPI.validUsername($0.owner) &&
                  PublicGitHubAPI.validRepositoryName($0.name) &&
                  $0.fullName == "\($0.owner)/\($0.name)"
              }) else { throw APIError.invalidPayload }
        // Never return more than three pages. The final page doesn't imply all
        // private repositories were enumerated; GitHub web remains the fallback.
        return Page(items: results, hasMore: results.count == 20 && page < 3)
    }
}

private final class DenyRepositoryRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
