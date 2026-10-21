import XCTest
import Foundation
@testable import GitPilotCore

final class OAuthAuthorizationPolicyTests: XCTestCase {
    private let callback = URL(string: "https://login.gitpilot.example.net/oauth/callback")!
    private let state = String(repeating: "s", count: 43)
    private let challenge = String(repeating: "c", count: 43)

    func testSecureAuthorizationURLHasOnlyPKCEAndExpectedParameters() throws {
        let result = try OAuthAuthorizationPolicy.authorizeURL(
            clientID: "Iv1.publicClient123", callback: callback, state: state,
            codeChallenge: challenge)
        XCTAssertEqual(result.scheme, "https")
        XCTAssertEqual(result.host, "github.com")
        XCTAssertEqual(result.path, "/login/oauth/authorize")
        let items = URLComponents(url: result, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(Set(items.map(\.name)),
                       Set(["client_id", "redirect_uri", "state", "code_challenge", "code_challenge_method"]))
        XCTAssertEqual(items.first(where: { $0.name == "state" })?.value, state)
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertFalse(result.absoluteString.contains("client_secret"))
        XCTAssertFalse(result.absoluteString.contains("access_token"))
    }

    func testRefusesHTTPAndLookalikeCallbackOrigins() {
        for url in [
            "http://login.gitpilot.example.net/oauth/callback",
            "https://login.gitpilot.example.net.evil.test/oauth/callback",
            "https://login.gitpilot.example.net/oauth/callback?code=stolen",
            "https://login.gitpilot.example.net:444/oauth/callback",
            "https://login.gitpilot.example.net/other"
        ] {
            XCTAssertThrowsError(try OAuthAuthorizationPolicy.authorizeURL(
                clientID: "Iv1.publicClient123", callback: URL(string: url)!,
                state: state, codeChallenge: challenge))
        }
    }

    func testInsufficientOrInjectedPKCEValuesCannotStartBrowser() {
        for invalid in ["", "short", "bad space", String(repeating: "x", count: 129),
                        String(repeating: "x", count: 42) + "\n"] {
            XCTAssertThrowsError(try OAuthAuthorizationPolicy.authorizeURL(
                clientID: "Iv1.publicClient123", callback: callback,
                state: invalid, codeChallenge: challenge))
            XCTAssertThrowsError(try OAuthAuthorizationPolicy.authorizeURL(
                clientID: "Iv1.publicClient123", callback: callback,
                state: state, codeChallenge: invalid))
        }
    }

    func testClientIDInjectionCannotReachGitHub() {
        for id in ["", "client secret", "Iv1.good&redirect_uri=https://evil.test",
                   "Iv1.bad\r\nHeader: evil", String(repeating: "x", count: 161)] {
            XCTAssertThrowsError(try OAuthAuthorizationPolicy.authorizeURL(
                clientID: id, callback: callback, state: state,
                codeChallenge: challenge))
        }
    }
}
