import Foundation

/// A staged remote edit is plaintext only in memory or inside the encrypted vault.
public struct StagedFileEdit: Codable, Identifiable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let repositoryID: Int
    public let repositoryFullName: String
    public let path: String
    public let branch: String
    public let originalBlobSHA: String
    public let originalContent: String
    public let newContent: String

    public init(repositoryID: Int, repositoryFullName: String, path: String,
                branch: String, originalBlobSHA: String,
                originalContent: String, newContent: String) {
        self.repositoryID = repositoryID
        self.repositoryFullName = repositoryFullName
        self.path = path
        self.branch = branch
        self.originalBlobSHA = originalBlobSHA
        self.originalContent = originalContent
        self.newContent = newContent
    }
    public var id: String { "\(repositoryID):\(branch):\(path)" }
    public var byteCount: Int { newContent.utf8.count }
    public var description: String { "StagedFileEdit(<redacted>)" }
    public var debugDescription: String { description }
}

/// Versioned plaintext *inside* the encrypted on-device vault. Never write it
/// to UserDefaults, a log, or an unprotected file.
public struct StagedDraftEnvelope: Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentVersion = 1
    public let version: Int
    public let accountLogin: String
    public let edits: [StagedFileEdit]

    public var description: String { "StagedDraftEnvelope(account=<redacted>, edits=\(edits.count))" }
    public var debugDescription: String { description }

    public enum ValidationError: LocalizedError, Equatable {
        case wrongAccount, incompatibleVersion, invalidContents
        public var errorDescription: String? {
            switch self {
            case .wrongAccount: return "Saved drafts belong to another GitHub account."
            case .incompatibleVersion: return "Saved drafts were created by an incompatible GitPilot version."
            case .invalidContents: return "Saved drafts are invalid or exceed the staging limits."
            }
        }
    }

    public init(accountLogin: String, edits: [StagedFileEdit]) throws {
        version = Self.currentVersion
        self.accountLogin = accountLogin.lowercased()
        self.edits = edits
        try validate(for: accountLogin)
    }

    public func validate(for account: String) throws {
        guard version == Self.currentVersion else { throw ValidationError.incompatibleVersion }
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              accountLogin.lowercased() == account.lowercased() else {
            throw ValidationError.wrongAccount
        }
        guard edits.count <= 12,
              Set(edits.map(\.id)).count == edits.count,
              edits.reduce(0, { $0 + $1.byteCount }) <= 1_000_000,
              edits.allSatisfy({ edit in
                  edit.repositoryID > 0 && edit.repositoryFullName.split(separator: "/").count == 2 &&
                  !edit.branch.isEmpty && !edit.path.isEmpty && !edit.originalBlobSHA.isEmpty &&
                  edit.originalContent.utf8.count <= 200_000 && edit.byteCount <= 200_000 &&
                  edit.originalContent != edit.newContent
              }) else { throw ValidationError.invalidContents }
    }
}
