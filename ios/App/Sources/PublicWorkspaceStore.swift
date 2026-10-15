import Foundation
import SwiftUI
import GitPilotCore

/// Intentionally public-only while RC3 Keychain/OAuth are being migrated.
/// All results are scoped to a load generation; no old profile may overwrite a new one.
@MainActor
final class PublicWorkspaceStore: ObservableObject {
    @Published private(set) var username = "KornutaKM"
    @Published private(set) var repositories: [PublicRepository] = []
    @Published private(set) var pullRequests: [PublicPullRequest] = []
    @Published private(set) var workflowRuns: [PublicWorkflowRun] = []
    @Published private(set) var warnings: [String] = []
    @Published private(set) var monitoredRepositories = 0
    @Published private(set) var hasMore = false
    @Published private(set) var page = 1
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let api = PublicGitHubAPI()
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?

    func selectProfile(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PublicGitHubAPI.validUsername(value) else {
            errorMessage = "Enter a valid GitHub username."
            return
        }
        username = value
        refresh()
    }

    func refresh() {
        generation += 1
        let request = generation
        let target = username
        loadTask?.cancel()
        pageTask?.cancel()
        isLoading = true
        loadingMore = false
        errorMessage = nil
        warnings = []
        // Never display previous user's workspace while switching profiles.
        repositories = []
        pullRequests = []
        workflowRuns = []
        hasMore = false
        hasLoaded = false
        monitoredRepositories = 0
        page = 1
        loadTask = Task {
            do {
                let snapshot = try await api.workspace(username: target)
                guard !Task.isCancelled && request == generation else { return }
                repositories = snapshot.repositories
                pullRequests = snapshot.pullRequests
                workflowRuns = snapshot.workflows
                warnings = snapshot.warnings
                monitoredRepositories = snapshot.monitoredRepositories
                hasMore = snapshot.hasMoreRepositories
                hasLoaded = true
            } catch is CancellationError {
                return
            } catch {
                guard request == generation else { return }
                errorMessage = error.localizedDescription
                hasLoaded = true
            }
            if request == generation { isLoading = false }
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, !loadingMore, page < 3 else { return }
        let request = generation
        let nextPage = page + 1
        let target = username
        loadingMore = true
        pageTask = Task {
            do {
                let result = try await api.repositories(username: target, page: nextPage)
                guard !Task.isCancelled && request == generation else { return }
                let present = Set(repositories.map(\.id))
                repositories += result.repositories.filter { !present.contains($0.id) }
                page = nextPage
                hasMore = result.hasMore
            } catch is CancellationError {
                return
            } catch {
                if request == generation { errorMessage = error.localizedDescription }
            }
            if request == generation { loadingMore = false }
        }
    }

    /// A bounded sample of four public repositories does not represent the account's
    /// complete CI health. Never interpret zero failed runs as all checks passed.
    var partial: Bool {
        !warnings.isEmpty || hasMore || repositories.count > monitoredRepositories
    }

    var failedRuns: [PublicWorkflowRun] { workflowRuns.filter(\.failed) }
    var runningRuns: [PublicWorkflowRun] { workflowRuns.filter(\.running) }
}
