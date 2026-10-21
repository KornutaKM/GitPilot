import SwiftUI
import GitPilotCore

/// The only overview of encrypted local edits. Never syncs drafts or source to
/// GitHub, telemetry, backups, search indexing or UserDefaults.
struct EncryptedDraftsScreen: View {
    @EnvironmentObject private var account: OAuthAccountSession
    @State private var drafts: [StagedFileEdit] = []
    @State private var boundLogin: String?
    @State private var boundRevision: Int?
    @State private var error: String?
    @State private var status: String?
    @State private var confirmErase = false

    private var authorized: Bool {
        guard let boundLogin, let boundRevision else { return false }
        return boundRevision == account.authRevision &&
            boundLogin.lowercased() == account.authenticatedAs?.lowercased() &&
            !account.busy
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                GPWelcomeCard(
                    eyebrow: "ENCRYPTED ON THIS DEVICE",
                    title: "Saved changes.",
                    subtitle: "Small, private edits you can review without sending anything to GitHub.",
                    icon: "lock.doc"
                )
                if !authorized {
                    GPEmptyState(icon: "lock.shield.fill",
                                 title: "Drafts are locked",
                                 detail: "Reopen after verifying your GitHub account.")
                } else {
                    HStack {
                        StatusPill(text: "\(drafts.count) / 12 files", color: GP.accent)
                        Spacer()
                        if !drafts.isEmpty {
                            Button("Erase all drafts", role: .destructive) {
                                confirmErase = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    if let error {
                        GPEmptyState(icon: "exclamationmark.triangle",
                                     title: "Secure storage unavailable", detail: error)
                    }
                    if let status {
                        Label(status, systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(GP.green)
                    }
                    if drafts.isEmpty && error == nil {
                        GPEmptyState(icon: "doc.text",
                                     title: "No staged changes yet",
                                     detail: "Open a private text file, edit it and save an encrypted draft.")
                    }
                    ForEach(drafts) { draft in
                        Surface {
                            HStack(spacing: 10) {
                                GPIndicator(icon: "doc.text", tint: GP.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft.path)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(GP.ink)
                                        .lineLimit(2)
                                    MetaText(text: draft.repositoryFullName + " · " + draft.branch)
                                }
                                Spacer(minLength: 4)
                                StatusPill(text: "Local only", color: GP.green)
                            }
                            MetaText(text: "Original SHA: " + String(draft.originalBlobSHA.prefix(12)) +
                                     " · " + String(draft.byteCount) + " bytes")
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(StagedDiffPreview.lines(
                                        from: draft.originalContent,
                                        to: draft.newContent, maxLines: 40)) { line in
                                        Text(line.prefix + " " + line.text)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(line.kind == .addition ? GP.green :
                                                line.kind == .deletion ? GP.red : GP.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button(role: .destructive) {
                                remove(draft)
                            } label: {
                                Label("Delete this local draft", systemImage: "trash")
                            }
                            .font(.caption.weight(.medium))
                        }
                    }
                    MetaText(text: "Encrypted with AES-256-GCM. Changing accounts or signing out erases local drafts. No cloud upload or commits.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            boundLogin = account.authenticatedAs
            boundRevision = account.authRevision
            reload()
        }
        .onChange(of: account.authRevision) { _ in
            drafts = []
            status = nil
        }
        .onDisappear {
            drafts = []
            status = nil
            error = nil
        }
        .confirmationDialog(
            "Erase all encrypted drafts on this device?",
            isPresented: $confirmErase, titleVisibility: .visible
        ) {
            Button("Erase all drafts", role: .destructive) { eraseAll() }
        } message: {
            Text("This cannot be undone. GitHub repositories and commits will not be changed.")
        }
    }

    @MainActor
    private func reload() {
        drafts = []
        error = nil
        guard authorized, let login = account.authenticatedAs else { return }
        do { drafts = try StagedDraftVault.load(for: login) }
        catch { error = error.localizedDescription }
    }

    @MainActor
    private func remove(_ draft: StagedFileEdit) {
        guard authorized, let login = account.authenticatedAs else { return }
        do {
            let next = drafts.filter { $0.id != draft.id }
            try StagedDraftVault.save(for: login, edits: next)
            drafts = next
            status = "Local draft deleted; GitHub was not changed."
        } catch { error = error.localizedDescription }
    }

    @MainActor
    private func eraseAll() {
        guard authorized else { return }
        do {
            try StagedDraftVault.erase()
            drafts = []
            status = "All encrypted local drafts were erased."
        } catch { error = error.localizedDescription }
    }
}
