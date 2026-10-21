import SwiftUI
import GitPilotCore

/// The real OAuth entry point: Apple's system authentication sheet, not a
/// password WebView or an in-app PAT prompt. CI builds may browse publicly.
struct AccountCenterScreen: View {
    @ObservedObject var store: PublicWorkspaceStore
    @EnvironmentObject private var account: OAuthAccountSession
    @State private var publicLogin = ""
    @FocusState private var profileFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                GPWelcomeCard(
                    eyebrow: "YOUR WORKSPACE",
                    title: account.authenticatedAs.map { "Hello, @\($0)." } ?? "Your GitHub, in bloom.",
                    subtitle: account.authenticatedAs == nil
                        ? "Connect securely to browse your repositories, code, reviews and workflows."
                        : "Your account is verified. Private data stays in memory and credentials stay in Keychain.",
                    icon: account.authenticatedAs == nil ? "sparkles.rectangle.stack" : "checkmark.shield.fill"
                )

                GPSectionTitle(title: "Connection", detail: "GitHub App OAuth")
                Surface {
                    HStack(spacing: 12) {
                        GPIndicator(icon: account.authenticatedAs == nil ? "lock.shield" : "checkmark.shield.fill",
                                    tint: account.authenticatedAs == nil ? GP.amber : GP.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(account.authenticatedAs.map { "@\($0)" } ?? "Not connected")
                                .font(.headline)
                                .foregroundStyle(GP.ink)
                            MetaText(text: account.authenticatedAs == nil
                                ? "Public browsing is available without sign-in."
                                : "Connected with verified GitHub App session")
                        }
                        Spacer(minLength: 0)
                        StatusPill(text: account.authenticatedAs == nil ? "Guest" : "Secure",
                                   color: account.authenticatedAs == nil ? GP.amber : GP.green)
                    }

                    if account.busy {
                        ProgressView("Checking GitHub session…")
                            .tint(GP.accent)
                            .foregroundStyle(GP.secondary)
                    } else if account.authenticatedAs == nil {
                        if account.isConfigured {
                            Button {
                                account.signIn()
                            } label: {
                                Label("Continue with GitHub", systemImage: "arrow.up.right.shield.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityHint("Opens the secure system browser for GitHub App authorization")
                        } else {
                            Label("GitHub sign-in is not configured for this build.",
                                  systemImage: "info.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(GP.amber)
                            Text("A publisher must provide the GitHub App client ID, owned HTTPS callback and OAuth gateway. No credentials are requested in the app.")
                                .font(.footnote)
                                .foregroundStyle(GP.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        NavigationLink {
                            AuthenticatedRepositoriesScreen()
                        } label: {
                            Label("Open private workspace", systemImage: "folder.badge.person.crop")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(role: .destructive) {
                            account.signOut()
                        } label: {
                            Label("Disconnect and erase local drafts", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(account.busy)
                    }

                    if let error = account.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(GP.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if account.isConfigured && account.authenticatedAs == nil && !account.busy {
                            Button("Try GitHub sign-in again") { account.signIn() }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                GPSectionTitle(title: "Public explorer", detail: "No account needed")
                Surface {
                    Text("Browse a public GitHub profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GP.ink)
                    TextField("GitHub username", text: $publicLogin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.go)
                        .focused($profileFocused)
                        .padding(12)
                        .background(GP.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GP.border))
                        .onSubmit { selectPublic() }
                    Button {
                        selectPublic()
                    } label: {
                        Label("Explore public projects", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!PublicGitHubAPI.validUsername(publicLogin.trimmingCharacters(in: .whitespacesAndNewlines)))
                    MetaText(text: "Current public profile: @\(store.username)")
                }

                GPSectionTitle(title: "How sign-in works", detail: "Privacy first")
                HStack(spacing: 12) {
                    feature("System browser", "safari.fill", GP.lavender)
                    feature("Keychain", "lock.shield.fill", GP.mint)
                    feature("No client secret", "checkmark.seal.fill", GP.peach)
                }

                Surface {
                    Eyebrow(text: "RELEASE READINESS")
                    Text("Read-only GitHub integration")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GP.ink)
                    Text("Private files, PR reviews and workflow status are available after OAuth authorization. Posting, merging, dispatch and commits are intentionally disabled until live device and permission tests pass.")
                        .font(.footnote)
                        .foregroundStyle(GP.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .gpScreen()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { publicLogin = store.username }
    }

    private func feature(_ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(GP.ink)
                .frame(width: 44, height: 44)
                .background(tint, in: RoundedRectangle(cornerRadius: 14))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GP.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 5)
        .background(GP.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(GP.border))
    }

    private func selectPublic() {
        let trimmed = publicLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PublicGitHubAPI.validUsername(trimmed) else { return }
        profileFocused = false
        store.selectProfile(trimmed)
    }
}
