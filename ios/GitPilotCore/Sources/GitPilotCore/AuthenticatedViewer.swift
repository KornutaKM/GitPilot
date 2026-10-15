import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Login verification is the only authenticated API operation enabled in this
/// migration slice. PR merges, comments, workflow actions and file writes remain off.
public struct GitHubAuthenticatedViewer {
    public enum ViewerError: Error, LocalizedError, Equatable {
        case invalidToken, untrustedResponse, revoked, unavailable
        public var errorDescription: String? {
            switch self {
            case .invalidToken: return "The GitHub credential is invalid."
            case .untrustedResponse: return "GitHub returned an unexpected authenticated response."
            case .revoked: return "GitHub access has expired. Sign in again."
            case .unavailable: return "Cannot verify GitHub login right now."
            }
        }
    }

    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        let session = URLSession(configuration: .ephemeral,
                                 delegate: DenyViewerRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }) {
        self.transport = transport
    }

    public func verifiedLogin(token: String) async throws -> String {
        guard !token.isEmpty, token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) ||
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw ViewerError.invalidToken }
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitPilot-iOS-OAuth-RC3", forHTTPHeaderField: "User-Agent")
        let (body, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw ViewerError.untrustedResponse
        }
        if http.statusCode == 401 { throw ViewerError.revoked }
        guard http.statusCode == 200, body.count <= 16_384 else {
            throw ViewerError.unavailable
        }
        struct Viewer: Decodable { let login: String }
        guard let decoded = try? JSONDecoder().decode(Viewer.self, from: body),
              PublicGitHubAPI.validUsername(decoded.login) else {
            throw ViewerError.untrustedResponse
        }
        return decoded.login
    }
}

private final class DenyViewerRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
