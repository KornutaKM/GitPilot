import XCTest
import Foundation
import GitPilotCore
@testable import GitPilotCoreSmoke

/// Real iOS CryptoKit + Keychain integration. Does not talk to GitHub.
final class NativeEncryptedStagingTests: XCTestCase {
    override func setUpWithError() throws { try StagedDraftVault.erase() }
    override func tearDownWithError() throws { try StagedDraftVault.erase() }

    private func repository() throws -> PublicRepository {
        try JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":42,"name":"sample","full_name":"octocat/sample","description":null,
         "default_branch":"main","language":"Swift","stargazers_count":0,
         "html_url":null,"private":true}
        """.utf8))
    }

    private func edit(path: String, text: String) throws -> StagedFileEdit {
        try AuthenticatedStagingPolicy.stage(
            repository: repository(), branch: "main", path: path,
            originalBlobSHA: String(repeating: "a", count: 40),
            original: "before", revised: text)
    }

    func testMultipleStagedFilesRoundTripOnlyForOriginalAccount() throws {
        let first = try edit(path: "README.md", text: "updated readme")
        let second = try edit(path: "Sources/App.swift", text: "updated app")
        try StagedDraftVault.save(for: "octocat", edits: [first, second])
        let recovered = try StagedDraftVault.load(for: "OCTOCAT")
        XCTAssertEqual(recovered.map(\.path), ["README.md", "Sources/App.swift"])
        XCTAssertEqual(recovered[0].newContent, "updated readme")
        XCTAssertThrowsError(try StagedDraftVault.load(for: "another-account"))
    }

    func testInvalidOverBudgetSaveDoesNotOverwritePreviousEncryptedDrafts() throws {
        let original = try edit(path: "README.md", text: "safe")
        try StagedDraftVault.save(for: "octocat", edits: [original])
        let many = try (0..<13).map { try edit(path: "file-\($0).txt", text: "modified") }
        XCTAssertThrowsError(try StagedDraftVault.save(for: "octocat", edits: many))
        XCTAssertEqual(try StagedDraftVault.load(for: "octocat"), [original])
    }

    func testClearingStagedFilesErasesKeyAndCiphertext() throws {
        try StagedDraftVault.save(for: "octocat", edits: [
            edit(path: "private.txt", text: "private staging test content")
        ])
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
            .appendingPathComponent("GitPilot", isDirectory: true)
        let ciphertext = try Data(contentsOf:
            folder.appendingPathComponent("staged-drafts-v1.enc"))
        XCTAssertFalse(String(decoding: ciphertext, as: UTF8.self).contains("private staging test content"))
        try StagedDraftVault.save(for: "octocat", edits: [])
        XCTAssertTrue(try StagedDraftVault.load(for: "octocat").isEmpty)
    }
}
