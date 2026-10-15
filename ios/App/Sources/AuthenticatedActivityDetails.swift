import SwiftUI
import GitPilotCore

struct AuthenticatedPullDetailsScreen: View {
    let repository: PublicRepository
    let pull: PublicPullRequest

    @EnvironmentObject private var account: OAuthAccountSession
    @State private var files: [AuthenticatedActivityAPI.PullFile] = []
    @State private var discussion: AuthenticatedActivityAPI.Discussion?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var generation = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PR #\(pull.number) · READ ONLY",
                         title: pull.title,
                         subtitle: repository.fullName)
                if account.authenticatedAs == nil || account.busy {
                    GPEmptyState(icon: "lock.shield.fill", title: "Private PR locked",
                                 detail: "GitHub App authorization is required.")
                } else {
                    Surface {
                        HStack {
                            StatusPill(text: pull.draft ? "Draft" : "Open",
                                       color: pull.draft ? GP.secondary : GP.green)
                            Spacer(minLength: 4)
                            MetaText(text: "@\(pull.user.login)")
                        }
                        MetaText(text: "\(pull.head.ref) → \(pull.base.ref)")
                        if let url = PublicGitHubAPI.safeGitHubWebURL(pull.htmlURL) {
                            Link("Open full PR on GitHub", destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if loading {
                        Surface { ProgressView("Loading private PR details…").tint(GP.accent) }
                    }
                    if let errorMessage {
                        Surface {
                            Text(errorMessage).foregroundStyle(GP.amber).font(.caption)
                            Button("Retry") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    GPSectionTitle(title: "Changed files", detail: "First 30 only")
                    if !loading && files.isEmpty && errorMessage == nil {
                        GPEmptyState(icon: "doc", title: "No changed files in sample",
                                     detail: "The complete PR diff is available on GitHub.")
                    }
                    ForEach(files) { file in
                        Surface {
                            HStack {
                                Text(file.filename).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(3)
                                Spacer(minLength: 4)
                                StatusPill(text: file.status, color: GP.blue)
                            }
                            MetaText(text: "+\(file.additions) / −\(file.deletions)")
                            if let patch = file.patch, !patch.isEmpty {
                                ScrollView(.horizontal) {
                                    Text(patch)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .textSelection(.enabled)
                                        .padding(10)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GP.raised, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                MetaText(text: "Patch unavailable (binary, large or unsupported diff).")
                            }
                            if let url = PublicGitHubAPI.safeGitHubWebURL(file.blobURL) {
                                Link("Inspect source on GitHub", destination: url)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    GPSectionTitle(title: "Discussion", detail: "First 20 of each type")
                    if let discussion {
                        if discussion.issueComments.isEmpty && discussion.reviewComments.isEmpty {
                            GPEmptyState(icon: "bubble.left", title: "No comments in sample",
                                         detail: "Only the first page of each discussion type is loaded.")
                        }
                        ForEach(discussion.issueComments) { comment in
                            commentRow(comment, label: "Conversation")
                        }
                        ForEach(discussion.reviewComments) { comment in
                            commentRow(comment, label: "Inline review")
                        }
                    }
                    MetaText(text: "Discussion and patches are read-only. Posting reviews or merging is disabled.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("PR #\(pull.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await load() }
        .onChange(of: account.authenticatedAs) { _ in clear() }
        .onDisappear { clear() }
    }

    private func commentRow(_ comment: AuthenticatedActivityAPI.Comment, label: String) -> some View {
        Surface {
            HStack {
                StatusPill(text: label, color: GP.secondary)
                Spacer(minLength: 4)
                MetaText(text: "@\(comment.user?.login ?? "deleted")")
            }
            if let path = comment.path {
                MetaText(text: path + (comment.line.map { ":\($0)" } ?? ""))
            }
            Text(comment.body ?? "(No text)")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(10)
            if let url = PublicGitHubAPI.safeGitHubWebURL(comment.htmlURL) {
                Link("View comment on GitHub", destination: url).font(.caption)
            }
        }
    }

    @MainActor
    private func clear() {
        generation += 1
        files = []
        discussion = nil
        errorMessage = nil
        loading = false
    }

    @MainActor
    private func load() async {
        clear()
        guard let expectedLogin = account.authenticatedAs, !account.busy else { return }
        let requestGeneration = generation
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await account.tokenForProtectedRead()
            let revision = account.authRevision
            let api = AuthenticatedActivityAPI()
            let loadedFiles = try await api.pullFiles(
                repository: repository, number: pull.number, token: token)
            let loadedDiscussion = try await api.discussion(
                repository: repository, number: pull.number, token: token)
            guard requestGeneration == generation, !Task.isCancelled,
                  revision == account.authRevision,
                  account.authenticatedAs == expectedLogin, !account.busy else { return }
            files = loadedFiles
            discussion = loadedDiscussion
        } catch is CancellationError { return }
        catch {
            guard requestGeneration == generation, !Task.isCancelled,
                  account.authenticatedAs == expectedLogin else { return }
            if let issue = error as? AuthenticatedActivityAPI.ActivityError,
               issue == .revoked {
                account.signOut()
                clear()
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct AuthenticatedWorkflowJobsScreen: View {
    let repository: PublicRepository
    let run: PublicWorkflowRun

    @EnvironmentObject private var account: OAuthAccountSession
    @State private var jobs: [AuthenticatedActivityAPI.Job] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var generation = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "ACTIONS · READ ONLY",
                         title: run.title, subtitle: repository.fullName)
                if account.authenticatedAs == nil || account.busy {
                    GPEmptyState(icon: "lock.shield.fill", title: "Workflow jobs locked",
                                 detail: "GitHub App authorization is required.")
                } else {
                    Surface {
                        HStack {
                            StatusPill(text: run.conclusion ?? run.status,
                                       color: run.failed ? GP.red : run.running ? GP.blue : GP.green)
                            Spacer()
                            MetaText(text: run.headBranch ?? "Unknown branch")
                        }
                        if let url = PublicGitHubAPI.safeGitHubWebURL(run.htmlURL) {
                            Link("Open full workflow run on GitHub", destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if loading {
                        Surface { ProgressView("Reading workflow jobs…").tint(GP.accent) }
                    }
                    if let errorMessage {
                        Surface {
                            Text(errorMessage).foregroundStyle(GP.amber).font(.caption)
                            Button("Retry") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    GPSectionTitle(title: "Jobs", detail: "First 50 only")
                    ForEach(jobs) { job in
                        Surface {
                            HStack {
                                Text(job.name).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white).lineLimit(2)
                                Spacer(minLength: 4)
                                StatusPill(text: job.conclusion ?? job.status,
                                            color: job.conclusion == "failure" ? GP.red :
                                                job.status == "completed" ? GP.green : GP.blue)
                            }
                            if let url = PublicGitHubAPI.safeGitHubWebURL(job.htmlURL) {
                                Link("View job on GitHub", destination: url)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    if !loading && errorMessage == nil && jobs.isEmpty {
                        GPEmptyState(icon: "bolt", title: "No jobs in loaded sample",
                                     detail: "More jobs may exist outside the first GitHub page.")
                    }
                    MetaText(text: "Re-run, cancel, dispatch and artifact downloads remain disabled.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Workflow jobs")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await load() }
        .onChange(of: account.authenticatedAs) { _ in clear() }
        .onDisappear { clear() }
    }

    @MainActor
    private func clear() {
        generation += 1
        jobs = []
        loading = false
        errorMessage = nil
    }

    @MainActor
    private func load() async {
        clear()
        guard let expectedLogin = account.authenticatedAs, !account.busy else { return }
        let requestGeneration = generation
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await account.tokenForProtectedRead()
            let revision = account.authRevision
            let loaded = try await AuthenticatedActivityAPI().workflowJobs(
                repository: repository, runID: run.id, token: token)
            guard requestGeneration == generation, !Task.isCancelled,
                  revision == account.authRevision,
                  account.authenticatedAs == expectedLogin, !account.busy else { return }
            jobs = loaded
        } catch is CancellationError { return }
        catch {
            guard requestGeneration == generation, !Task.isCancelled,
                  account.authenticatedAs == expectedLogin else { return }
            if let issue = error as? AuthenticatedActivityAPI.ActivityError,
               issue == .revoked {
                account.signOut()
                clear()
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
