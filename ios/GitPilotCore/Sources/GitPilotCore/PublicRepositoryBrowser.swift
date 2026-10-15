import Foundation

public struct PublicFileEntry: Decodable, Identifiable, Equatable {
    public let name: String
    public let path: String
    public let type: String
    public let size: Int?
    public let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case name, path, type, size
        case htmlURL = "html_url"
    }
    public var id: String { path }
    public var isDirectory: Bool { type == "dir" }
    public var isFile: Bool { type == "file" }
}

public struct PublicFilePreview {
    public let path: String
    public let text: String
    public let htmlURL: URL?
}

public struct PublicCommit: Decodable, Identifiable, Equatable {
    public struct Details: Decodable, Equatable { public let message: String }
    public let sha: String
    public let commit: Details
    public let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case sha, commit
        case htmlURL = "html_url"
    }
    public var id: String { sha }
    public var subject: String { String(commit.message.split(separator: "\n").first ?? "") }
}

public extension PublicGitHubAPI {
    /// Reject traversal and broken refs before using URLComponents.
    static func validRepositoryPath(_ path: String) -> Bool {
        guard path.utf8.count <= 1024, !path.contains("\\"),
              !path.contains("\u{0000}") else { return false }
        return path.isEmpty || path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func validBranchRef(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= 120, !ref.contains(".."),
              !ref.contains("//"), !ref.hasPrefix("-"), !ref.hasPrefix("."),
              !ref.hasSuffix("."), !ref.hasSuffix("/"), !ref.hasSuffix(".lock"),
              !ref.contains("@{") else { return false }
        return ref.utf8.allSatisfy { byte in
            (65...90).contains(Int(byte)) || (97...122).contains(Int(byte)) ||
            (48...57).contains(Int(byte)) || byte == 45 || byte == 95 ||
            byte == 46 || byte == 47
        }
    }

    func directory(
        repository: PublicRepository, branch: String, path: String = ""
    ) async throws -> [PublicFileEntry] {
        let root = try publicRepoPath(repository)
        guard Self.validBranchRef(branch), Self.validRepositoryPath(path) else {
            throw PublicGitHubError.invalidRepository
        }
        let resource = root + "/contents" + (path.isEmpty ? "" : "/" + path)
        let items = try await get(path: resource,
                                  query: [URLQueryItem(name: "ref", value: branch)],
                                  as: [PublicFileEntry].self)
        guard items.count <= 100,
              items.allSatisfy({
                  Self.validRepositoryPath($0.path) &&
                  $0.path.hasPrefix(path.isEmpty ? "" : path + "/")
              }) else { throw PublicGitHubError.oversizedResponse }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func preview(
        repository: PublicRepository, branch: String, file: PublicFileEntry
    ) async throws -> PublicFilePreview {
        guard file.isFile, (file.size ?? 0) <= 64_000 else {
            throw PublicGitHubError.oversizedResponse
        }
        let root = try publicRepoPath(repository)
        guard Self.validBranchRef(branch), Self.validRepositoryPath(file.path),
              !file.path.isEmpty else { throw PublicGitHubError.invalidRepository }
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
        let result = try await get(path: root + "/contents/" + file.path,
                                   query: [URLQueryItem(name: "ref", value: branch)],
                                   as: Content.self)
        guard result.type == "file", result.path == file.path,
              result.size >= 0, result.size <= 64_000,
              result.encoding == "base64",
              let encoded = result.content else { throw PublicGitHubError.invalidResponse }
        let compact = encoded.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact), data.count <= 64_000,
              data.count == result.size,
              let text = String(data: data, encoding: .utf8), !text.contains("\u{0000}") else {
            throw PublicGitHubError.invalidResponse
        }
        return PublicFilePreview(path: file.path, text: text,
                                 htmlURL: Self.safeGitHubWebURL(result.htmlURL))
    }

    func recentCommits(
        repository: PublicRepository, branch: String
    ) async throws -> [PublicCommit] {
        let root = try publicRepoPath(repository)
        guard Self.validBranchRef(branch) else { throw PublicGitHubError.invalidRepository }
        let commits = try await get(path: root + "/commits",
                                    query: [URLQueryItem(name: "sha", value: branch),
                                            URLQueryItem(name: "per_page", value: "12")],
                                    as: [PublicCommit].self)
        guard commits.count <= 12 else { throw PublicGitHubError.invalidResponse }
        return commits
    }

    private func publicRepoPath(_ repo: PublicRepository) throws -> String {
        guard Self.validUsername(repo.owner), Self.validRepositoryName(repo.name),
              repo.fullName == repo.owner + "/" + repo.name, !repo.privateRepository else {
            throw PublicGitHubError.invalidRepository
        }
        return "/repos/" + repo.owner + "/" + repo.name
    }
}
