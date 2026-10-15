import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class OAuthGatewayTests: XCTestCase {
    private let base = URL(string: "https://auth.gitpilot.example.net")!
    private let validToken = """
    {"access_token":"test_access_secret","expires_in":28800,
     "refresh_token":"test_refresh_secret","refresh_token_expires_in":15897600}
    """

    private func gateway(
        status: Int = 200, responseURL: URL? = nil, body: String? = nil,
        check: @escaping (URLRequest) -> Void = { _ in }
    ) throws -> GitHubOAuthGateway {
        try GitHubOAuthGateway(base: base) { request in
            check(request)
            return (Data((body ?? self.validToken).utf8),
                    HTTPURLResponse(url: responseURL ?? request.url!,
                                    statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testGatewayOnlyAcceptsConfiguredHTTPSOrigin() {
        let forbidden = [
            "http://auth.gitpilot.example.net",
            "https://user:pass@auth.gitpilot.example.net",
            "https://auth.gitpilot.example.net:9443",
            "https://localhost",
            "https://example.com",
            "https://auth.gitpilot.example.net?token=secret",
            "https://auth.gitpilot.example.net#fragment"
        ]
        forbidden.forEach {
            XCTAssertFalse(GitHubOAuthGatewayPolicy.trustedBackend(URL(string: $0)!))
        }
        XCTAssertTrue(GitHubOAuthGatewayPolicy.trustedBackend(base))
        XCTAssertEqual(GitHubOAuthGatewayPolicy.endpoint(base: base, operation: "exchange")?.path,
                       "/oauth/exchange")
        XCTAssertNil(GitHubOAuthGatewayPolicy.endpoint(base: base, operation: "delete-token"))
    }

    func testCodeExchangeUsesOnlyConfiguredHTTPSPostAndNoAuthorizationHeader() async throws {
        let client = try gateway { request in
            XCTAssertEqual(request.url?.host, "auth.gitpilot.example.net")
            XCTAssertEqual(request.url?.path, "/oauth/exchange")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("only-test-code"))
            XCTAssertTrue(body.contains("only-test-verifier"))
            XCTAssertFalse(body.contains("client_secret"))
        }
        let session = try await client.exchange(code: "only-test-code", verifier: "only-test-verifier")
        XCTAssertEqual(session.accessToken, "test_access_secret")
        XCTAssertEqual(session.refreshToken, "test_refresh_secret")
        XCTAssertFalse(String(reflecting: session).contains("test_refresh_secret"))
    }

    func testRefreshUsesExistingRefreshTokenWithoutClientSecret() async throws {
        let prior = OAuthCredentials(accessToken: "old-access",
           accessExpiresAt: Date().addingTimeInterval(-1),
           refreshToken: "test-previous-refresh",
           refreshExpiresAt: Date().addingTimeInterval(3600))
        let client = try gateway { request in
            XCTAssertEqual(request.url?.path, "/oauth/refresh")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("test-previous-refresh"))
            XCTAssertFalse(body.contains("old-access"))
            XCTAssertFalse(body.contains("client_secret"))
        }
        let session = try await client.refresh(prior)
        XCTAssertEqual(session.refreshToken, "test_refresh_secret")
    }

    func testExpiredOrAbsentRefreshTokenDoesNotMakeNetworkRequest() async throws {
        let client = try gateway { _ in XCTFail("Unexpected network request") }
        let dead = OAuthCredentials(accessToken: "old", accessExpiresAt: Date().addingTimeInterval(-1),
                                    refreshToken: nil, refreshExpiresAt: nil)
        do {
            _ = try await client.refresh(dead)
            XCTFail("Refresh should be rejected")
        } catch { XCTAssertEqual(error as? GitHubOAuthGatewayError, .accessRevoked) }
    }

    func testHTTP401RevocationIsSeparateFromTemporaryFailures() async throws {
        let rejected = try gateway(status: 401)
        do { _ = try await rejected.exchange(code: "a", verifier: "b"); XCTFail("Expected revocation") }
        catch { XCTAssertEqual(error as? GitHubOAuthGatewayError, .accessRevoked) }
        let unavailable = try gateway(status: 429)
        do { _ = try await unavailable.exchange(code: "a", verifier: "b"); XCTFail("Expected temporary error") }
        catch { XCTAssertEqual(error as? GitHubOAuthGatewayError, .unavailable) }
    }

    func testGatewayRefusesRedirectToAttackerHost() async throws {
        let client = try gateway(
           responseURL: URL(string: "https://evil.test/oauth/exchange")!)
        do { _ = try await client.exchange(code: "a", verifier: "b"); XCTFail("Expected redirect block") }
        catch { XCTAssertEqual(error as? GitHubOAuthGatewayError, .invalidResponse) }
    }

    func testMalformedOrIncompleteTokenRotationCannotBecomeCredentials() async throws {
        let bad = [
            #"{"access_token":"secret","expires_in":3600}"#,
            #"{"access_token":"secret","refresh_token":"refresh","expires_in":3600}"#,
            #"{"access_token":"","expires_in":3600,"refresh_token":"r","refresh_token_expires_in":3600}"#,
            #"{"access_token":"a b","expires_in":3600,"refresh_token":"r","refresh_token_expires_in":3600}"#,
            #"{"access_token":"a","expires_in":0,"refresh_token":"r","refresh_token_expires_in":3600}"#,
            #"{"access_token":"a","expires_in":3600,"refresh_token":"r","refresh_token_expires_in":-1}"#
        ]
        for body in bad {
            let client = try gateway(body: body)
            do { _ = try await client.exchange(code: "test", verifier: "test"); XCTFail("Accepted incomplete rotation") }
            catch { XCTAssertEqual(error as? GitHubOAuthGatewayError, .invalidResponse) }
        }
    }

    func testOAuthTokenFieldsNeverAppearInDefaultDebugDump() throws {
        let data = Data(validToken.utf8)
        let payload = try JSONDecoder().decode(OAuthTokenPayload.self, from: data)
        XCTAssertFalse(String(reflecting: payload).contains("test_access_secret"))
        XCTAssertFalse(String(reflecting: payload).contains("test_refresh_secret"))
        XCTAssertEqual(try payload.validatedCredentials().refreshToken, "test_refresh_secret")
    }
}
