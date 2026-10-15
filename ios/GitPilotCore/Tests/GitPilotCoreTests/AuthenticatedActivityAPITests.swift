import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class AuthenticatedActivityAPITests: XCTestCase {
    private var repo: PublicRepository {
        try! JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":42,"name":"private-repo","full_name":"Octocat/private-repo",
         "description":null,"default_branch":"main","language":"Swift",
         "stargazers_count":0,"html_url":null,"private":true}
        """.utf8))
    }

    private let pr = """
    {"id":100,"number":9,"title":"Test PR","draft":false,
     "user":{"login":"octocat"},"head":{"ref":"feature"},"base":{"ref":"main"},
     "html_url":"https://github.com/Octocat/private-repo/pull/9",
     "updated_at":"2026-10-14T12:00:00Z"}
    """
    private let run = """
    {"id":1234,"name":"CI","display_title":"Build","status":"completed",
     "conclusion":"failure","head_branch":"feature",
     "html_url":"https://github.com/Octocat/private-repo/actions/runs/1234",
     "updated_at":"2026-10-14T12:00:00Z"}
    """

    private func api(body: String, status: Int = 200, target: URL? = nil,
                     headers: [String: String] = [:],
                     onRequest: @escaping (URLRequest) -> Void = { _ in }) -> AuthenticatedActivityAPI {
        AuthenticatedActivityAPI { request in
            onRequest(request)
            return (Data(body.utf8),
                    HTTPURLResponse(url: target ?? request.url!, statusCode: status,
                                    httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
    }

    func testOnlyAuthenticatedNamedGETForOpenPullRequests() async throws {
        let request = api(body: "[\(pr)]") { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.host, "api.github.com")
            XCTAssertEqual(req.url?.path, "/repos/Octocat/private-repo/pulls")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertTrue(req.url!.absoluteString.contains("per_page=20"))
            XCTAssertTrue(req.url!.absoluteString.contains("state=open"))
        }
        let result = try await request.pullRequests(repository: repo, token: "test-token")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "Test PR")
        XCTAssertFalse(result.hasMore)
    }

    func testPRPagingStopsAfterThirdPageWithoutNetworkCall() async throws {
        let many = "[" + Array(repeating: pr, count: 20).joined(separator: ",") + "]"
        let request = api(body: many)
        let first = try await request.pullRequests(repository: repo, token: "test-token", page: 1)
        let last = try await request.pullRequests(repository: repo, token: "test-token", page: 3)
        XCTAssertTrue(first.hasMore)
        XCTAssertFalse(last.hasMore)
        do {
            _ = try await request.pullRequests(repository: repo, token: "test-token", page: 4)
            XCTFail("Fourth page accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidInput) }
    }

    func testWorkflowResultsAndJobsAreTypedAndReadOnly() async throws {
        let runs = api(body: "{\"workflow_runs\":[\(run)]}") { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.path, "/repos/Octocat/private-repo/actions/runs")
            XCTAssertNil(req.httpBody)
        }
        let list = try await runs.workflowRuns(repository: repo, token: "test-token")
        XCTAssertEqual(list.items.first?.conclusion, "failure")
        XCTAssertFalse(list.hasMore)
        let jobs = api(body: """
        {"jobs":[{"id":91,"name":"compile","status":"completed",
        "conclusion":"success","html_url":null,"started_at":null,"completed_at":null}]}
        """) { req in
            XCTAssertEqual(req.url?.path, "/repos/Octocat/private-repo/actions/runs/1234/jobs")
            XCTAssertTrue(req.url!.absoluteString.contains("per_page=50"))
        }
        let items = try await jobs.workflowJobs(repository: repo, runID: 1234, token: "test-token")
        XCTAssertEqual(items.first?.name, "compile")
    }

    func testPRFilePatchesAreBoundedAndNotFollowedToBlobURL() async throws {
        let request = api(body: """
        [{"filename":"Sources/Secret.swift","status":"modified",
          "additions":5,"deletions":2,
          "patch":"@@ -1 +1 @@\\n-old\\n+new",
          "blob_url":"https://github.com/Octocat/private-repo/blob/main/Secret.swift"}]
        """) { req in
            XCTAssertEqual(req.url?.path, "/repos/Octocat/private-repo/pulls/9/files")
        }
        let files = try await request.pullFiles(repository: repo, number: 9, token: "test-token")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].additions, 5)
        XCTAssertTrue(files[0].patch!.contains("+new"))
    }

    func testIssueCommentsAndInlineReviewCommentsAreSeparateResources() async throws {
        var visited: [String] = []
        let request = AuthenticatedActivityAPI { req in
            visited.append(req.url!.path)
            let data = Data("""
            [{"id":21,"body":"Looks good","user":{"login":"octocat"},
              "created_at":"2026-10-15T10:00:00Z",
              "path":null,"line":null,"html_url":null}]
            """.utf8)
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: nil)!)
        }
        let discussion = try await request.discussion(repository: repo, number: 9, token: "test-token")
        XCTAssertEqual(discussion.issueComments.count, 1)
        XCTAssertEqual(discussion.reviewComments.count, 1)
        XCTAssertEqual(visited, ["/repos/Octocat/private-repo/issues/9/comments",
                                 "/repos/Octocat/private-repo/pulls/9/comments"])
    }

    func testHeaderInjectionAndInvalidIdentifiersAreBlockedBeforeNetwork() async {
        let request = api(body: "[]") { _ in XCTFail("Unsafe request reached transport") }
        for token in ["", "token space", "x\r\nAuthorization: other",
                      String(repeating: "x", count: 4097)] {
            do {
                _ = try await request.pullRequests(repository: repo, token: token)
                XCTFail("Malformed bearer accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidInput) }
        }
        for invalid in [0, -1, Int.max] {
            do {
                _ = try await request.pullFiles(repository: repo, number: invalid, token: "test-token")
                XCTFail("Malformed PR number accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidInput) }
        }
        do {
            _ = try await request.workflowJobs(repository: repo, runID: -1, token: "test-token")
            XCTFail("Malformed run ID accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidInput) }
    }

    func testRejectsCrossHostRedirectEvenWhenHTTP200() async {
        let request = api(body: "[\(pr)]", target: URL(string: "https://evil.test/pulls")!)
        do {
            _ = try await request.pullRequests(repository: repo, token: "test-token")
            XCTFail("Redirect accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .untrustedResponse) }
    }

    func testRevokedForbiddenAndDeletedAreNotSilentlyEmpty() async {
        let expected: [(Int, AuthenticatedActivityAPI.ActivityError)] = [
            (401, .revoked), (403, .forbidden), (404, .missing), (500, .unavailable)
        ]
        for (code, kind) in expected {
            let request = api(body: "[]", status: code)
            do {
                _ = try await request.pullRequests(repository: repo, token: "test-token")
                XCTFail("HTTP \(code) incorrectly accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, kind) }
        }
    }

    func testOversizedBodyAndDeclaredLengthFailClosed() async {
        for request in [
            api(body: String(repeating: "x", count: 1_200_001)),
            api(body: "[]", headers: ["Content-Length": "1200001"])
        ] {
            do {
                _ = try await request.pullRequests(repository: repo, token: "test-token")
                XCTFail("Oversized activity accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .oversizedResponse) }
        }
    }

    func testFilePatchOverBudgetIsRejected() async {
        let request = api(body: """
        [{"filename":"a.swift","status":"modified","additions":1,
          "deletions":0,"patch":"\(String(repeating: "x", count: 80_001))"}]
        """)
        do {
            _ = try await request.pullFiles(repository: repo, number: 1, token: "test-token")
            XCTFail("Huge patch accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidPayload) }
    }

    func testInvalidCommentsAndExcessiveJobsAreRejected() async {
        let longComment = String(repeating: "x", count: 32_001)
        let apiForComments = api(body: """
        [{"id":1,"body":"\(longComment)","user":null,
          "created_at":"2026-10-15T10:00:00Z","path":null,"line":null,"html_url":null}]
        """)
        do {
            _ = try await apiForComments.discussion(repository: repo, number: 5, token: "test-token")
            XCTFail("Excessive comment accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidPayload) }
        let item = """
        {"id":1,"name":"compile","status":"completed",
        "conclusion":"success","html_url":null,"started_at":null,"completed_at":null}
        """
        let jobs = api(body: "{\"jobs\":[" + Array(repeating: item, count: 51).joined(separator: ",") + "]}")
        do {
            _ = try await jobs.workflowJobs(repository: repo, runID: 1, token: "test-token")
            XCTFail("Excessive jobs accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidPayload) }
    }

    func testMalformedRepositoryOwnerCannotBeUsedToBuildURL() async {
        let corrupted = try! JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":42,"name":"x","full_name":"evil owner/x","description":null,
         "default_branch":"main","language":null,"stargazers_count":0,
         "html_url":null,"private":true}
        """.utf8))
        let request = api(body: "[]") { _ in XCTFail("Invalid repo reached network") }
        do {
            _ = try await request.pullRequests(repository: corrupted, token: "test-token")
            XCTFail("Untrusted owner accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedActivityAPI.ActivityError, .invalidInput) }
    }
}
