import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class PublicGitHubAPITests: XCTestCase {
    private let repoJSON = """
    {"id":42,"name":"GitPilot","full_name":"Octocat/GitPilot","description":"Safe preview",
     "default_branch":"main","language":"Swift","stargazers_count":3,
     "html_url":"https://github.com/Octocat/GitPilot","private":false}
    """
    private let pullJSON = """
    {"id":501,"number":7,"title":"Improve CI","draft":true,
     "user":{"login":"octocat"},"head":{"ref":"feature"},
     "base":{"ref":"main"},"html_url":"https://github.com/Octocat/GitPilot/pull/7",
     "updated_at":"2026-10-15T10:00:00Z"}
    """
    private let runJSON = """
    {"id":123,"name":"Android CI","display_title":"Build","status":"completed",
     "conclusion":"failure","head_branch":"feature",
     "html_url":"https://github.com/Octocat/GitPilot/actions/runs/123",
     "updated_at":"2026-10-15T10:00:00Z"}
    """

    private func response(_ request: URLRequest, status: Int = 200,
                          headers: [String: String] = [:],
                          url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url ?? request.url!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func api(body: String, status: Int = 200) -> PublicGitHubAPI {
        PublicGitHubAPI { request in
            (Data(body.utf8), self.response(request, status: status))
        }
    }

    func testUsernameValidationRejectsInjectionAndWhitespace() {
        for valid in ["Octocat", "x", "git-pilot", "A1-Z9"] {
            XCTAssertTrue(PublicGitHubAPI.validUsername(valid))
        }
        for invalid in ["", "-abc", "abc-", "a b", "a/b", "a?token=x",
                        "équipe", String(repeating: "a", count: 40)] {
            XCTAssertFalse(PublicGitHubAPI.validUsername(invalid))
        }
    }

    func testRepositoryNamesRejectTraversalAndControlCharacters() {
        XCTAssertTrue(PublicGitHubAPI.validRepositoryName("repo.name-1"))
        for invalid in ["", ".", "..", "a/b", "repo?x=1", "bad name", "bad\nname"] {
            XCTAssertFalse(PublicGitHubAPI.validRepositoryName(invalid))
        }
    }

    func testPublicRepositoryListIsDecodedAndReadOnly() async throws {
        let client = PublicGitHubAPI { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/users/Octocat/repos")
            XCTAssertTrue(request.url!.absoluteString.contains("per_page=12"))
            return (Data("[\(self.repoJSON)]".utf8), self.response(request))
        }
        let page = try await client.repositories(username: "Octocat")
        XCTAssertEqual(page.repositories.count, 1)
        XCTAssertEqual(page.repositories.first?.fullName, "Octocat/GitPilot")
        XCTAssertFalse(page.hasMore)
    }

    func testMalformedAndOversizedAPIResponsesFailClosed() async {
        do {
            _ = try await api(body: "{ malformed").repositories(username: "Octocat")
            XCTFail("Malformed JSON must be rejected")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .invalidResponse) }
        do {
            _ = try await api(body: String(repeating: "a", count: 1_500_001))
                .repositories(username: "Octocat")
            XCTFail("Oversized body must be rejected")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .oversizedResponse) }
    }

    func testRateLimitAndNotFoundRemainDistinct() async {
        do {
            _ = try await api(body: "{}", status: 403).repositories(username: "Octocat")
            XCTFail("Expected rate limit")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .rateLimited) }
        do {
            _ = try await api(body: "{}", status: 404).repositories(username: "Octocat")
            XCTFail("Expected not found")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .notFound) }
    }

    func testRefusesCrossOriginAPIResponseEvenWhenStatusIsSuccessful() async {
        let client = PublicGitHubAPI { request in
            (Data("[\(self.repoJSON)]".utf8),
             self.response(request, url: URL(string: "https://api.github.com.evil.test/users/Octocat/repos")!))
        }
        do {
            _ = try await client.repositories(username: "Octocat")
            XCTFail("Redirect to a spoofed origin must be rejected")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .untrustedResponse) }
    }

    func testPublicWorkspaceLoadsRealEntitiesWithExplicitSampleBoundary() async throws {
        let client = PublicGitHubAPI { request in
            let body: String
            switch request.url!.path {
            case "/users/Octocat/repos": body = "[\(self.repoJSON)]"
            case "/repos/Octocat/GitPilot/pulls": body = "[\(self.pullJSON)]"
            case "/repos/Octocat/GitPilot/actions/runs": body = "{\"workflow_runs\":[\(self.runJSON)]}"
            default: throw PublicGitHubError.notFound
            }
            return (Data(body.utf8), self.response(request))
        }
        let workspace = try await client.workspace(username: "Octocat")
        XCTAssertEqual(workspace.repositories.count, 1)
        XCTAssertEqual(workspace.pullRequests.first?.title, "Improve CI")
        XCTAssertEqual(workspace.workflows.first?.conclusion, "failure")
        XCTAssertEqual(workspace.monitoredRepositories, 1)
        XCTAssertFalse(workspace.isPartial)
    }

    func testPartialMonitoringReportsWarningsInsteadOfClaimingGreenCI() async throws {
        let client = PublicGitHubAPI { request in
            switch request.url!.path {
            case "/users/Octocat/repos":
                return (Data("[\(self.repoJSON)]".utf8), self.response(request))
            case "/repos/Octocat/GitPilot/pulls":
                return (Data("[]".utf8), self.response(request))
            default:
                throw PublicGitHubError.rateLimited
            }
        }
        let workspace = try await client.workspace(username: "Octocat")
        XCTAssertTrue(workspace.isPartial)
        XCTAssertEqual(workspace.warnings.count, 1)
        XCTAssertTrue(workspace.workflows.isEmpty)
    }

    func testHTMLLinksNeverTrustLookalikeHosts() {
        XCTAssertNotNil(PublicGitHubAPI.safeGitHubWebURL(URL(string: "https://github.com/Octocat/GitPilot")))
        for raw in ["http://github.com/user", "https://github.com.evil.test/user",
                    "https://github.com:8443/user", "https://me:password@github.com/user"] {
            XCTAssertNil(PublicGitHubAPI.safeGitHubWebURL(URL(string: raw)))
        }
    }

    func testRepositoryPagingRejectsUnlimitedScans() async {
        do {
            _ = try await api(body: "[]").repositories(username: "Octocat", page: 4)
            XCTFail("Fourth page must be rejected")
        } catch { XCTAssertEqual(error as? PublicGitHubError, .invalidResponse) }
    }
}
