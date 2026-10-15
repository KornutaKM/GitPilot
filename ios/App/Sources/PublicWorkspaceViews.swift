import SwiftUI
import GitPilotCore

struct PublicWorkspaceRoot: View {
    @StateObject private var store = PublicWorkspaceStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { TodayScreen(store: store) }
                    .tabItem { Label("Today", systemImage: "square.grid.2x2.fill") }
                NavigationStack { ReviewsScreen(store: store) }
                    .tabItem { Label("Reviews", systemImage: "arrow.triangle.pull") }
                NavigationStack { ActionsScreen(store: store) }
                    .tabItem { Label("Actions", systemImage: "bolt.fill") }
                NavigationStack { RepositoriesScreen(store: store) }
                    .tabItem { Label("Repos", systemImage: "square.stack.3d.up.fill") }
            }
            .tint(GP.accent)

            // Mirror RC3's app-switcher privacy cover; future OAuth/private
            // views must not remain readable in app switcher snapshots.
            if scenePhase != .active {
                GP.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36)).foregroundStyle(GP.accent)
                    Text("GitPilot").font(.title2.bold()).foregroundStyle(.white)
                    Text("Workspace hidden").font(.caption).foregroundStyle(GP.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("GitPilot content hidden")
            }
        }
        .preferredColorScheme(.dark)
        .task { if !store.hasLoaded && !store.isLoading { store.refresh() } }
    }
}

private struct LoadingOrError: View {
    @ObservedObject var store: PublicWorkspaceStore
    var body: some View {
        Group {
            if store.isLoading {
                Surface {
                    ProgressView("Reading public GitHub data…")
                        .tint(GP.accent)
                        .foregroundStyle(.white)
                }
            }
            if let error = store.errorMessage {
                Surface {
                    Label("GitHub request failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(GP.amber)
                    Text(error).font(.caption).foregroundStyle(GP.secondary)
                    Button("Retry") { store.refresh() }.buttonStyle(.bordered)
                }
            }
            if store.partial && store.hasLoaded {
                Surface {
                    Label("Partial GitHub overview", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GP.amber)
                    Text("Only the first \(store.monitoredRepositories) public repositories are checked for pull requests and Actions. Other checks may exist.")
                        .font(.caption).foregroundStyle(GP.secondary)
                    ForEach(store.warnings, id: \.self) { message in
                        MetaText(text: "• \(message)")
                    }
                }
            }
        }
    }
}

private struct Metric: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GPIndicator(icon: symbol, tint: tint)
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(GP.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GP.card, in: RoundedRectangle(cornerRadius: GP.radius))
    }
}

private struct TodayScreen: View {
    @ObservedObject var store: PublicWorkspaceStore
    @State private var showingProfile = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                GPHeader(
                    eyebrow: "@\(store.username) · PUBLIC PREVIEW",
                    title: "Your work,\nat a glance.",
                    subtitle: "Read-only GitHub activity across a bounded sample of public projects."
                )
                HStack(spacing: 12) {
                    Metric(value: store.pullRequests.count, label: "Sample PRs",
                           symbol: "arrow.triangle.pull", tint: GP.accent)
                    Metric(value: store.failedRuns.count, label: "Failed in sample",
                           symbol: "xmark.circle.fill", tint: GP.red)
                }
                LoadingOrError(store: store)
                GPSectionTitle(title: "Needs attention", detail: "Visible failed runs")
                if store.failedRuns.isEmpty {
                    GPEmptyState(
                        icon: "checkmark.shield",
                        title: "No failures in loaded sample",
                        detail: "This is not a claim that every repository's CI passed. Inspect GitHub for complete checks."
                    )
                } else {
                    ForEach(Array(store.failedRuns.prefix(4))) { run in
                        WorkflowCard(run: run)
                    }
                }
                if !store.runningRuns.isEmpty {
                    GPSectionTitle(title: "In progress", detail: "Monitored workflows")
                    ForEach(Array(store.runningRuns.prefix(3))) { run in
                        WorkflowCard(run: run)
                    }
                }
                Surface {
                    Eyebrow(text: "INTEGRATION STATUS")
                    Text("iOS RC3 migration")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("Public browsing is connected to GitHub. OAuth, private repositories, reviews, merges and publishing are intentionally unavailable in this build.")
                        .font(.footnote).foregroundStyle(GP.secondary)
                    StatusPill(text: "Read-only alpha", color: GP.amber)
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingProfile = true } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }
        }
        .sheet(isPresented: $showingProfile) { ProfileEditor(store: store) }
        .refreshable { store.refresh() }
    }
}

private struct ReviewsScreen: View {
    @ObservedObject var store: PublicWorkspaceStore
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PULL REQUESTS", title: "Reviews.",
                         subtitle: "Open pull requests from monitored public repositories.")
                LoadingOrError(store: store)
                if store.pullRequests.isEmpty && !store.isLoading {
                    GPEmptyState(icon: "arrow.triangle.pull", title: "No PRs in loaded sample",
                                 detail: "More public repositories may have open pull requests.")
                }
                ForEach(store.pullRequests) { pull in
                    Surface {
                        HStack {
                            StatusPill(text: pull.draft ? "Draft" : "Open", color: pull.draft ? GP.secondary : GP.green)
                            Spacer(minLength: 4)
                            Text("#\(pull.number)").font(.caption.monospacedDigit()).foregroundStyle(GP.secondary)
                        }
                        Text(pull.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        MetaText(text: "@\(pull.user.login) · \(pull.head.ref) → \(pull.base.ref)")
                        SafeGitHubLink(title: "View PR on GitHub", url: pull.htmlURL)
                    }
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.refresh() }
    }
}

