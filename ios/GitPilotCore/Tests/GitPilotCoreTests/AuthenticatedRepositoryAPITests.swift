import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class AuthenticatedRepositoryAPITests: XCTestCase {
    private let item = """
    {"id":42,"name":"private-repo","full_name":"Octocat/private-repo",
     "description":"do not print this","default_branch":"main",
     "language":"Swift","stargazers_count":0,
     "html_url":"https://github.com/Octocat/private-repo","private":true}
    """

    private func client(
        status: Int = 200, payload: String? = nil, redirectedTo: URL? = nil,
        headers: [String: String] = [:],
        check: @escaping (URLRequest) -> Void = { _ in }
    ) -> AuthenticatedRepositoryAPI {
        AuthenticatedRepositoryAPI { request in
            check(request)
            return (Data((payload ?? "[\(self.item)]").utf8),
                    HTTPURLResponse(url: redirectedTo ?? request.url!, statusCode: status,
                                    httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
    }

    func testPrivateRepositoryIsDecodedOnlyThroughAuthenticatedReadOnlyGET() async throws {
        let api = client { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/user/repos")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertTrue(request.url!.absoluteString.contains("per_page=20"))
            XCTAssertTrue(request.url!.absoluteString.contains("page=1"))
        }
        let result = try await api.repositories(token: "fixture-secret")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].privateRepository)
        XCTAssertEqual(result.items[0].fullName, "Octocat/private-repo")
        XCTAssertFalse(result.hasMore)
    }

    func testBadTokenCannotReachNetworkOrInjectHeaders() async {
        let api = client { _ in XCTFail("Network access for invalid credential") }
        for invalid in ["", "token space", "token\nHeader: evil",
                        String(repeating: "x", count: 4097)] {
            do { _ = try await api.repositories(token: invalid); XCTFail("Accepted malformed token") }
            catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .invalidCredentials) }
        }
    }

    func testOnlyThreePagesMayBeLoaded() async {
        let api = client { _ in XCTFail("Page limit bypassed") }
        for invalid in [0, -1, 4, Int.max] {
            do { _ = try await api.repositories(token: "valid-test", page: invalid); XCTFail("Accepted page") }
            catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .invalidPage) }
        }
    }

    func testRedirectionCannotLeakBearerEvenIfRedirectReturnsHTTP200() async {
        let api = client(redirectedTo: URL(string: "https://evil.test/user/repos")!)
        do { _ = try await api.repositories(token: "valid-test"); XCTFail("Accepted redirected response") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .untrustedResponse) }
    }

    func testRevokedAndForbiddenHaveDistinctOutcomes() async {
        let revoked = client(status: 401)
        do { _ = try await revoked.repositories(token: "valid-test"); XCTFail("Expected revoked") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .revoked) }
        let forbidden = client(status: 403)
        do { _ = try await forbidden.repositories(token: "valid-test"); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .forbidden) }
    }

    func testResponseBombsAndMalformedMetadataAreRejected() async {
        let huge = client(payload: String(repeating: "x", count: 1_500_001))
        do { _ = try await huge.repositories(token: "valid-test"); XCTFail("Oversized response accepted") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .oversizedResponse) }

        let malformed = client(payload: "[{\"id\": 42}]")
        do { _ = try await malformed.repositories(token: "valid-test"); XCTFail("Malformed repository accepted") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .invalidPayload) }

        let invalidOwner = client(payload: "[\(item.replacingOccurrences(of: "Octocat/", with: "evil user/"))]")
        do { _ = try await invalidOwner.repositories(token: "valid-test"); XCTFail("Invalid owner accepted") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .invalidPayload) }
    }

    func testNextPageFlagIsBoundedEvenForFullLastPage() async throws {
        let list = "[" + Array(repeating: item, count: 20).joined(separator: ",") + "]"
        let api = client(payload: list)
        let first = try await api.repositories(token: "valid-test")
        let last = try await api.repositories(token: "valid-test", page: 3)
        XCTAssertTrue(first.hasMore)
        XCTAssertFalse(last.hasMore)
        XCTAssertEqual(last.items.count, 20)
    }

    func testContentLengthLimitIsHonoredEvenIfMockBodyShort() async {
        let api = client(headers: ["Content-Length": "1500001"])
        do { _ = try await api.repositories(token: "valid-test"); XCTFail("Oversized declared response accepted") }
        catch { XCTAssertEqual(error as? AuthenticatedRepositoryAPI.APIError, .oversizedResponse) }
    }
}
