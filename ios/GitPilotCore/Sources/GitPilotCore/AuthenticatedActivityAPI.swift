import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Account-scoped GitHub activity. It exposes only named GET endpoints;
/// review submission, merges and Actions mutations are deliberately absent.
public struct AuthenticatedActivityAPI {
    public enum ActivityError: Error, LocalizedError, Equatable {
        case invalidInput, revoked, forbidden, missing, unavailable
        case untrustedResponse, oversizedResponse, invalidPayload
        public var errorDescription: String? {
            switch self {
            case .invalidInput: return "The repository, identifier or page is invalid."
            case .revoked: return "GitHub authorization expired. Sign in again."
            case .forbidden: return "GitHub denied access to this resource."
            case .missing: return "This GitHub resource is unavailable or was deleted."
            case .unavailable: return "GitHub activity is temporarily unavailable."
            case .untrustedResponse: return "GitHub returned an untrusted activity response."
            case .oversizedResponse: return "GitHub returned too much activity data."
            case .invalidPayload: return "GitHub returned invalid activity data."
            }
        }
    }

    public struct Page<Item> {
        public let items: [Item]
        public let hasMore: Bool
    }

    public struct PullFile: Decodable, Identifiable {
        public let filename: String
        public let status: String
        public let additions: Int
        public let deletions: Int
        public let patch: String?
        public let blobURL: URL?
        public var id: String { filename }

        enum CodingKeys: String, CodingKey {
            case filename, status, additions, deletions, patch
            case blobURL = "blob_url"
        }
    }

