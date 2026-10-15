import Foundation

/// The native client never contains a GitHub App client secret.
public struct OAuthCredentials: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let accessExpiresAt: Date?
    public let refreshToken: String?
    public let refreshExpiresAt: Date?


    public init(accessToken: String, accessExpiresAt: Date?,
                refreshToken: String?, refreshExpiresAt: Date?) {
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.refreshExpiresAt = refreshExpiresAt
    }

    /// Do not include bearer or refresh tokens in logs, diagnostics or app state dumps.
    public var description: String {
        "OAuthCredentials(accessToken=<redacted>, refreshToken=" +
        (refreshToken == nil ? "nil" : "<redacted>") + ")"
    }
    public var debugDescription: String { description }

    public var needsRefresh: Bool {
        guard let accessExpiresAt else { return false }
        return accessExpiresAt <= Date().addingTimeInterval(120)
    }

    public var canRefresh: Bool {
        guard let refreshToken, !refreshToken.isEmpty else { return false }
        return refreshExpiresAt.map { $0 > Date().addingTimeInterval(30) } ?? true
    }
}

public struct OAuthTokenPayload: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let expiresIn: TimeInterval?
    public let refreshToken: String?
    public let refreshTokenExpiresIn: TimeInterval?

    public var description: String { "OAuthTokenPayload(accessToken=<redacted>, refreshToken=<redacted>)" }
    public var debugDescription: String { description }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in"
        case refreshToken = "refresh_token", refreshTokenExpiresIn = "refresh_token_expires_in"
    }

    public enum ValidationError: LocalizedError {
        case malformedCredentials
        public var errorDescription: String? { "OAuth gateway returned invalid credentials." }
    }

    /// Enforces a complete refresh-token rotation and bounded token lifetimes.
    /// Reject before writing any data into Keychain.
    public func validatedCredentials(issuedAt: Date = Date()) throws -> OAuthCredentials {
        func valid(_ value: String?) -> Bool {
            guard let value, !value.isEmpty && value.utf8.count <= 4096 else { return false }
            return !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) ||
                CharacterSet.controlCharacters.contains($0) }
        }
        guard valid(accessToken), refreshToken == nil || valid(refreshToken) else {
            throw ValidationError.malformedCredentials
        }
        for lifetime in [expiresIn, refreshTokenExpiresIn] {
            if let lifetime, (!lifetime.isFinite || lifetime < 1 || lifetime > 315_360_000) {
                throw ValidationError.malformedCredentials
            }
        }
        guard (refreshToken == nil) == (refreshTokenExpiresIn == nil),
              refreshToken == nil || expiresIn != nil else {
            throw ValidationError.malformedCredentials
        }
        return credential(issuedAt: issuedAt)
    }

    public func credential(issuedAt: Date = Date()) -> OAuthCredentials {
        OAuthCredentials(accessToken: accessToken,
                         accessExpiresAt: expiresIn.map { issuedAt.addingTimeInterval($0) },
                         refreshToken: refreshToken,
                         refreshExpiresAt: refreshTokenExpiresIn.map { issuedAt.addingTimeInterval($0) })
    }
}

public enum OAuthValidation {
    /// The callback is an owned-domain Universal Link registered with the GitHub App.
    /// Exact origin and path matching prevents acceptance of lookalike hosts/paths.
    public static func code(from callback: URL, state: String, expectedCallback: URL) -> String? {
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

    public static func validCallbackURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return url.scheme == "https" && host.contains(".") &&
            host != "example.com" && !host.hasSuffix(".example") &&
            !host.hasSuffix(".invalid") && host != "localhost" &&
            url.path == "/oauth/callback" && url.port == nil &&
            url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

public enum OAuthConfiguration {
    public static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthClientID") as? String,
              value.hasPrefix("Iv") || value.hasPrefix("Ov") else { return nil }
        return value
    }

    public static var backendURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthBackendURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != "example.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    public static var callbackURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GitPilotOAuthCallbackURL") as? String,
              let url = URL(string: raw), OAuthValidation.validCallbackURL(url) else { return nil }
        return url
    }

    public static var isConfigured: Bool { clientID != nil && backendURL != nil && callbackURL != nil }
}
