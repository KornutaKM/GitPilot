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

## Protected repository source (PR #15)

After a verified GitHub App sign-in, the protected repository list can open **private directories and small text files** using a separate authenticated, read-only GET client. The client validates repository/branch/path, sends the bearer exclusively to `https://api.github.com/repos/<owner>/<repo>/contents/...`, forbids redirects, caps a directory at 100 entries and accepts only UTF-8 text previews of at most 64 KB. Symlink/submodule entries are not followed; binary files, path traversal, malformed Base64 and oversized responses fail closed. Private source is held in memory only and cleared when navigation ends or OAuth identity/revision changes.

The protected source feature includes nine offline Swift mock-transport regression tests. Public browsing remains unauthenticated. **No edits, commits, PR comments, merges or workflow dispatches are enabled.** Real OAuth/gateway and private repository permissions still need verification on a signed iPhone before release.

## Verified Reviews and Actions (PR #16)

The iOS Aurora app now exposes **read-only Reviews and Actions for verified GitHub accounts**. From either public tab, users can open the protected repository picker, select an authorized repo, and browse private-source files, open pull requests (up to 3 × 20), diff patches (first 30 files, max 80 KB per patch), conversation and inline review comments (first 20 of each type), workflow runs (up to 3 × 20), and the first 50 jobs of a run. All counts are explicitly labelled as bounded samples rather than complete repository coverage.

All authenticated requests are named GET endpoints on exactly `https://api.github.com` with ephemeral no-redirect sessions. The bearer token comes exclusively from the Keychain-backed session coordinator. Protected result pages, private code patches, comments and job metadata remain in RAM, are cleared on navigation/logout, and are rejected if the account or authorization revision changes while the request is in flight. Failure of any required detail request shows an error rather than pretending the whole PR was loaded.

Twelve deterministic XCTest transport regressions cover token injection, host redirection, pagination bounds, request methods, invalid IDs, large/broken responses, and distinct GitHub errors. The existing native Keychain/AES-GCM simulator tests remain release gates. **This milestone does not permit reviews, comments, merges, reruns, dispatches, file edits or commits**; live OAuth permissions and physical device QA are still pending.

## Aurora Pastel UI + complete opt-in GitHub App sign-in journey (PR #17)

The native iOS workspace and Android Material 3 app share a bright **lavender / mint / peach / blush** design vocabulary, with accessible dark-ink typography. iOS adds a five-tab navigation layout (**Today, Reviews, Actions, Repos, Account**), a pastel hero, visible verified/guest connection status, secure sign-in affordances, custom semantic surfaces and comprehensive error/empty states. This is real SwiftUI layout code, not a static mockup or an image.

The **Account** screen provides:
- native `Continue with GitHub` via `ASWebAuthenticationSession` (iOS 17.4+) and PKCE S256;
- a previously migrated server-owned Cloudflare OAuth gateway for code exchange and token rotation;
- verified `GET /user` identity, device-only Keychain persistence, restoration, reconnect and sign-out;
- authenticated, memory-only repository → source / PRs / discussion / Actions flows;
- a separate anonymous public profile explorer, which **never** receives the bearer token.

The new `OAuthAuthorizationPolicy` rejects malformed callback origins, state/challenge values and embedded secrets before opening the browser; four offline XCTest cases guard this contract. Three additional native XCTest checks enforce readable contrast on the actual iOS SDK. Android's existing OAuth Device Flow and API features are retained while its Material 3 palette is aligned with iOS.

### Required one-time operator configuration before login is live

GitHub App OAuth **cannot succeed in an ordinary unsigned/simulator CI build**, because the repo does not store deployment secrets, GitHub App registration or signing profiles. To enable login on a signed real device:
1. Register a GitHub App with expiring user tokens and the exact HTTPS callback `https://YOUR_OWN_DOMAIN/oauth/callback`. Grant only the read permissions the tested endpoints need.
2. Deploy the Worker in `backend/` behind your owned HTTPS domain. Provision `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_CALLBACK_URI`, the rate-limiter and valid Apple App Site Association outside Git history. Validate the deployed health, callback and AASA responses.
3. Set build values `GITPILOT_OAUTH_CLIENT_ID`, `GITPILOT_OAUTH_BACKEND_URL`, `GITPILOT_OAUTH_CALLBACK_URL` and `GITPILOT_OAUTH_ASSOCIATED_DOMAIN` (the hostname only, no scheme). Use a valid Apple Development Team, matching bundle ID/provisioning profile and `ios/App/Config/ProductionOAuth.entitlements` instead of the simulator-only entitlements. **Never pass the GitHub App client secret** to Xcode.
4. On a signed iPhone, verify Universal Link handoff to `ASWebAuthenticationSession`, fresh sign-in, token refresh, process restart, account switch, offline mode, 401 revocation, Keychain and logout. These remain outstanding physical QA gates.

```bash
xcodegen generate --spec ios/App/project.yml
# An operator's signed device build (insert values using secure local CI variables).
xcodebuild build -project ios/App/GitPilotCoreSmoke.xcodeproj -scheme GitPilotCoreSmoke \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_ENTITLEMENTS=Config/ProductionOAuth.entitlements \
  GITPILOT_OAUTH_CLIENT_ID="$GITPILOT_OAUTH_CLIENT_ID" \
  GITPILOT_OAUTH_BACKEND_URL="$GITPILOT_OAUTH_BACKEND_URL" \
  GITPILOT_OAUTH_CALLBACK_URL="$GITPILOT_OAUTH_CALLBACK_URL" \
  GITPILOT_OAUTH_ASSOCIATED_DOMAIN="$GITPILOT_OAUTH_ASSOCIATED_DOMAIN"
```

This is a **fully wired conditional sign-in experience**, not a claim that GitHub credentials, a production host or physical-device authorization have already been provisioned. Remote mutations (PR reviews, merges, commits and workflow dispatch) remain disabled until live signing and permission tests succeed.

## Remaining migration and release gates

**Not yet migrated into this GitHub repository:** the full authenticated RC3 SwiftUI flows, the full write-capable network stack, production Xcode project, app assets, Keychain-backed authenticated workspace and staged draft editing integration, configured/validated Cloudflare OAuth gateway deployment, signed Universal Link support, and remote mutation feature screens. The simulator smoke host is not a replacement for these. The pre-existing RC3 archive includes those sources; it has not passed a native Xcode build and must be integrated and verified before TestFlight. Mac Swift Package tests are a foundation check, **not** an iOS simulator build or an iPhone QA pass.

After source integration, run `xcodebuild build` on macOS with iOS 26 SDK against a signing-disabled simulator destination, add on-simulator tests, verify the privacy manifest and entitlements, then complete the actual publisher signing/TestFlight evidence. Do not put OAuth client secrets, signing certificates or tokens into source control.

The corresponding Android milestones are tracked in draft PRs #1, #3, #5–#9. PR #9 passed Android CI and Android Emulator Smoke on commit `f76ea8d11bb76a2d8da42c17609e625c4a0f297c`; this does not imply any iOS app build succeeded.
