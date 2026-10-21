import SwiftUI
import GitPilotCore

/// Native single-file editing is saved ONLY to the device-only AES-GCM vault.
/// There is deliberately no GitHub PUT/PATCH/POST path in this UI.
struct EncryptedDraftEditor: View {
    let repository: PublicRepository
    let branch: String
    let preview: PublicFilePreview

    @EnvironmentObject private var account: OAuthAccountSession
    @State private var text: String
    @State private var openedAs: String?
    @State private var openedRevision: Int?
    @State private var message: String?
    @State private var errorMessage: String?

    init(repository: PublicRepository, branch: String, preview: PublicFilePreview) {
        self.repository = repository
        self.branch = branch
        self.preview = preview
        _text = State(initialValue: preview.text)
    }

    private var stillAuthorized: Bool {
        guard let openedAs, let openedRevision else { return false }
        return openedRevision == account.authRevision &&
            openedAs.lowercased() == account.authenticatedAs?.lowercased() &&
            !account.busy
    }

    private var diff: [StagedDiffPreview.Line] {
        StagedDiffPreview.lines(from: preview.text, to: text, maxLines: 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GPHeader(eyebrow: "ENCRYPTED LOCAL DRAFT",
                         title: "Make it yours.",
                         subtitle: "\(repository.fullName) / \(preview.path)")
                if !stillAuthorized {
                    GPEmptyState(icon: "lock.shield.fill",
                                 title: "Editor locked",
                                 detail: "Reopen the file with the current GitHub session.")
                } else {
                    Surface {
                        HStack {
                            GPIndicator(icon: "square.and.pencil", tint: GP.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Private, device-only")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(GP.ink)
                                MetaText(text: "AES-256-GCM · Keychain · no network upload")
                            }
                            Spacer(minLength: 0)
                            StatusPill(text: "Draft", color: GP.accent)
                        }
                        Text("Your edit is staged locally, not committed to GitHub.")
                            .font(.caption)
                            .foregroundStyle(GP.secondary)
                    }

                    GPSectionTitle(title: "Edit text", detail: "200 KB maximum")
                    TextEditor(text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(GP.ink)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(minHeight: 250)
                        .background(GP.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(GP.border, lineWidth: 1))
                        .accessibilityLabel("Local staged file content")

                    HStack {
                        MetaText(text: "Original: \(preview.text.utf8.count) bytes")
                        Spacer()
                        MetaText(text: "Edited: \(text.utf8.count) bytes")
                    }
                    GPSectionTitle(title: "Change preview", detail: "First 60 lines")
                    Surface {
                        if preview.text == text {
                            MetaText(text: "No changes yet. Update the text to stage a draft.")
                        } else {
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(diff) { line in
                                        Text(line.prefix + " " + line.text)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(diffColor(line.kind))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let message {
                        Label(message, systemImage: "checkmark.shield.fill")
                            .font(.subheadline)
                            .foregroundStyle(GP.green)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(GP.red)
                    }
                    Button {
                        stage()
                    } label: {
                        Label("Save encrypted draft", systemImage: "lock.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(text == preview.text || text.utf8.count > 200_000)

                    Button(role: .destructive) {
                        discardDraft()
                    } label: {
                        Label("Remove this local draft", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    MetaText(text: "Remote commits are not enabled. GitPilot never silently uploads edited source.")
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Staged edit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if openedAs == nil {
                openedAs = account.authenticatedAs
                openedRevision = account.authRevision
                restoreDraft()
            }
        }
        .onChange(of: account.authRevision) { _ in
            if !stillAuthorized {
                text = ""
                message = nil
                errorMessage = nil
            }
        }
        .onDisappear {
            // Do not retain uncommitted plaintext in a hidden editor state.
            text = ""
        }
    }

    private func diffColor(_ kind: StagedDiffPreview.Kind) -> Color {
        switch kind {
        case .added: return GP.green
        case .removed: return GP.red
        case .unchanged: return GP.secondary
        case .warning: return GP.amber
        }
    }

    @MainActor
    private func restoreDraft() {
        guard stillAuthorized, let login = account.authenticatedAs,
              let sourceSHA = preview.sha,
              let id = Int(exactly: repository.id) else { return }
        do {
            let drafts = try StagedDraftVault.load(for: login)
            if let existing = drafts.first(where: {
                $0.repositoryID == id && $0.path == preview.path && $0.branch == branch
            }) {
                if existing.originalBlobSHA == sourceSHA &&
                   existing.originalContent == preview.text {
                    text = existing.newContent
                    message = "Restored an encrypted draft saved earlier on this device."
                } else {
                    errorMessage = "A saved draft refers to a different Git blob. Review current source before replacing it."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func stage() {
        guard stillAuthorized, let login = account.authenticatedAs,
              let sha = preview.sha else { return }
        message = nil
        errorMessage = nil
        do {
            let edit = try AuthenticatedStagingPolicy.stage(
                repository: repository, branch: branch, path: preview.path,
                originalBlobSHA: sha, original: preview.text, revised: text)
            var drafts = try StagedDraftVault.load(for: login)
            drafts.removeAll { $0.id == edit.id }
            drafts.append(edit)
            try StagedDraftVault.save(for: login, edits: drafts)
            message = "Encrypted draft saved on this device (\(drafts.count)/12 files)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func discardDraft() {
        guard stillAuthorized, let login = account.authenticatedAs else { return }
        message = nil
        errorMessage = nil
        do {
            var drafts = try StagedDraftVault.load(for: login)
            let before = drafts.count
            guard let id = Int(exactly: repository.id) else { return }
            drafts.removeAll {
                $0.repositoryID == id && $0.path == preview.path && $0.branch == branch
            }
            if drafts.count != before {
                try StagedDraftVault.save(for: login, edits: drafts)
            }
            message = "Local staged change cleared. Nothing was sent to GitHub."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
