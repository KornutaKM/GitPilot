import Foundation

/// A staged remote edit is plaintext only in memory or inside the encrypted vault.
struct StagedFileEdit: Codable, Identifiable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let repositoryID: Int
    let repositoryFullName: String
    let path: String
    let branch: String
    let originalBlobSHA: String
    let originalContent: String
    let newContent: String

    var id: String { "\(repositoryID):\(branch):\(path)" }
    var byteCount: Int { newContent.utf8.count }
    var description: String { "StagedFileEdit(<redacted>)" }
    var debugDescription: String { description }
}

/// Versioned plaintext *inside* the encrypted on-device vault. Never write it
/// to UserDefaults, a log, or an unprotected file.
struct StagedDraftEnvelope: Codable, CustomStringConvertible, CustomDebugStringConvertible {
    static let currentVersion = 1
    let version: Int
    let accountLogin: String
    let edits: [StagedFileEdit]

    var description: String { "StagedDraftEnvelope(account=<redacted>, edits=\(edits.count))" }
    var debugDescription: String { description }

    enum ValidationError: LocalizedError, Equatable {
        case wrongAccount, incompatibleVersion, invalidContents
        var errorDescription: String? {
            switch self {
            case .wrongAccount: return "Saved drafts belong to another GitHub account."
            case .incompatibleVersion: return "Saved drafts were created by an incompatible GitPilot version."
            case .invalidContents: return "Saved drafts are invalid or exceed the staging limits."
            }
        }
    }

    init(accountLogin: String, edits: [StagedFileEdit]) throws {
        version = Self.currentVersion
        self.accountLogin = accountLogin.lowercased()
        self.edits = edits
        try validate(for: accountLogin)
    }

    func validate(for account: String) throws {
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
