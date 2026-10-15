import Foundation
import SwiftUI
import GitPilotCore

/// Native RC3 OAuth session coordinator. Authenticated access is restricted to
/// verified /user. Private browsing and ALL remote mutations remain disabled.
@MainActor
final class OAuthAccountSession: ObservableObject {
    @Published private(set) var authenticatedAs: String?
    @Published private(set) var busy = false
    @Published var errorMessage: String?

    private var epoch = 0
    private var didAttemptRestore = false
    private var operation: Task<Void, Never>?

    var isConfigured: Bool {
        if #available(iOS 17.4, *) { return OAuthLogin.shared.isConfigured }
        return false
    }

    func restoreOnce() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        let current = epoch
        operation?.cancel()
        busy = true
        operation = Task {
            do {
                guard let credentials = try OAuthTokenStore.read() else {
                    if current == epoch { busy = false }
                    return
                }
                let active: OAuthCredentials
                if credentials.needsRefresh {
                    guard credentials.canRefresh else {
                        try OAuthTokenStore.remove()
                        if current == epoch { errorMessage = "Stored authorization expired. Sign in again." }
                        if current == epoch { busy = false }
                        return
                    }
                    active = try await OAuthLogin.shared.refresh(credentials)
                } else {
                    active = credentials
                }
                let login = try await GitHubAuthenticatedViewer()
                    .verifiedLogin(token: active.accessToken)
                guard current == epoch && !Task.isCancelled else { return }
                if active != credentials { try OAuthTokenStore.save(active) }
                authenticatedAs = login
                busy = false
            } catch is CancellationError {
                return
            } catch {
                guard current == epoch else { return }
                // Permanent 401 explicitly invalidates persisted credentials;
                // transient gateway outages preserve recoverable tokens.
                if let issue = error as? GitHubAuthenticatedViewer.ViewerError, issue == .revoked {
                    try? OAuthTokenStore.remove()
                }
                if let issue = error as? GitHubOAuthGatewayError, issue == .accessRevoked {
                    try? OAuthTokenStore.remove()
                }
                errorMessage = error.localizedDescription
                busy = false
            }
        }
    }

    func signIn() {
        OAuthLogin.shared.cancelSignIn()
        guard isConfigured else {
            errorMessage = "GitHub App OAuth is not configured for this iOS build."
            return
        }
        epoch += 1
        let requestEpoch = epoch
        operation?.cancel()
        busy = true
        errorMessage = nil
        operation = Task {
            do {
                let credentials = try await OAuthLogin.shared.signIn()
                let login = try await GitHubAuthenticatedViewer()
                    .verifiedLogin(token: credentials.accessToken)
                guard requestEpoch == epoch && !Task.isCancelled else { return }
                // A different account must never access an older account's draft key.
                if authenticatedAs?.lowercased() != login.lowercased() {
                    try StagedDraftVault.erase()
                }
                try OAuthTokenStore.save(credentials)
                authenticatedAs = login
                busy = false
            } catch is CancellationError {
                return
            } catch {
                guard requestEpoch == epoch else { return }
                errorMessage = error.localizedDescription
                busy = false
            }
        }
    }

    func signOut() {
        OAuthLogin.shared.cancelSignIn()
        operation?.cancel()
        do {
            // Do not report signed out if iOS refused to remove the Keychain item.
            try OAuthTokenStore.remove()
        } catch {
            errorMessage = "Secure GitHub credentials could not be cleared."
            return
        }
        epoch += 1
        operation = nil
        authenticatedAs = nil
        busy = false
        errorMessage = nil
        do {
            try StagedDraftVault.erase()
        } catch {
            errorMessage = "Signed out, but encrypted local drafts could not be cleared."
        }
    }
}
