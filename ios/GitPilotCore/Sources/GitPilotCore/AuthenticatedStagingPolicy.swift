import Foundation

/// Validation boundary before source enters the native device-only AES-GCM vault.
public enum AuthenticatedStagingPolicy {
    public enum StageError: Error, LocalizedError, Equatable {
        case invalidRepository, invalidPath, missingBlobSHA, unchanged, invalidText, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalidRepository: return "The selected GitHub repository is invalid."
            case .invalidPath: return "The selected branch or file path is invalid."
            case .missingBlobSHA: return "GitHub did not provide a verifiable source blob SHA."
            case .unchanged: return "Change the file before saving a draft."
            case .invalidText: return "Only UTF-8 text without NUL bytes can be staged."
            case .tooLarge: return "This edit exceeds the secure draft size limit."
            }
        }
    }

    public static func validBlobSHA(_ sha: String) -> Bool {
        (sha.utf8.count == 40 || sha.utf8.count == 64) &&
        sha.utf8.allSatisfy {
            (48...57).contains(Int($0)) || (65...70).contains(Int($0)) ||
            (97...102).contains(Int($0))
        }
    }

    public static func stage(
        repository: PublicRepository, branch: String, path: String,
        originalBlobSHA: String, original: String, revised: String
    ) throws -> StagedFileEdit {
        guard let id = Int(exactly: repository.id), id > 0,
              PublicGitHubAPI.validUsername(repository.owner),
              PublicGitHubAPI.validRepositoryName(repository.name),
              repository.fullName == repository.owner + "/" + repository.name else {
            throw StageError.invalidRepository
        }
        guard PublicGitHubAPI.validBranchRef(branch),
              AuthenticatedContentsAPI.validPath(path), !path.isEmpty else {
            throw StageError.invalidPath
        }
        guard validBlobSHA(originalBlobSHA) else { throw StageError.missingBlobSHA }
        guard original != revised else { throw StageError.unchanged }
        guard !original.contains("\u{0000}"), !revised.contains("\u{0000}") else {
            throw StageError.invalidText
        }
        guard original.utf8.count <= 64_000,
              revised.utf8.count <= 200_000 else {
            throw StageError.tooLarge
        }
        return StagedFileEdit(repositoryID: id, repositoryFullName: repository.fullName,
                              path: path, branch: branch, originalBlobSHA: originalBlobSHA,
                              originalContent: original, newContent: revised)
    }
}
