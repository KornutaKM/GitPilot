import SwiftUI
import GitPilotCore

/// Account-scoped private repository browser. No cached private data on disk,
/// no unsafe path construction and no GitHub write operation.
struct AuthenticatedDirectoryScreen: View {
    let repository: PublicRepository
    let branch: String
    let path: String

    @EnvironmentObject private var account: OAuthAccountSession
    @State private var entries: [PublicFileEntry] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var boundLogin: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PROTECTED SOURCE · READ ONLY",
                         title: path.isEmpty ? repository.name : String(path.split(separator: "/").last ?? "Files"),
                         subtitle: "\(repository.fullName) · \(branch)")
                if account.authenticatedAs == nil || account.busy ||
                   (boundLogin != nil && account.authenticatedAs?.lowercased() != boundLogin?.lowercased()) {
                    GPEmptyState(icon: "lock.shield.fill", title: "Protected repository locked",
                                 detail: "A verified GitHub App session is required.")
                } else {
                    if loading {
                        Surface { ProgressView("Loading protected directory…").tint(GP.accent) }
                    }
                    if let errorMessage {
                        GPEmptyState(icon: "exclamationmark.triangle",
                                     title: "Directory unavailable", detail: errorMessage)
                    }
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                AuthenticatedDirectoryScreen(
                                    repository: repository, branch: branch, path: entry.path)
                            } label: { fileRow(entry, icon: "folder.fill") }
                                .buttonStyle(.plain)
                        } else if entry.isFile {
                            NavigationLink {
                                AuthenticatedFileScreen(
                                    repository: repository, branch: branch, file: entry)
                            } label: { fileRow(entry, icon: "doc.text") }
                                .buttonStyle(.plain)
                        } else {
                            fileRow(entry, icon: "link")
                        }
                    }
                    if !loading && errorMessage == nil && entries.isEmpty {
                        GPEmptyState(icon: "folder", title: "Empty directory",
                                     detail: "GitHub returned no files in this folder.")
                    }
                    MetaText(text: "Up to 100 files per directory; private text previews are limited to 64 KB.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(path.isEmpty ? repository.name : String(path.split(separator: "/").last ?? "Files"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await load() }
        .onChange(of: account.authenticatedAs) { _ in clear() }
        .onDisappear { clear() }
    }

    private func fileRow(_ file: PublicFileEntry, icon: String) -> some View {
        Surface {
            HStack(spacing: 12) {
                GPIndicator(icon: icon, tint: file.isDirectory ? GP.accent : GP.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.name).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    MetaText(text: file.isDirectory ? "Directory" :
                        file.isFile ? "\(file.size ?? 0) bytes" : "Unsupported link")
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(GP.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @MainActor
    private func clear() {
        entries = []
        loading = false
        errorMessage = nil
    }

    @MainActor
    private func load() async {
        clear()
        guard let expectedLogin = account.authenticatedAs, !account.busy else { return }
        if let boundLogin, boundLogin.lowercased() != expectedLogin.lowercased() { return }
        if boundLogin == nil { boundLogin = expectedLogin }
        loading = true
        do {
            let token = try await account.tokenForProtectedRead()
            let revision = account.authRevision
            let result = try await AuthenticatedContentsAPI().directory(
                repository: repository, branch: branch, path: path, token: token)
            guard !Task.isCancelled, account.authRevision == revision,
                  account.authenticatedAs == expectedLogin, !account.busy else { return }
            entries = result
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, account.authenticatedAs == expectedLogin else { return }
            if let cause = error as? AuthenticatedContentsAPI.ReadError, cause == .revoked {
                account.signOut()
                clear()
                return
            }
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

struct AuthenticatedFileScreen: View {
    let repository: PublicRepository
    let branch: String
    let file: PublicFileEntry

    @EnvironmentObject private var account: OAuthAccountSession
    @State private var preview: PublicFilePreview?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var boundLogin: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GPHeader(eyebrow: "PROTECTED TEXT · READ ONLY", title: file.name,
                         subtitle: file.path)
                if account.authenticatedAs == nil || account.busy ||
                   (boundLogin != nil && account.authenticatedAs?.lowercased() != boundLogin?.lowercased()) {
                    GPEmptyState(icon: "lock.shield.fill", title: "Preview locked",
                                 detail: "Sign in again to view protected source.")
                } else {
                    if loading {
                        Surface { ProgressView("Reading protected file…").tint(GP.accent) }
                    }
                    if let errorMessage {
                        GPEmptyState(icon: "exclamationmark.triangle",
                                     title: "Cannot preview protected file", detail: errorMessage)
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
                    MetaText(text: "UTF-8 only; source remains in memory and is cleared on sign-out.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.authRevision) { await load() }
        .onChange(of: account.authenticatedAs) { _ in clear() }
        .onDisappear { clear() }
    }

    @MainActor
    private func clear() {
        preview = nil
        errorMessage = nil
        loading = false
    }

    @MainActor
    private func load() async {
        clear()
        guard let expectedLogin = account.authenticatedAs, !account.busy else { return }
        if let boundLogin, boundLogin.lowercased() != expectedLogin.lowercased() { return }
        if boundLogin == nil { boundLogin = expectedLogin }
        loading = true
        do {
            let token = try await account.tokenForProtectedRead()
            let revision = account.authRevision
            let result = try await AuthenticatedContentsAPI().preview(
                repository: repository, branch: branch, file: file, token: token)
            guard !Task.isCancelled, account.authRevision == revision,
                  account.authenticatedAs == expectedLogin, !account.busy else { return }
            preview = result
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, account.authenticatedAs == expectedLogin else { return }
            if let cause = error as? AuthenticatedContentsAPI.ReadError, cause == .revoked {
                account.signOut()
                clear()
                return
            }
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
