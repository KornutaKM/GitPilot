# GitPilot iOS — RC3 migration (in progress)

The GitHub Android 1.3-alpha implementation and the independently developed iOS/Android 1.0 RC3 source archive are distinct code lines. This directory begins a controlled, **incremental migration of the existing iOS RC3 code**; it is not a new iOS product and is not a finished app.

## Verified first migration slice

`GitPilotCore` is a standalone Swift Package with the RC3's Foundation-only logic for:
- OAuth callback exact-origin/state validation, token session expiry and redacted diagnostic descriptions;
- trusted GitHub API origins, authorization-free external redirects, constrained pagination continuation;
- unified pull-request diffs and LEFT/RIGHT review line indexing;
- bounded staged diff previews with safeguards against oversized input/output.
- RC3 staged-draft envelopes: account isolation, 12-file/1-MB aggregate limits, per-file limits and redaction of uncommitted source in diagnostics.

The logic is intentionally headless and has no GitHub network or account access in CI. The package includes 16 XCTest regressions. Build and run locally on macOS or Linux:

```bash
swift build --package-path ios/GitPilotCore --configuration release
swift test --package-path ios/GitPilotCore --parallel
```

The dedicated [iOS Core CI](../.github/workflows/ios-core.yml) runs both commands on `ubuntu-latest` and `macos-15` for each PR that changes this package.

## Native simulator integration smoke host

`ios/App` is a temporary **non-production** SwiftUI smoke host that links the migrated Swift Package and **the original RC3 Aurora design system** (`DesignSystem.swift`). Its Xcode project is generated from `ios/App/project.yml` with XcodeGen rather than committing build-system generated files. It has no OAuth integration, authenticated account access, GitHub writes, or secrets; it **does** read public GitHub REST data and includes an explicit privacy manifest.

The dedicated [iOS Simulator Smoke CI](../.github/workflows/ios-simulator.yml) selects Xcode 26, generates an Xcode project, compiles an unsigned app for the generic iPhone Simulator destination, and uploads an **unsigned simulator-only artifact** for further review. This is not the archived RC3 application; a green simulator smoke build establishes native compiler/linker integration for the portable core only.

To reproduce on macOS with Xcode 26 and XcodeGen:

```bash
xcodegen generate --spec ios/App/project.yml
xcodebuild build -project ios/App/GitPilotCoreSmoke.xcodeproj -scheme GitPilotCoreSmoke \
  -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```


## Functional iOS public workspace (next RC3 migration slice)

The simulator app now contains RC3-style **Today, Reviews, Actions and Repos** tabs using the existing Aurora SwiftUI components. Public GitHub data comes from a new typed, read-only REST client in `GitPilotCore` rather than static sample JSON. It can switch public profiles, display recent repositories, show open PRs and workflow outcomes from at most four monitored repositories, navigate to safe GitHub web URLs, and paginate repository discovery up to three pages of 12.

This is deliberately **public browsing only**: no client secret, PAT, OAuth flow, private repository access, PR reviews, merges, workflow dispatch, cancellation or remote file writes. The account and any cached results stay in memory, not persistent profile storage. Each refresh invalidates results from the previous profile. Partial responses, rate limits and truncated monitoring are shown as such; zero failures in the sampled repositories does not mean all CI is green.

PublicGitHubAPI is tested with deterministic transport stubs (10 additional XCTest cases) covering network contract, API origin, size limits, rate limits, decoding, URL injection, paging and incomplete results. The full suite contains 26 XCTest cases.

## Migrated Keychain, encrypted drafts and opt-in OAuth (PR #12)

