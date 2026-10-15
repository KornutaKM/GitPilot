import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class RC3SecurityTests: XCTestCase {
    func testGitHubAPIOriginPolicyRejectsLookalikes() {
        let accepted = ["https://api.github.com/repos/octocat/Hello-World", "https://api.github.com:443/user"]
        for raw in accepted { XCTAssertTrue(GitHubURLPolicy.trustedAPI(URL(string: raw)!)) }
        let rejected = ["http://api.github.com/repos", "https://api.github.com.evil.test/user",
                        "https://api.github.com:8443/user", "https://user:pass@api.github.com/user",
                        "https://api.github.com/user#anchor"]
        for raw in rejected { XCTAssertFalse(GitHubURLPolicy.trustedAPI(URL(string: raw)!)) }
    }

    func testRedirectDropsBearerOnForeignHost() {
        var first = URLRequest(url: URL(string: "https://api.github.com/user")!)
        first.setValue("Bearer test-not-real", forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(GitHubURLPolicy.sanitizedRedirect(first)?.value(forHTTPHeaderField: "Authorization"))
        var foreign = URLRequest(url: URL(string: "https://objects.githubusercontent.com/signed")!)
        foreign.setValue("Bearer test-not-real", forHTTPHeaderField: "Authorization")
        XCTAssertNil(GitHubURLPolicy.sanitizedRedirect(foreign)?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(GitHubURLPolicy.sanitizedRedirect(URLRequest(url: URL(string: "http://github.com")!)))
    }

    func testOnlyMonotonicSameResourcePageIsAccepted() {
        let start = URL(string: "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=2")!
        let good = URL(string: "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=3")!
        XCTAssertEqual(GitHubPaginationPolicy.nextPage(good, after: start), good)
        let rejected = [
            "https://evil.test/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=3",
            "https://api.github.com:444/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=3",
            "https://api.github.com/repos/other/repo/pulls?state=open&per_page=20&page=3",
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=closed&per_page=20&page=3",
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=2",
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=0",
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=20&page=3&page=4"
        ]
        for raw in rejected { XCTAssertNil(GitHubPaginationPolicy.nextPage(URL(string: raw)!, after: start)) }
    }

    func testUnifiedDiffTracksSidesAndReviewLocations() {
        let lines = UnifiedDiff.parse("@@ -2,2 +2,2 @@\n keep\n-removed\n+added")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1].oldLine, 2)
        XCTAssertEqual(lines[1].newLine, 2)
        XCTAssertEqual(lines[2].reviewLocation?.side, "LEFT")
        XCTAssertEqual(lines[3].reviewLocation?.side, "RIGHT")
        XCTAssertEqual(lines[2].reviewLocation?.line, 3)
        XCTAssertEqual(lines[3].reviewLocation?.line, 3)
    }

    func testOAuthCallbackRejectsHostSpoofingAndStateMismatch() {
        let allowed = URL(string: "https://gitpilot.example.net/oauth/callback")!
        let good = URL(string: "https://gitpilot.example.net/oauth/callback?state=nonce&code=code123")!
        XCTAssertEqual(OAuthValidation.code(from: good, state: "nonce", expectedCallback: allowed), "code123")
        let bad = [
            "https://gitpilot.example.net.evil.test/oauth/callback?state=nonce&code=code123",
            "http://gitpilot.example.net/oauth/callback?state=nonce&code=code123",
            "https://gitpilot.example.net/oauth/callback?state=other&code=code123",
            "https://gitpilot.example.net/oauth/callback?state=nonce&state=nonce&code=code123",
            "https://gitpilot.example.net/oauth/callback?state=nonce&code=code123&code=code123",
            "https://gitpilot.example.net/oauth/callback?state=nonce&code=code123&error=access_denied"
        ]
        for raw in bad { XCTAssertNil(OAuthValidation.code(from: URL(string: raw)!, state: "nonce", expectedCallback: allowed)) }
    }

    func testOAuthCredentialsNeverPrintTokens() {
        let token = OAuthCredentials(accessToken: "super-private-access", accessExpiresAt: nil,
            refreshToken: "super-private-refresh", refreshExpiresAt: nil)
        XCTAssertFalse(String(describing: token).contains("super-private-access"))
        XCTAssertFalse(String(reflecting: token).contains("super-private-refresh"))
        let payload = OAuthTokenPayload(accessToken: "super-private-access", expiresIn: nil,
            refreshToken: "super-private-refresh", refreshTokenExpiresIn: nil)
        XCTAssertFalse(String(describing: payload).contains("super-private-access"))
        XCTAssertFalse(String(reflecting: payload).contains("super-private-refresh"))
    }

    func testOAuthCredentialsRefreshWindow() {
        let now = Date()
        let credentials = OAuthCredentials(accessToken: "test-secret", accessExpiresAt: now.addingTimeInterval(60),
            refreshToken: "test-refresh", refreshExpiresAt: now.addingTimeInterval(3600))
        XCTAssertTrue(credentials.needsRefresh)
        XCTAssertTrue(credentials.canRefresh)
    }
}
