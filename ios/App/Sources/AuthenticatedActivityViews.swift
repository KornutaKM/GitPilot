import SwiftUI
import GitPilotCore

/// One verified repository, three read-only capabilities.
struct AuthenticatedRepositoryHubScreen: View {
    let repository: PublicRepository
    @EnvironmentObject private var account: OAuthAccountSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GPHeader(eyebrow: "VERIFIED ACCOUNT · READ ONLY",
                         title: repository.name, subtitle: repository.fullName)
                if account.authenticatedAs == nil || account.busy {
                    GPEmptyState(icon: "lock.shield.fill",
                                 title: "Repository locked",
                                 detail: "A verified GitHub App account is required.")
                } else {
                    if PublicGitHubAPI.validBranchRef(repository.defaultBranch) {
                        NavigationLink {
                            AuthenticatedDirectoryScreen(repository: repository,
                                branch: repository.defaultBranch, path: "")
                        } label: {
                            actionRow("Source", "Browse private folders and small text files",
                                      "folder.fill", GP.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        AuthenticatedPullRequestsScreen(repository: repository)
                    } label: {
                        actionRow("Reviews", "Open pull requests, diffs and comments",
                                  "arrow.triangle.pull", GP.blue)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        AuthenticatedWorkflowRunsScreen(repository: repository)
                    } label: {
                        actionRow("Actions", "Workflow runs, conclusions and jobs",
                                  "bolt.fill", GP.amber)
                    }
                    .buttonStyle(.plain)
                    GPEmptyState(icon: "lock.shield.fill",
                                 title: "Remote writes remain disabled",
                                 detail: "No merge, review submission, file commit, workflow retry or dispatch.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionRow(_ title: String, _ summary: String, _ icon: String,
                           _ color: Color) -> some View {
        Surface {
            HStack(spacing: 12) {
                GPIndicator(icon: icon, tint: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    MetaText(text: summary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(GP.secondary)
            }
        }
    }
}

struct AuthenticatedPullRequestsScreen: View {
    let repository: PublicRepository
    @EnvironmentObject private var account: OAuthAccountSession
    @StateObject private var pager = AuthenticatedActivityPager<PublicPullRequest>()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PRIVATE PR · READ ONLY",
                         title: "Reviews.",
                         subtitle: "\(repository.fullName) · Open pull requests")
                if account.authenticatedAs == nil || account.busy {
                    GPEmptyState(icon: "lock.fill", title: "Reviews locked",
                                 detail: "Sign in with the authorized GitHub App account.")
                } else {
                    if pager.loading && pager.items.isEmpty {
                        Surface { ProgressView("Reading pull requests…").tint(GP.accent) }
                    }
                    if let error = pager.errorMessage {
                        Surface {
                            Text(error).foregroundStyle(GP.amber).font(.caption)
                            Button("Retry") { Task { await refresh() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    ForEach(pager.items) { pull in
                        NavigationLink {
                            AuthenticatedPullDetailsScreen(repository: repository, pull: pull)
                        } label: {
                            Surface {
                                HStack {
                                    StatusPill(text: pull.draft ? "Draft" : "Open",
                                               color: pull.draft ? GP.secondary : GP.green)
                                    Spacer()
                                    Text("#\(pull.number)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(GP.secondary)
                                }
                                Text(pull.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                MetaText(text: "@\(pull.user.login) · \(pull.head.ref) → \(pull.base.ref)")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if pager.hasMore {
                        Button { Task { await loadMore() } } label: {
                            Label("Load more pull requests", systemImage: "arrow.down.circle")
                        }
                        .disabled(pager.loading)
                        .buttonStyle(.borderedProminent)
                    }
                    if pager.loaded && pager.items.isEmpty && pager.errorMessage == nil {
                        GPEmptyState(icon: "arrow.triangle.pull",
                                     title: "No PRs in loaded sample",
                                     detail: "GitHub returned no open pull requests in the first page.")
                    }
                    MetaText(text: "Up to 3 × 20 open PRs. Complete history is available on GitHub.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await refresh() }
        .onDisappear { pager.clear() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await pager.reload(account: account, fetch: { token, page in
            try await AuthenticatedActivityAPI().pullRequests(
                repository: repository, token: token, page: page)
        })
    }
    private func loadMore() async {
        await pager.next(account: account, fetch: { token, page in
            try await AuthenticatedActivityAPI().pullRequests(
                repository: repository, token: token, page: page)
        })
    }
}

struct AuthenticatedWorkflowRunsScreen: View {
    let repository: PublicRepository
    @EnvironmentObject private var account: OAuthAccountSession
    @StateObject private var pager = AuthenticatedActivityPager<PublicWorkflowRun>()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PRIVATE CI · READ ONLY",
                         title: "Actions.",
                         subtitle: "\(repository.fullName) · Recent workflow runs")
                if account.authenticatedAs == nil || account.busy {
                    GPEmptyState(icon: "lock.fill", title: "Actions locked",
                                 detail: "Sign in with a verified GitHub App account.")
                } else {
                    if pager.loading && pager.items.isEmpty {
                        Surface { ProgressView("Reading workflow runs…").tint(GP.accent) }
                    }
                    if let error = pager.errorMessage {
                        Surface {
                            Text(error).foregroundStyle(GP.amber).font(.caption)
                            Button("Retry") { Task { await refresh() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    ForEach(pager.items) { run in
                        NavigationLink {
                            AuthenticatedWorkflowJobsScreen(repository: repository, run: run)
                        } label: {
                            Surface {
                                HStack(spacing: 10) {
                                    GPIndicator(icon: run.failed ? "xmark.circle.fill" :
                                        run.running ? "clock.fill" : "checkmark.circle.fill",
                                        tint: run.failed ? GP.red : run.running ? GP.blue : GP.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(run.title).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        MetaText(text: run.headBranch ?? "Unknown branch")
                                    }
                                    Spacer(minLength: 4)
                                    StatusPill(text: run.conclusion ?? run.status,
                                        color: run.failed ? GP.red : run.running ? GP.blue : GP.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if pager.hasMore {
                        Button { Task { await loadMore() } } label: {
                            Label("Load more workflow runs", systemImage: "arrow.down.circle")
                        }
                        .disabled(pager.loading)
                        .buttonStyle(.borderedProminent)
                    }
                    if pager.loaded && pager.items.isEmpty && pager.errorMessage == nil {
                        GPEmptyState(icon: "bolt", title: "No workflow runs in sample",
                                     detail: "An empty result is not proof that CI is green.")
                    }
                    MetaText(text: "Up to 3 × 20 runs per repository. Jobs display read-only details.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await refresh() }
        .onDisappear { pager.clear() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await pager.reload(account: account, fetch: { token, page in
            try await AuthenticatedActivityAPI().workflowRuns(
                repository: repository, token: token, page: page)
        })
    }
    private func loadMore() async {
        await pager.next(account: account, fetch: { token, page in
            try await AuthenticatedActivityAPI().workflowRuns(
                repository: repository, token: token, page: page)
        })
    }
}
