import SwiftUI
import GitPilotCore

/// Protected read-only list. Results never leave memory and cannot outlive
/// OAuth sign-out/account changes. No private file contents or mutations.
struct AuthenticatedRepositoriesScreen: View {
    @EnvironmentObject private var account: OAuthAccountSession
    @State private var items: [PublicRepository] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var nextPage = 1
    @State private var error: String?

    private var activeLogin: String? { account.authenticatedAs }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(
                    eyebrow: "GITHUB APP · PRIVATE READ-ONLY",
                    title: "Your repos.",
                    subtitle: activeLogin.map { "Verified @\($0), bounded to 60 repositories" }
                        ?? "Connect a verified GitHub App account first."
                )
                if activeLogin == nil || account.busy {
                    GPEmptyState(icon: "lock.shield.fill",
                                 title: "Protected workspace locked",
                                 detail: "Only a verified GitHub App session may read account repositories.")
                } else {
                    if loading && items.isEmpty {
                        Surface { ProgressView("Reading GitHub repositories…").tint(GP.accent) }
                    }
                    if let error {
                        Surface {
                            Label("Protected read unavailable", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(GP.amber)
                            Text(error).font(.caption).foregroundStyle(GP.secondary)
                            Button("Retry") { Task { await reload() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    ForEach(items) { repo in
                        Surface {
                            HStack {
                                GPIndicator(icon: repo.privateRepository ? "lock.fill" : "folder",
                                            tint: repo.privateRepository ? GP.amber : GP.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(repo.fullName).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(repo.privateRepository ? "Private · read-only" : "Public · read-only")
                                        .font(.caption).foregroundStyle(GP.secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            if let url = PublicGitHubAPI.safeGitHubWebURL(repo.htmlURL) {
                                Link("Open on GitHub", destination: url)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    if hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if loading { ProgressView().tint(GP.accent) }
                            else { Label("Load more repositories", systemImage: "arrow.down.circle") }
                        }
                        .disabled(loading)
                        .buttonStyle(.borderedProminent)
                    }
                    if !loading && items.isEmpty && error == nil {
                        GPEmptyState(icon: "folder",
                                     title: "No accessible repositories in first page",
                                     detail: "Access depends on your GitHub App installation and granted permissions.")
                    }
                    MetaText(text: "Only 3 × 20 repositories may be loaded. No private data is saved on disk.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Authenticated repos")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await reload() }
        .onChange(of: account.authenticatedAs) { _ in clear() }
        .onDisappear { clear() }
        .refreshable { await reload() }
    }

    @MainActor
    private func clear() {
        items = []
        hasMore = false
        loading = false
        nextPage = 1
        error = nil
    }

    @MainActor
    private func reload() async {
        clear()
        guard activeLogin != nil, !account.busy else { return }
        await fetch(page: 1)
    }

    @MainActor
    private func loadMore() async {
        guard hasMore, !loading, nextPage <= 3 else { return }
        await fetch(page: nextPage)
    }

    @MainActor
    private func fetch(page: Int) async {
        guard !loading, let expectedLogin = activeLogin, !account.busy else { return }
        loading = true
        error = nil
        do {
            // Refresh stays in the session coordinator; this view never reads Keychain.
            let token = try await account.tokenForProtectedRead()
            let requestRevision = account.authRevision
            let result = try await AuthenticatedRepositoryAPI().repositories(token: token, page: page)
            guard !Task.isCancelled, requestRevision == account.authRevision,
                  account.authenticatedAs == expectedLogin, !account.busy else { return }
            if page == 1 { items = result.items }
            else {
                let existing = Set(items.map(\.id))
                items += result.items.filter { !existing.contains($0.id) }
            }
            nextPage = page + 1
            hasMore = result.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard account.authenticatedAs == expectedLogin, !Task.isCancelled else { return }
            if let failure = error as? AuthenticatedRepositoryAPI.APIError, failure == .revoked {
                account.signOut()
                clear()
                return
            }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
