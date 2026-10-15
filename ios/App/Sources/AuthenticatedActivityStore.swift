import Foundation
import SwiftUI
import GitPilotCore

/// Reusable page loader for either PRs or Actions. Every response is scoped to
/// the exact authenticated account and revision; nothing is persisted on disk.
@MainActor
final class AuthenticatedActivityPager<Item: Identifiable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = false
    @Published private(set) var loaded = false
    @Published private(set) var errorMessage: String?

    private var page = 1
    private var generation = 0

    func clear() {
        generation += 1
        items = []
        page = 1
        hasMore = false
        loaded = false
        loading = false
        errorMessage = nil
    }

    func reload(
        account: OAuthAccountSession,
        fetch: @escaping (String, Int) async throws -> AuthenticatedActivityAPI.Page<Item>
    ) async {
        clear()
        await next(account: account, fetch: fetch)
    }

    func next(
        account: OAuthAccountSession,
        fetch: @escaping (String, Int) async throws -> AuthenticatedActivityAPI.Page<Item>
    ) async {
        guard !loading, page <= 3, let login = account.authenticatedAs,
              !account.busy, !loaded || hasMore else { return }
        let requestGeneration = generation
        let requestedPage = page
        loading = true
        errorMessage = nil
        do {
            let token = try await account.tokenForProtectedRead()
            let sessionRevision = account.authRevision
            let response = try await fetch(token, requestedPage)
            guard !Task.isCancelled, generation == requestGeneration,
                  sessionRevision == account.authRevision,
                  account.authenticatedAs == login, !account.busy else { return }
            let seen = Set(items.map(\.id))
            items += response.items.filter { !seen.contains($0.id) }
            page = requestedPage + 1
            hasMore = response.hasMore
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration, !Task.isCancelled,
                  account.authenticatedAs == login else { return }
            if let failure = error as? AuthenticatedActivityAPI.ActivityError,
               failure == .revoked {
                account.signOut()
                clear()
                return
            }
            errorMessage = error.localizedDescription
            loaded = true
        }
        if generation == requestGeneration { loading = false }
    }
}
