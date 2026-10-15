import SwiftUI
import GitPilotCore

/// Non-production integration harness: compiles the existing RC3 Aurora theme
/// against the migrated Foundation-only core on the real iPhone Simulator SDK.
struct GitPilotCoreSmokeView: View {
    private let trustedOrigin = GitHubURLPolicy.trustedAPI(
        URL(string: "https://api.github.com/repos/octocat/Hello-World")!
    )
    private let blockedOrigin = !GitHubURLPolicy.trustedAPI(
        URL(string: "https://api.github.com.evil.test/user")!
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GP.spacing) {
                    GPHeader(
                        eyebrow: "iOS FOUNDATION",
                        title: "GitPilot",
                        subtitle: "RC3 migration smoke host — not the production GitPilot app."
                    )
                    HStack {
                        StatusPill(text: "Simulator only", color: GP.amber)
                        StatusPill(text: "No credentials", color: GP.green)
                    }
                    Surface {
                        GPSectionTitle(title: "Security checks", detail: "Local only")
                        Label("Trusted GitHub origin", systemImage:
                            trustedOrigin ? "checkmark.shield.fill" : "xmark.shield.fill")
                        Label("Lookalike host rejected", systemImage:
                            blockedOrigin ? "checkmark.shield.fill" : "xmark.shield.fill")
                        Label("No OAuth tokens or writes", systemImage: "lock.shield.fill")
                    }
                    .foregroundStyle(.white)
                    GPEmptyState(
                        icon: "hammer.fill",
                        title: "Full GitPilot UI not yet migrated",
                        detail: "Remaining: RC3 feature screens, network models, Keychain, OAuth gateway and native device QA."
                    )
                }
                .padding(24)
            }
            .gpScreen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
