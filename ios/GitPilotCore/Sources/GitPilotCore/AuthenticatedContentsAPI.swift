import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A second independent, GET-only authenticated boundary for browsing the
/// selected repository. Nothing is cached and there is no mutation interface.
public struct AuthenticatedContentsAPI {
    public enum ReadError: Error, LocalizedError, Equatable {
        case invalidInput, revoked, forbidden, unavailable
        case untrustedResponse, oversizedResponse, invalidPayload
        public var errorDescription: String? {
            switch self {
            case .invalidInput: return "The GitHub repository, branch or file path is invalid."
            case .revoked: return "GitHub authorization expired. Sign in again."
            case .forbidden: return "GitHub denied access to this repository."
            case .unavailable: return "Repository files are temporarily unavailable."
            case .untrustedResponse: return "GitHub returned an untrusted file response."
            case .oversizedResponse: return "The requested file or directory exceeds the safe preview limit."
            case .invalidPayload: return "GitHub returned an invalid file preview."
            }
        }
    }

    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init() {
        self.transport = { request in
            let session = URLSession(configuration: .ephemeral,
                                     delegate: DenyAuthenticatedContentRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            return try await session.data(for: request)
        }
    }

    public init(transport: @escaping Transport) { self.transport = transport }

    public static func validPath(_ value: String) -> Bool {
        guard value.utf8.count <= 1024,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.contains("\\"), !value.contains("?"), !value.contains("#"),
              !value.contains("%") else { return false }
        return value.isEmpty || value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func validate(_ repository: PublicRepository, branch: String, path: String,
                          token: String) throws -> String {
        guard repository.id > 0,
              PublicGitHubAPI.validUsername(repository.owner),
              PublicGitHubAPI.validRepositoryName(repository.name),
              repository.fullName == "\(repository.owner)/\(repository.name)",
              PublicGitHubAPI.validBranchRef(branch), Self.validPath(path),
              !token.isEmpty && token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) ||
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw ReadError.invalidInput }
        return "/repos/\(repository.owner)/\(repository.name)/contents" +
            (path.isEmpty ? "" : "/" + path)
    }

    private func fetch<T: Decodable>(
        path: String, branch: String, token: String, as type: T.Type
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]
        guard let url = components.url, GitHubURLPolicy.trustedAPI(url) else {
            throw ReadError.untrustedResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitPilot-iOS-authenticated-files-readonly", forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw ReadError.untrustedResponse
        }
        if http.statusCode == 401 { throw ReadError.revoked }
        if http.statusCode == 403 { throw ReadError.forbidden }
        guard http.statusCode == 200 else { throw ReadError.unavailable }
        guard data.count <= 1_200_000 else { throw ReadError.oversizedResponse }
        if let length = http.value(forHTTPHeaderField: "Content-Length"),
           let size = Int(length), size > 1_200_000 {
            throw ReadError.oversizedResponse
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ReadError.invalidPayload }
    }

    /// A single directory only. Symlinks/submodules are displayed as metadata,
    /// never resolved to a different repo or hostname.
    public func directory(
        repository: PublicRepository, branch: String, path: String = "", token: String
    ) async throws -> [PublicFileEntry] {
        let route = try validate(repository, branch: branch, path: path, token: token)
        let items = try await fetch(path: route, branch: branch, token: token,
                                    as: [PublicFileEntry].self)
        guard items.count <= 100, items.allSatisfy({
            Self.validPath($0.path) && !$0.path.isEmpty &&
            $0.path.hasPrefix(path.isEmpty ? "" : path + "/")
        }) else { throw ReadError.invalidPayload }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// File content is never persisted; binary or oversized data is rejected.
    public func preview(
        repository: PublicRepository, branch: String,
        file: PublicFileEntry, token: String
    ) async throws -> PublicFilePreview {
        guard file.isFile, let declaredSize = file.size,
              declaredSize >= 0 && declaredSize <= 64_000, !file.path.isEmpty else {
            throw ReadError.oversizedResponse
        }
        let route = try validate(repository, branch: branch, path: file.path, token: token)
        struct Content: Decodable {
            let type: String
            let path: String
            let size: Int
            let encoding: String?
            let content: String?
            let htmlURL: URL?
            enum CodingKeys: String, CodingKey {
                case type, path, size, encoding, content
                case htmlURL = "html_url"
            }
        }
        let payload = try await fetch(path: route, branch: branch, token: token,
                                      as: Content.self)
        guard payload.type == "file", payload.path == file.path,
              payload.size >= 0, payload.size <= 64_000,
              payload.encoding == "base64", let encoded = payload.content else {
            throw ReadError.invalidPayload
        }
        let base64 = encoded.filter { !$0.isWhitespace }
        guard let decoded = Data(base64Encoded: base64),
              decoded.count == payload.size, decoded.count <= 64_000,
              let text = String(data: decoded, encoding: .utf8),
              !text.contains("\u{0000}") else { throw ReadError.invalidPayload }
        return PublicFilePreview(path: file.path, text: text,
                                 htmlURL: PublicGitHubAPI.safeGitHubWebURL(payload.htmlURL))
    }
}

private final class DenyAuthenticatedContentRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