    public struct Comment: Decodable, Identifiable {
        public struct Author: Decodable { public let login: String }
        public let id: Int64
        public let body: String?
        public let user: Author?
        public let createdAt: String
        public let path: String?
        public let line: Int?
        public let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case id, body, user, path, line
            case createdAt = "created_at", htmlURL = "html_url"
        }
    }

    public struct Discussion {
        public let issueComments: [Comment]
        public let reviewComments: [Comment]
    }

    public struct Job: Decodable, Identifiable {
        public let id: Int64
        public let name: String
        public let status: String
        public let conclusion: String?
        public let htmlURL: URL?
        public let startedAt: String?
        public let completedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name, status, conclusion
            case htmlURL = "html_url", startedAt = "started_at"
            case completedAt = "completed_at"
        }
    }

    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init() {
        self.transport = { request in
            let session = URLSession(configuration: .ephemeral,
                                     delegate: DenyActivityRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            return try await session.data(for: request)
        }
    }

    /// Injects an offline transport for regression testing.
    public init(transport: @escaping Transport) { self.transport = transport }

    private func route(_ repository: PublicRepository, token: String) throws -> String {
        guard repository.id > 0,
              PublicGitHubAPI.validUsername(repository.owner),
              PublicGitHubAPI.validRepositoryName(repository.name),
              repository.fullName == "\(repository.owner)/\(repository.name)",
              !token.isEmpty && token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) ||
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw ActivityError.invalidInput }
        return "/repos/\(repository.owner)/\(repository.name)"
    }

    private func get<T: Decodable>(
        path: String, query: [URLQueryItem], token: String, as type: T.Type
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = query
        guard let url = components.url, GitHubURLPolicy.trustedAPI(url) else {
            throw ActivityError.untrustedResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitPilot-iOS-private-activity-readonly", forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw ActivityError.untrustedResponse
        }
        if http.statusCode == 401 { throw ActivityError.revoked }
        if http.statusCode == 403 { throw ActivityError.forbidden }
        if http.statusCode == 404 { throw ActivityError.missing }
        guard http.statusCode == 200 else { throw ActivityError.unavailable }
        guard data.count <= 1_200_000 else { throw ActivityError.oversizedResponse }
        if let raw = http.value(forHTTPHeaderField: "Content-Length"),
           let declared = Int(raw), declared > 1_200_000 {
            throw ActivityError.oversizedResponse
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ActivityError.invalidPayload }
    }

    /// Up to three pages of twenty open PRs in a selected repository.
    public func pullRequests(
        repository: PublicRepository, token: String, page: Int = 1
    ) async throws -> Page<PublicPullRequest> {
        let base = try route(repository, token: token)
        guard (1...3).contains(page) else { throw ActivityError.invalidInput }
        let count = 20
        let items = try await get(
            path: base + "/pulls",
            query: [.init(name: "state", value: "open"),
                    .init(name: "sort", value: "updated"),
                    .init(name: "direction", value: "desc"),
                    .init(name: "per_page", value: String(count)),
                    .init(name: "page", value: String(page))],
            token: token, as: [PublicPullRequest].self
        )
        guard items.count <= count, items.allSatisfy({ $0.id > 0 && $0.number > 0 }) else {
            throw ActivityError.invalidPayload
        }
        return Page(items: items, hasMore: items.count == count && page < 3)
    }

    /// First thirty changed files only; no misleading "all files" claim.
    public func pullFiles(
        repository: PublicRepository, number: Int, token: String
    ) async throws -> [PullFile] {
        let base = try route(repository, token: token)
        guard number > 0 && number <= 1_000_000_000 else { throw ActivityError.invalidInput }
        let files = try await get(
            path: base + "/pulls/\(number)/files",
            query: [.init(name: "per_page", value: "30"), .init(name: "page", value: "1")],
            token: token, as: [PullFile].self
        )
        guard files.count <= 30, files.allSatisfy({
            $0.filename.utf8.count <= 1024 && !$0.filename.isEmpty &&
            $0.additions >= 0 && $0.deletions >= 0 &&
            ($0.patch?.utf8.count ?? 0) <= 80_000
        }) else { throw ActivityError.invalidPayload }
        return files
    }

    /// Issue and inline review comments are separate GitHub REST resources.
    /// Both samples are explicitly bounded to the first twenty comments.
    public func discussion(
        repository: PublicRepository, number: Int, token: String
    ) async throws -> Discussion {
        let base = try route(repository, token: token)
        guard number > 0 && number <= 1_000_000_000 else { throw ActivityError.invalidInput }
        let query: [URLQueryItem] = [
            .init(name: "per_page", value: "20"), .init(name: "page", value: "1")
        ]
        let issues = try await get(path: base + "/issues/\(number)/comments",
                                   query: query, token: token, as: [Comment].self)
        try Task.checkCancellation()
        let reviews = try await get(path: base + "/pulls/\(number)/comments",
                                    query: query, token: token, as: [Comment].self)
        guard issues.count <= 20, reviews.count <= 20,
              (issues + reviews).allSatisfy({
                  $0.id > 0 && ($0.body?.utf8.count ?? 0) <= 32_000
              }) else { throw ActivityError.invalidPayload }
        return Discussion(issueComments: issues, reviewComments: reviews)
    }

    /// Up to sixty recent workflow runs per selected repository.
    public func workflowRuns(
        repository: PublicRepository, token: String, page: Int = 1
    ) async throws -> Page<PublicWorkflowRun> {
        let base = try route(repository, token: token)
        guard (1...3).contains(page) else { throw ActivityError.invalidInput }
        struct Container: Decodable {
            let workflowRuns: [PublicWorkflowRun]
            enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
        }
        let count = 20
        let payload = try await get(
            path: base + "/actions/runs",
            query: [.init(name: "per_page", value: String(count)),
                    .init(name: "page", value: String(page))],
            token: token, as: Container.self
        )
        guard payload.workflowRuns.count <= count,
              payload.workflowRuns.allSatisfy({ $0.id > 0 }) else {
            throw ActivityError.invalidPayload
        }
        return Page(items: payload.workflowRuns,
                    hasMore: payload.workflowRuns.count == count && page < 3)
    }

    /// A single bounded page of jobs for a particular run.
    public func workflowJobs(
        repository: PublicRepository, runID: Int64, token: String
    ) async throws -> [Job] {
        let base = try route(repository, token: token)
        guard runID > 0 else { throw ActivityError.invalidInput }
        struct Container: Decodable { let jobs: [Job] }
        let payload = try await get(
            path: base + "/actions/runs/\(runID)/jobs",
            query: [.init(name: "per_page", value: "50"),
                    .init(name: "page", value: "1")],
            token: token, as: Container.self
        )
        guard payload.jobs.count <= 50, payload.jobs.allSatisfy({
            $0.id > 0 && !$0.name.isEmpty && $0.name.utf8.count <= 256
        }) else { throw ActivityError.invalidPayload }
        return payload.jobs
    }
}

private final class DenyActivityRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
