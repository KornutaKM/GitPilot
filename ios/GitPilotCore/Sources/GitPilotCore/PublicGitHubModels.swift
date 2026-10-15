import Foundation

/// Public repository metadata, decoded from GitHub REST. Private account data is
/// deliberately outside this read-only client and never cached in UserDefaults.
public struct PublicRepository: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let fullName: String
    public let description: String?
    public let defaultBranch: String
    public let language: String?
    public let stargazersCount: Int
    public let htmlURL: URL?
    public let privateRepository: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, language
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case stargazersCount = "stargazers_count"
        case htmlURL = "html_url"
        case privateRepository = "private"
    }
    public var owner: String { String(fullName.split(separator: "/").first ?? "") }
}

public struct PublicPullRequest: Decodable, Identifiable, Equatable {
    public struct Author: Decodable, Equatable { public let login: String }
    public struct Ref: Decodable, Equatable { public let ref: String }
    public let id: Int64
    public let number: Int
    public let title: String
    public let draft: Bool
    public let user: Author
    public let head: Ref
    public let base: Ref
    public let htmlURL: URL?
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, number, title, draft, user, head, base
        case htmlURL = "html_url", updatedAt = "updated_at"
    }
}

public struct PublicWorkflowRun: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String?
    public let displayTitle: String?
    public let status: String
    public let conclusion: String?
    public let headBranch: String?
    public let htmlURL: URL?
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case displayTitle = "display_title"
        case headBranch = "head_branch"
        case htmlURL = "html_url", updatedAt = "updated_at"
    }
    public var title: String { displayTitle ?? name ?? "Workflow run" }
    public var failed: Bool { conclusion == "failure" || conclusion == "timed_out" }
    public var running: Bool {
        status == "in_progress" || status == "queued" || status == "waiting" || status == "pending"
    }
}

public struct PublicRepositoryPage {
    public let repositories: [PublicRepository]
    public let hasMore: Bool
}

public struct PublicWorkspaceSnapshot {
    public let username: String
    public let repositories: [PublicRepository]
    public let pullRequests: [PublicPullRequest]
    public let workflows: [PublicWorkflowRun]
    public let warnings: [String]
    public let monitoredRepositories: Int
    public let hasMoreRepositories: Bool

    public var isPartial: Bool {
        !warnings.isEmpty || hasMoreRepositories ||
            repositories.count > monitoredRepositories
    }
}
