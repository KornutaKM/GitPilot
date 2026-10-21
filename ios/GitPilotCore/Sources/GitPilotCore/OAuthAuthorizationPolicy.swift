import Foundation

/// A pure, testable GitHub App OAuth URL builder. The only browser origin
/// accepted is GitHub's fixed HTTPS authorization endpoint.
public enum OAuthAuthorizationPolicy {
    public enum AuthorizationError: Error, LocalizedError, Equatable {
        case invalidParameters
        public var errorDescription: String? {
            "The GitHub App authorization configuration is invalid."
        }
    }

    public static func authorizeURL(
        clientID: String, callback: URL, state: String, codeChallenge: String
    ) throws -> URL {
        guard !clientID.isEmpty, clientID.utf8.count <= 160,
              clientID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }),
              OAuthValidation.validCallbackURL(callback),
              state.count >= 32 && state.count <= 128,
              codeChallenge.count >= 43 && codeChallenge.count <= 128,
              [state, codeChallenge].allSatisfy({ value in
                  value.utf8.allSatisfy {
                      (48...57).contains(Int($0)) || (65...90).contains(Int($0)) ||
                      (97...122).contains(Int($0)) || $0 == 45 || $0 == 95
                  }
              }) else { throw AuthorizationError.invalidParameters }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "github.com"
        url.path = "/login/oauth/authorize"
        url.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: callback.absoluteString),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let result = url.url, result.scheme == "https",
              result.host == "github.com", result.path == "/login/oauth/authorize"
        else { throw AuthorizationError.invalidParameters }
        return result
    }
}
