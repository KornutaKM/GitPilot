import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Extracted from the RC3 GitHub API. Only the exact GitHub API origin may
/// receive an Authorization header, and untrusted redirects must never retain it.
public enum GitHubURLPolicy {
    public static func trustedAPI(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.github.com" &&
        (url.port == nil || url.port == 443) && url.user == nil && url.password == nil &&
        url.fragment == nil
    }

    public static func sanitizedRedirect(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, url.scheme?.lowercased() == "https",
              (url.port == nil || url.port == 443),
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        var result = request
        if !trustedAPI(url) { result.setValue(nil, forHTTPHeaderField: "Authorization") }
        return result
    }
}

/// Link header pagination must never turn a benign GET into an authenticated
/// request to a different resource, origin or search/filter query.
public enum GitHubPaginationPolicy {
    public static func nextPage(_ candidate: URL, after current: URL) -> URL? {
        guard GitHubURLPolicy.trustedAPI(current), GitHubURLPolicy.trustedAPI(candidate),
              let from = URLComponents(url: current, resolvingAgainstBaseURL: false),
              let to = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              from.path == to.path else { return nil }
        let previous = from.queryItems ?? []
        let following = to.queryItems ?? []
        let fromPages = previous.filter { $0.name == "page" }
        let toPages = following.filter { $0.name == "page" }
        guard fromPages.count <= 1, toPages.count == 1,
              let nextRaw = toPages[0].value,
              let next = Int(nextRaw), next > 0, next <= 1000 else { return nil }
        if let previousRaw = fromPages.first?.value {
            guard let old = Int(previousRaw), next > old else { return nil }
        } else if next <= 1 { return nil }
        let unchangedFrom = previous.filter { $0.name != "page" }.map { ($0.name, $0.value) }
        let unchangedTo = following.filter { $0.name != "page" }.map { ($0.name, $0.value) }
        guard unchangedFrom.count == unchangedTo.count,
              zip(unchangedFrom, unchangedTo).allSatisfy({ $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 }) else { return nil }
        return candidate
    }
}