- `OAuthTokenStore.swift` retains the RC3 OAuth credentials in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, atomically upserts rotated credentials and verifies deletion on sign-out.
- `StagedDraftVault.swift` encrypts versioned per-account drafts with AES-256-GCM and a device-only Keychain key; ciphertext is stored using complete file protection in an Application Support directory excluded from backups. **The vault is not yet wired to a remote multi-file commit editor**, so no code write capability is implied.
- `OAuthLogin.swift` uses ASWebAuthenticationSession, PKCE-S256, a cryptographically random verifier/state, HTTPS callback/state validation, an operator-provisioned OAuth gateway and ephemeral no-redirect token exchange. The GitHub App client secret belongs **only** on the gateway; it never enters the iOS build.
- After OAuth completion, the native session coordinator checks the access token with `GET https://api.github.com/user` before persisting the verified account. Session-epoch guards prevent stale network responses from restoring a signed-out account. On sign-out, Keychain credentials are deleted and the local draft encryption key is destroyed.
- OAuth is deliberately **disabled in ordinary CI/simulator builds** because they do not ship operator-owned values for `GitPilotOAuthClientID`, `GitPilotOAuthBackendURL` or `GitPilotOAuthCallbackURL` in the generated Info.plist. For operator builds, pass `GITPILOT_OAUTH_CLIENT_ID`, `GITPILOT_OAUTH_BACKEND_URL` and `GITPILOT_OAUTH_CALLBACK_URL` through Xcode build settings after registering the GitHub App and owned HTTPS Universal Link callback. iOS **17.4+** is required for the secure system HTTPS callback. Configure/verify the associated domain on a signed device build before claiming login works. Never pass a `client_secret`.
- Signing in is strictly a **read-only verified-account preview** at this stage: the public repository loader stays token-free. OAuth identity verification does not unlock private repositories, reviews, PR merges, Actions mutations or file writes.
- SwiftPM includes mock transport tests for gateway origins, authorization and refresh payloads, hostile redirects, revocation and GitHub viewer verification. The iOS Simulator workflow also runs native XCTest against the actual Keychain and AES-GCM vault with test-only tokens. This is not physical-device or live-gateway acceptance testing.

## Verified-account repository browsing (PR #14)

Authenticated mode adds a **strictly read-only** `GET /user/repos` client and a protected SwiftUI repository list, accessible only after the OAuth session has verified `/user`. The client sends the bearer only to the exact GitHub API HTTPS endpoint, refuses redirects, parses bounded typed JSON (1.5 MB) and permits up to three pages of 20 repositories. Private or collaborator-owned repositories may appear depending on actual GitHub App access; the UI never implies the app has broader permissions.

Protected results exist **in process memory only**; every account change, sign-out or token rotation invalidates the view's generation and discards stale responses. Only the session coordinator may read Keychain or refresh a credential. The public four-tab workspace continues to use its anonymous API client with no Authorization header. Eight deterministic mock-transport tests cover token injection, host redirects, permissions, malformed payloads and request limits.

Remote file editing, posting PR reviews, merges, workflow dispatch and repository mutations remain **disabled**. Private file content is not downloaded by this new list and no application secrets, client secrets or production signing keys are committed.

## Remaining migration and release gates

**Not yet migrated into this GitHub repository:** the full authenticated RC3 SwiftUI flows, the full write-capable network stack, production Xcode project, app assets, Keychain-backed authenticated workspace and staged draft editing integration, configured/validated Cloudflare OAuth gateway deployment, signed Universal Link support, and remote mutation feature screens. The simulator smoke host is not a replacement for these. The pre-existing RC3 archive includes those sources; it has not passed a native Xcode build and must be integrated and verified before TestFlight. Mac Swift Package tests are a foundation check, **not** an iOS simulator build or an iPhone QA pass.

After source integration, run `xcodebuild build` on macOS with iOS 26 SDK against a signing-disabled simulator destination, add on-simulator tests, verify the privacy manifest and entitlements, then complete the actual publisher signing/TestFlight evidence. Do not put OAuth client secrets, signing certificates or tokens into source control.

The corresponding Android milestones are tracked in draft PRs #1, #3, #5–#9. PR #9 passed Android CI and Android Emulator Smoke on commit `f76ea8d11bb76a2d8da42c17609e625c4a0f297c`; this does not imply any iOS app build succeeded.
