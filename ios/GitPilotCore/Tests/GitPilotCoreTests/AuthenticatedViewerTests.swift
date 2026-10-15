import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class AuthenticatedViewerTests: XCTestCase {
    private func client(status: Int = 200, responseURL: URL? = nil,
                        body: String = #"{"login":"Octocat"}"#,
                        check: @escaping (URLRequest) -> Void = { _ in }) -> GitHubAuthenticatedViewer {
        GitHubAuthenticatedViewer { request in
            check(request)
            return (Data(body.utf8),
                    HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status,
                                    httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
    }

    func testAuthenticatedViewerOnlySendsBearerToGitHubUserEndpoint() async throws {
        let api = client { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-token")
        }
        let login = try await api.verifiedLogin(token: "test-only-token")
        XCTAssertEqual(login, "Octocat")
    }

    func testViewerRejectsWhitespaceAndCRLFInBearerToken() async {
        let api = client { _ in XCTFail("Should not reach network") }
        for invalid in ["", "a b", "a\nb", "a\r\nInjected: header",
                        String(repeating: "a", count: 4097)] {
            do { _ = try await api.verifiedLogin(token: invalid); XCTFail("Unexpected success") }
            catch { XCTAssertEqual(error as? GitHubAuthenticatedViewer.ViewerError, .invalidToken) }
        }
    }

    func testViewerRejectsCrossHostRedirectAndInvalidResponse() async {
        let redirect = client(responseURL: URL(string: "https://api.github.com.evil.test/user")!)
        do { _ = try await redirect.verifiedLogin(token: "abc"); XCTFail("Redirect accepted") }
        catch { XCTAssertEqual(error as? GitHubAuthenticatedViewer.ViewerError, .untrustedResponse) }
        let invalid = client(body: #"{"login":"malicious user"}"#)
        do { _ = try await invalid.verifiedLogin(token: "abc"); XCTFail("Invalid login accepted") }
        catch { XCTAssertEqual(error as? GitHubAuthenticatedViewer.ViewerError, .untrustedResponse) }
    }

    func testViewerDifferentiatesRevokedFromTransientFailure() async {
        let revoked = client(status: 401)
        do { _ = try await revoked.verifiedLogin(token: "abc"); XCTFail("Expected revoked") }
        catch { XCTAssertEqual(error as? GitHubAuthenticatedViewer.ViewerError, .revoked) }
        let outage = client(status: 500)
        do { _ = try await outage.verifiedLogin(token: "abc"); XCTFail("Expected unavailable") }
        catch { XCTAssertEqual(error as? GitHubAuthenticatedViewer.ViewerError, .unavailable) }
    }
}
