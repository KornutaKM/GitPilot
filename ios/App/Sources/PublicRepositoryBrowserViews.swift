import SwiftUI
import GitPilotCore

/// Additional RC3 browsing slice: no token and no GitHub mutations.
struct PublicDirectoryScreen: View {
    let repository: PublicRepository
    let branch: String
    let path: String

    @State private var entries: [PublicFileEntry] = []
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "REPOSITORY FILES", title: path.isEmpty ? repository.name : path,
                         subtitle: "Read-only · \(branch)")
                if loading {
                    Surface { ProgressView("Loading GitHub directory…").tint(GP.accent) }
                }
                if let errorMessage {
                    Surface {
                        Text(errorMessage).foregroundStyle(GP.amber)
                            .font(.caption)
                        Button("Retry") { Task { await load() } }.buttonStyle(.bordered)
                    }
                }
                if entries.isEmpty && !loading && errorMessage == nil {
                    GPEmptyState(icon: "folder", title: "Empty directory",
                                 detail: "GitHub returned no files in this folder.")
                }
                ForEach(entries) { item in
                    if item.isDirectory {
                        NavigationLink {
                            PublicDirectoryScreen(repository: repository, branch: branch, path: item.path)
                        } label: {
                            fileRow(item, icon: "folder.fill", tint: GP.accent)
                        }
                        .buttonStyle(.plain)
                    } else if item.isFile {
                        NavigationLink {
                            PublicFilePreviewScreen(repository: repository, branch: branch, entry: item)
                        } label: {
                            fileRow(item, icon: "doc.text", tint: GP.blue)
                        }
                        .buttonStyle(.plain)
                    } else {
                        fileRow(item, icon: "shippingbox", tint: GP.secondary)
                    }
                }
                MetaText(text: "At most 100 entries per directory; text file preview is limited to 64 KB.")
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(path.isEmpty ? repository.name : String(path.split(separator: "/").last ?? "Files"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await load() }
    }

    @ViewBuilder
    private func fileRow(_ entry: PublicFileEntry, icon: String, tint: Color) -> some View {
        Surface {
            HStack(spacing: 12) {
                GPIndicator(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    MetaText(text: entry.isDirectory ? "Folder" :
                        entry.isFile ? "\(entry.size ?? 0) bytes" : entry.type)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(GP.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        entries = []
        errorMessage = nil
        do {
            let response = try await PublicGitHubAPI().directory(
                repository: repository, branch: branch, path: path)
            guard !Task.isCancelled else { return }
            entries = response
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
        loading = false
    }
}

struct PublicFilePreviewScreen: View {
    let repository: PublicRepository
    let branch: String
    let entry: PublicFileEntry

    @State private var preview: PublicFilePreview?
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GPHeader(eyebrow: "TEXT PREVIEW", title: entry.name, subtitle: entry.path)
                if loading {
                    Surface { ProgressView("Downloading preview…").tint(GP.accent) }
                } else if let errorMessage {
                    GPEmptyState(icon: "doc.badge.ellipsis",
                                 title: "File preview unavailable", detail: errorMessage)
                }
                if let preview {
                    ScrollView(.horizontal) {
                        Text(preview.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .padding(18)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GP.card, in: RoundedRectangle(cornerRadius: GP.radius))
                }
                if let url = PublicGitHubAPI.safeGitHubWebURL(entry.htmlURL) {
                    Link("Open full file on GitHub", destination: url)
                        .font(.caption.weight(.semibold))
                }
                MetaText(text: "UTF-8 text only. No editing or remote commits in public mode.")
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                preview = try await PublicGitHubAPI().preview(
                    repository: repository, branch: branch, file: entry)
            } catch is CancellationError { return }
            catch { errorMessage = error.localizedDescription }
            loading = false
        }
    }
}

struct PublicCommitsScreen: View {
    let repository: PublicRepository
    let branch: String

    @State private var commits: [PublicCommit] = []
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "HISTORY", title: "Recent commits.", subtitle: "\(repository.fullName) · \(branch)")
                if loading { Surface { ProgressView("Loading commits…").tint(GP.accent) } }
                if let errorMessage {
                    GPEmptyState(icon: "exclamationmark.triangle",
                                 title: "Cannot load Git history", detail: errorMessage)
                }
                ForEach(commits) { commit in
                    Surface {
                        Text(commit.subject).font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        MetaText(text: String(commit.sha.prefix(10)))
                        if let url = PublicGitHubAPI.safeGitHubWebURL(commit.htmlURL) {
                            Link("Inspect commit on GitHub", destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                MetaText(text: "First 12 commits on the default branch. Complete history is available on GitHub.")
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Commits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                commits = try await PublicGitHubAPI().recentCommits(
                    repository: repository, branch: branch)
            } catch is CancellationError { return }
            catch { errorMessage = error.localizedDescription }
            loading = false
        }
    }
}
