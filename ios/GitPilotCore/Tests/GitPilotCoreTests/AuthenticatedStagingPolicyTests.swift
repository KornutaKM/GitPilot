import XCTest
import Foundation
@testable import GitPilotCore

final class AuthenticatedStagingPolicyTests: XCTestCase {
    private var repo: PublicRepository {
        try! JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":42,"name":"secret","full_name":"Octocat/secret","description":null,
         "default_branch":"main","language":"Swift","stargazers_count":0,
         "html_url":null,"private":true}
        """.utf8))
    }
    private var sha: String { String(repeating: "a", count: 40) }

    func testValidDraftContainsOriginalGitBlobIDAndNoRemoteWrite() throws {
        let edit = try AuthenticatedStagingPolicy.stage(
            repository: repo, branch: "main", path: "Sources/File.swift",
            originalBlobSHA: sha, original: "let x = 1", revised: "let x = 2")
        XCTAssertEqual(edit.repositoryID, 42)
        XCTAssertEqual(edit.originalBlobSHA, sha)
        XCTAssertEqual(edit.newContent, "let x = 2")
        XCTAssertFalse(String(reflecting: edit).contains("let x = 2"))
    }

    func testSHAValidationRejectsHeaderInjectionAndMissingChecksums() {
        for value in ["", "123", String(repeating: "g", count: 40),
                      String(repeating: "a", count: 39),
                      String(repeating: "a", count: 65),
                      String(repeating: "a", count: 39) + "\n"] {
            XCTAssertFalse(AuthenticatedStagingPolicy.validBlobSHA(value))
            XCTAssertThrowsError(try AuthenticatedStagingPolicy.stage(
                repository: repo, branch: "main", path: "File.swift",
                originalBlobSHA: value, original: "old", revised: "new"))
        }
        XCTAssertTrue(AuthenticatedStagingPolicy.validBlobSHA(String(repeating: "f", count: 64)))
    }

    func testUnchangedOrBinaryFilesCannotBecomeDrafts() {
        for (before, after, type) in [
            ("same", "same", AuthenticatedStagingPolicy.StageError.unchanged),
            ("old", "new\u{0000}", .invalidText),
            ("old\u{0000}", "new", .invalidText)
        ] {
            do {
                _ = try AuthenticatedStagingPolicy.stage(
                    repository: repo, branch: "main", path: "File.swift",
                    originalBlobSHA: sha, original: before, revised: after)
                XCTFail("Unsafe edit accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedStagingPolicy.StageError, type) }
        }
    }

    func testPathTraversalAndRefInjectionCannotBecomeDrafts() {
        for path in ["../secret", "a//b", "a/../b", "bad?query", "bad%0A"] {
            XCTAssertThrowsError(try AuthenticatedStagingPolicy.stage(
                repository: repo, branch: "main", path: path,
                originalBlobSHA: sha, original: "old", revised: "new"))
        }
        XCTAssertThrowsError(try AuthenticatedStagingPolicy.stage(
            repository: repo, branch: "main\nInjected", path: "file.txt",
            originalBlobSHA: sha, original: "old", revised: "new"))
    }

    func testPerFileByteBudgetsEnforced() {
        XCTAssertThrowsError(try AuthenticatedStagingPolicy.stage(
            repository: repo, branch: "main", path: "File.swift",
            originalBlobSHA: sha, original: "old",
            revised: String(repeating: "x", count: 200_001)))
        XCTAssertThrowsError(try AuthenticatedStagingPolicy.stage(
            repository: repo, branch: "main", path: "File.swift",
            originalBlobSHA: sha, original: String(repeating: "a", count: 64_001),
            revised: "new"))
    }

    func testPreviewIsBoundedBeforeSavingEncryptedDraft() throws {
        let edit = try AuthenticatedStagingPolicy.stage(
            repository: repo, branch: "feature", path: "README.md",
            originalBlobSHA: sha, original: "old", revised: "new")
        let lines = StagedDiffPreview.lines(from: edit.originalContent,
                                            to: edit.newContent, maxLines: 30)
        XCTAssertTrue(lines.contains { $0.kind == .addition && $0.text == "new" })
        XCTAssertTrue(lines.contains { $0.kind == .deletion && $0.text == "old" })
        XCTAssertLessThanOrEqual(lines.count, 30)
    }
}
