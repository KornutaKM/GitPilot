import XCTest
import Foundation
import GitPilotCore
@testable import GitPilotCoreSmoke

/// Native simulator/device tests, not Linux stubs. These fixtures contain only
/// test-only strings, never real GitHub credentials or uncommitted user source.
final class NativeSecureStorageTests: XCTestCase {
    override func setUpWithError() throws {
        try OAuthTokenStore.remove()
        try StagedDraftVault.erase()
    }

    override func tearDownWithError() throws {
        try OAuthTokenStore.remove()
        try StagedDraftVault.erase()
    }

    func testKeychainTokenRoundTripIsDeviceOnlyAndNotUserDefaults() throws {
        let credential = OAuthCredentials(
            accessToken: "test-only-oauth-access", accessExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "test-only-oauth-refresh", refreshExpiresAt: Date().addingTimeInterval(7200)
        )
        try OAuthTokenStore.save(credential)
        XCTAssertEqual(try OAuthTokenStore.read()?.accessToken, credential.accessToken)
        XCTAssertEqual(try OAuthTokenStore.read()?.refreshToken, credential.refreshToken)
        XCTAssertFalse(UserDefaults.standard.dictionaryRepresentation().description.contains("test-only-oauth-access"))
        XCTAssertFalse(UserDefaults.standard.dictionaryRepresentation().description.contains("test-only-oauth-refresh"))
    }

    func testKeychainRotationOverwritesOldCredentialWithoutLeavingItReadable() throws {
        try OAuthTokenStore.save(OAuthCredentials(
            accessToken: "test-access-old", accessExpiresAt: nil,
            refreshToken: "test-refresh-old", refreshExpiresAt: nil
        ))
        try OAuthTokenStore.save(OAuthCredentials(
            accessToken: "test-access-new", accessExpiresAt: nil,
            refreshToken: "test-refresh-new", refreshExpiresAt: nil
        ))
        let restored = try OAuthTokenStore.read()
        XCTAssertEqual(restored?.accessToken, "test-access-new")
        XCTAssertEqual(restored?.refreshToken, "test-refresh-new")
    }

    func testSignOutDeletesPersistedKeychainRecord() throws {
        try OAuthTokenStore.save(OAuthCredentials(
            accessToken: "test-only-access", accessExpiresAt: nil,
            refreshToken: nil, refreshExpiresAt: nil
        ))
        try OAuthTokenStore.remove()
        XCTAssertNil(try OAuthTokenStore.read())
        XCTAssertNoThrow(try OAuthTokenStore.remove())
    }

    private func stagedEdit() -> StagedFileEdit {
        StagedFileEdit(repositoryID: 33, repositoryFullName: "test-user/example",
            path: "README.md", branch: "safe-branch",
            originalBlobSHA: String(repeating: "a", count: 40),
            originalContent: "test-old-content", newContent: "test-new-content")
    }

    func testEncryptedDraftRestoresOnlyForTheOriginalAccount() throws {
        try StagedDraftVault.save(for: "Alice", edits: [stagedEdit()])
        let recovered = try StagedDraftVault.load(for: "ALICE")
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.newContent, "test-new-content")
        XCTAssertThrowsError(try StagedDraftVault.load(for: "Bob")) { error in
            XCTAssertEqual(error as? StagedDraftEnvelope.ValidationError, .wrongAccount)
        }
    }

    func testDraftFileNeverContainsPlaintextSource() throws {
        try StagedDraftVault.save(for: "Alice", edits: [stagedEdit()])
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitPilot", isDirectory: true)
        let encrypted = try Data(contentsOf: folder.appendingPathComponent("staged-drafts-v1.enc"))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("test-new-content"))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("test-old-content"))
    }

    func testErasingDraftKeyPreventsRecovery() throws {
        try StagedDraftVault.save(for: "Alice", edits: [stagedEdit()])
        try StagedDraftVault.erase()
        XCTAssertTrue(try StagedDraftVault.load(for: "Alice").isEmpty)
    }
}
