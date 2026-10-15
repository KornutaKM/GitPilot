import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PublicGitHubError: Error, LocalizedError, Equatable {
    case invalidUsername, invalidRepository, untrustedResponse, rateLimited
    case notFound, http(Int), oversizedResponse, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidUsername: return "Enter a valid GitHub username."
        case .invalidRepository: return "GitHub returned an invalid repository identifier."
        case .untrustedResponse: return "GitHub returned an untrusted API redirect."
        case .rateLimited: return "GitHub's public API rate limit was reached. Retry later."
        case .notFound: return "That public GitHub resource was not found."
        case .http(let code): return "GitHub request failed (HTTP \(code))."
        case .oversizedResponse: return "The GitHub response exceeded the safe preview limit."
        case .invalidResponse: return "GitHub returned invalid or unexpected data."
        }
    }
}

/// Credentials and write methods are intentionally absent. A public workspace
/// has a strictly bounded request budget; it does not crawl entire organizations.
public struct PublicGitHubAPI {
    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.transport = transport
    }

    public static func validUsername(_ value: String) -> Bool {
        let chars = Array(value)
        guard !chars.isEmpty && chars.count <= 39,
              chars.first?.isASCIIAlphaNumeric == true,
              chars.last?.isASCIIAlphaNumeric == true else { return false }
        return chars.allSatisfy { $0.isASCIIAlphaNumeric || $0 == "-" }
    }

    public static func validRepositoryName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 100, value != ".", value != ".." else { return false }
        return value.allSatisfy { $0.isASCIIAlphaNumeric || $0 == "-" || $0 == "_" || $0 == "." }
    }

    public static func safeGitHubWebURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com",
              (url.port == nil || url.port == 443),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    func get<T: Decodable>(
        path: String, query: [URLQueryItem], as type: T.Type
    ) async throws -> T {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.github.com"
        parts.path = path
        parts.queryItems = query
        guard let url = parts.url, GitHubURLPolicy.trustedAPI(url) else {
            throw PublicGitHubError.untrustedResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitPilot-iOS-read-only-alpha", forHTTPHeaderField: "User-Agent")
        // No Authorization header exists in this client.
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              let responseURL = http.url, GitHubURLPolicy.trustedAPI(responseURL),
              responseURL.path == url.path else {
            throw PublicGitHubError.untrustedResponse
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            throw PublicGitHubError.rateLimited
        }
        if http.statusCode == 404 { throw PublicGitHubError.notFound }
        guard (200..<300).contains(http.statusCode) else {
            throw PublicGitHubError.http(http.statusCode)
        }
        guard data.count <= 1_500_000 else { throw PublicGitHubError.oversizedResponse }
        if let declared = http.value(forHTTPHeaderField: "Content-Length"),
           let bytes = Int(declared), bytes > 1_500_000 {
            throw PublicGitHubError.oversizedResponse
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw PublicGitHubError.invalidResponse }
    }

    public func repositories(username: String, page: Int = 1) async throws -> PublicRepositoryPage {
        guard Self.validUsername(username) else { throw PublicGitHubError.invalidUsername }
        guard page >= 1 && page <= 3 else { throw PublicGitHubError.invalidResponse }
        let repos = try await get(
            path: "/users/\(username)/repos",
            query: [URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "per_page", value: "12"),
                    URLQueryItem(name: "page", value: String(page))],
            as: [PublicRepository].self
        )
        guard repos.count <= 12, repos.allSatisfy({ !$0.privateRepository }) else {
            throw PublicGitHubError.invalidResponse
        }
        return PublicRepositoryPage(repositories: repos, hasMore: repos.count == 12 && page < 3)
    }

    public func pullRequests(repository: PublicRepository) async throws -> [PublicPullRequest] {
        guard Self.validRepositoryName(repository.name),
              Self.validUsername(repository.owner) else { throw PublicGitHubError.invalidRepository }
        let items = try await get(
            path: "/repos/\(repository.owner)/\(repository.name)/pulls",
            query: [URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "per_page", value: "15")],
            as: [PublicPullRequest].self
        )
        guard items.count <= 15 else { throw PublicGitHubError.invalidResponse }
        return items
    }

    public func workflowRuns(repository: PublicRepository) async throws -> [PublicWorkflowRun] {
        guard Self.validRepositoryName(repository.name),
              Self.validUsername(repository.owner) else { throw PublicGitHubError.invalidRepository }
        struct Wrapper: Decodable { let workflowRuns: [PublicWorkflowRun]
            enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
        }
        let result = try await get(
            path: "/repos/\(repository.owner)/\(repository.name)/actions/runs",
            query: [URLQueryItem(name: "per_page", value: "10")],
            as: Wrapper.self
        )
        guard result.workflowRuns.count <= 10 else { throw PublicGitHubError.invalidResponse }
        return result.workflowRuns
    }

    /// One page of repos + up to eight detail requests. Request failures surface
    /// explicitly and never get interpreted as an all-green GitHub workspace.
    public func workspace(username: String) async throws -> PublicWorkspaceSnapshot {
        let page = try await repositories(username: username)
        var pulls: [PublicPullRequest] = []
        var runs: [PublicWorkflowRun] = []
        var warnings: [String] = []
        let monitored = Array(page.repositories.prefix(4))
        for repo in monitored {
            try Task.checkCancellation()
            do { pulls += try await pullRequests(repository: repo) }
            catch is CancellationError { throw CancellationError() }
            catch { warnings.append("PRs unavailable for \(repo.fullName).") }
            try Task.checkCancellation()
            do { runs += try await workflowRuns(repository: repo) }
            catch is CancellationError { throw CancellationError() }
            catch { warnings.append("Actions unavailable for \(repo.fullName).") }
        }
        return PublicWorkspaceSnapshot(
            username: username,
            repositories: page.repositories,
            pullRequests: pulls.sorted { $0.updatedAt > $1.updatedAt },
            workflows: runs.sorted { $0.updatedAt > $1.updatedAt },
            warnings: warnings,
            monitoredRepositories: monitored.count,
            hasMoreRepositories: page.hasMore
        )
    }
}

private extension Character {
    var isASCIIAlphaNumeric: Bool {
        unicodeScalars.count == 1 && unicodeScalars.allSatisfy {
            (65...90).contains(Int($0.value)) ||
            (97...122).contains(Int($0.value)) ||
            (48...57).contains(Int($0.value))
        }
    }
}
