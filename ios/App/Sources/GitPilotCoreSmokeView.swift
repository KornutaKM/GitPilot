import SwiftUI
import GitPilotCore

/// Verifies that iOS Simulator can launch a native SwiftUI app which links
/// the ported RC3 Foundation security library without a token or a backend.
struct GitPilotCoreSmokeView: View {
    private let background = Color(red: 11 / 255, green: 14 / 255, blue: 22 / 255)
    private let surface = Color(red: 21 / 255, green: 27 / 255, blue: 40 / 255)
    private let accent = Color(red: 176 / 255, green: 161 / 255, blue: 255 / 255)
    private let trustedOrigin = GitHubURLPolicy.trustedAPI(
        URL(string: "https://api.github.com/repos/octocat/Hello-World")!
    )
    private let blockedOrigin = !GitHubURLPolicy.trustedAPI(
        URL(string: "https://api.github.com.evil.test/user")!
    )

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("GitPilot")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("iOS RC3 migration smoke host")
                            .font(.title3)
                            .foregroundStyle(accent)
                        Text("Native simulator build and Swift Package linkage only. This is not the production GitPilot app.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.76))
                        VStack(alignment: .leading, spacing: 12) {
                            Label("GitHub API origin checked", systemImage: trustedOrigin ? "checkmark.shield.fill" : "xmark.shield.fill")
                            Label("Lookalike host rejected", systemImage: blockedOrigin ? "checkmark.shield.fill" : "xmark.shield.fill")
                            Label("No OAuth tokens or writes", systemImage: "lock.shield.fill")
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(surface, in: RoundedRectangle(cornerRadius: 20))
                        Text("Remaining: migrate full RC3 screens, networking, Keychain, OAuth gateway, and device QA.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