private struct WorkflowCard: View {
    let run: PublicWorkflowRun
    var body: some View {
        Surface {
            HStack {
                GPIndicator(icon: run.failed ? "xmark.circle.fill" :
                    run.running ? "clock.fill" : "checkmark.circle.fill",
                    tint: run.failed ? GP.red : run.running ? GP.blue : GP.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).lineLimit(2)
                    MetaText(text: run.headBranch ?? "Unknown branch")
                }
                Spacer(minLength: 4)
                StatusPill(text: run.conclusion ?? run.status,
                           color: run.failed ? GP.red : run.running ? GP.blue : GP.green)
            }
            SafeGitHubLink(title: "Inspect run on GitHub", url: run.htmlURL)
        }
    }
}

private struct ActionsScreen: View {
    @ObservedObject var store: PublicWorkspaceStore
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "GITHUB ACTIONS", title: "Workflows.",
                         subtitle: "Recent runs in the monitored public repositories. No write actions.")
                LoadingOrError(store: store)
                if store.workflowRuns.isEmpty && !store.isLoading {
                    GPEmptyState(icon: "bolt", title: "No runs in loaded sample",
                                 detail: "The absence of runs here is not proof that CI is green.")
                }
                ForEach(store.workflowRuns) { WorkflowCard(run: $0) }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.refresh() }
    }
}

private struct RepositoriesScreen: View {
    @ObservedObject var store: PublicWorkspaceStore
    @State private var showingProfile = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "@\(store.username)", title: "Repositories.",
                         subtitle: "Recent public repositories, sorted by activity.")
                Button {
                    showingProfile = true
                } label: {
                    Label("Browse another public profile", systemImage: "person.crop.circle.badge.questionmark")
                }
                .buttonStyle(.bordered)
                LoadingOrError(store: store)
                if store.repositories.isEmpty && !store.isLoading {
                    GPEmptyState(icon: "folder", title: "No public repositories loaded",
                                 detail: "Try another username or retry the GitHub request.")
                }
                ForEach(store.repositories) { repository in
                    NavigationLink {
                        RepositoryDetailsScreen(repository: repository)
                    } label: {
                        Surface {
                            HStack(alignment: .top, spacing: 12) {
                                GPIndicator(icon: "folder.fill", tint: GP.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(repository.fullName).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    if let summary = repository.description, !summary.isEmpty {
                                        Text(summary).font(.caption).foregroundStyle(GP.secondary)
                                            .lineLimit(2)
                                    }
                                    MetaText(text: "\(repository.language ?? "Unspecified") · ★ \(repository.stargazersCount)")
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(GP.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if store.hasMore {
                    Button {
                        store.loadMore()
                    } label: {
                        if store.loadingMore { ProgressView().tint(GP.accent) }
                        else { Label("Load more public repositories", systemImage: "arrow.down.circle") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.loadingMore)
                    .frame(maxWidth: .infinity)
                }
                MetaText(text: "Up to 3 × 12 repositories per profile. Only the first 4 are monitored for PRs and Actions.")
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Repos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProfile) { ProfileEditor(store: store) }
        .refreshable { store.refresh() }
    }
}

private struct RepositoryDetailsScreen: View {
    let repository: PublicRepository
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GPHeader(eyebrow: "PUBLIC REPOSITORY", title: repository.name,
                         subtitle: repository.fullName)
                Surface {
                    Text(repository.description ?? "No description.")
                        .foregroundStyle(.white)
                    MetaText(text: "Default branch: \(repository.defaultBranch)")
                    MetaText(text: "Language: \(repository.language ?? "Unknown")")
                    MetaText(text: "Stars: \(repository.stargazersCount)")
                    SafeGitHubLink(title: "Open repository on GitHub", url: repository.htmlURL)
                }
                if PublicGitHubAPI.validBranchRef(repository.defaultBranch) {
                    NavigationLink {
                        PublicDirectoryScreen(repository: repository,
                                              branch: repository.defaultBranch, path: "")
                    } label: {
                        Surface {
                            Label("Browse public files", systemImage: "folder.fill")
                                .foregroundStyle(.white)
                            MetaText(text: "Folders and small UTF-8 file previews")
                        }
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        PublicCommitsScreen(repository: repository, branch: repository.defaultBranch)
                    } label: {
                        Surface {
                            Label("Recent commits", systemImage: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(.white)
                            MetaText(text: "Up to 12 latest commits on the default branch")
                        }
                    }
                    .buttonStyle(.plain)
                }
                GPEmptyState(icon: "lock.shield",
                             title: "Read-only integration milestone",
                             detail: "Authenticated repositories, staging and remote commits remain disabled until the RC3 Keychain/OAuth migration.")
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SafeGitHubLink: View {
    let title: String
    let url: URL?
    var body: some View {
        if let safe = PublicGitHubAPI.safeGitHubWebURL(url) {
            Link(destination: safe) {
                Label(title, systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.medium))
            }
        } else {
            MetaText(text: "GitHub link unavailable")
        }
    }
}

private struct ProfileEditor: View {
    @ObservedObject var store: PublicWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Public profile") {
                    TextField("GitHub username", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    Text("Only public repositories are visible. No authentication tokens are saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Browse public projects") {
                        guard PublicGitHubAPI.validUsername(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                            return
                        }
                        store.selectProfile(draft)
                        dismiss()
                    }
                    .disabled(!PublicGitHubAPI.validUsername(draft.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .navigationTitle("GitHub profile")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") { dismiss() }
            }}
            .onAppear { draft = store.username }
        }
    }
}
