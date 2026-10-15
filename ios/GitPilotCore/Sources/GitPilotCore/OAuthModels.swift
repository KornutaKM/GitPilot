import Foundation

/// The native client never contains a GitHub App client secret.
struct OAuthCredentials: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let accessToken: String
    let accessExpiresAt: Date?
    let refreshToken: String?
    let refreshExpiresAt: Date?

    /// Do not include bearer or refresh tokens in logs, diagnostics or app state dumps.
    var description: String {
        "OAuthCredentials(accessToken=<redacted>, refreshToken=" +
        (refreshToken == nil ? "nil" : "<redacted>") + ")"
    }
    var debugDescription: String { description }

    var needsRefresh: Bool {
        guard let accessExpiresAt else { return false }
        return accessExpiresAt <= Date().addingTimeInterval(120)
    }

    var canRefresh: Bool {
        guard let refreshToken, !refreshToken.isEmpty else { return false }
        return refreshExpiresAt.map { $0 > Date().addingTimeInterval(30) } ?? true
    }
}

struct OAuthTokenPayload: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    let accessToken: String
    let expiresIn: TimeInterval?
    let refreshToken: String?
    let refreshTokenExpiresIn: TimeInterval?

    var description: String { "OAuthTokenPayload(accessToken=<redacted>, refreshToken=<redacted>)" }
    var debugDescription: String { description }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in"
        case refreshToken = "refresh_token", refreshTokenExpiresIn = "refresh_token_expires_in"
    }

    func credential(issuedAt: Date = Date()) -> OAuthCredentials {
        OAuthCredentials(accessToken: accessToken,
                         accessExpiresAt: expiresIn.map { issuedAt.addingTimeInterval($0) },
                         refreshToken: refreshToken,
                         refreshExpiresAt: refreshTokenExpiresIn.map { issuedAt.addingTimeInterval($0) })
    }
}

enum OAuthValidation {
    /// The callback is an owned-domain Universal Link registered with the GitHub App.
    /// Exact origin and path matching prevents acceptance of lookalike hosts/paths.
    static func code(from callback: URL, state: String, expectedCallback: URL) -> String? {
        guard validCallbackURL(expectedCallback),
              callback.scheme == "https", callback.host == expectedCallback.host,
              callback.path == expectedCallback.path, callback.port == nil,
              callback.user == nil, callback.password == nil, callback.fragment == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, items.first(where: { $0.name == "error" }) == nil else { return nil }
        return code
    }

    static func validCallbackURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return url.scheme == "https" && host.contains(".") &&
            host != "example.com" && !host.hasSuffix(".example") &&
            !host.hasSuffix(".invalid") && host != "localhost" &&
            url.path == "/oauth/callback" && url.port == nil &&
            url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

enum OAuthConfiguration {
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthClientID") as? String,
              value.hasPrefix("Iv") || value.hasPrefix("Ov") else { return nil }
        return value
    }

    static var backendURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthBackendURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != "example.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static var callbackURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthCallbackURL") as? String,
              let url = URL(string: raw), OAuthValidation.validCallbackURL(url) else { return nil }
        return url
    }

    static var isConfigured: Bool { clientID != nil && backendURL != nil && callbackURL != nil }
}
