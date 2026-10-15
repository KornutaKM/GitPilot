# GitPilot iOS — RC3 migration (in progress)

The GitHub Android 1.3-alpha implementation and the independently developed iOS/Android 1.0 RC3 source archive are distinct code lines. This directory begins a controlled, **incremental migration of the existing iOS RC3 code**; it is not a new iOS product and is not a finished app.

## Verified first migration slice

`GitPilotCore` is a standalone Swift Package with the RC3's Foundation-only logic for:
- OAuth callback exact-origin/state validation, token session expiry and redacted diagnostic descriptions;
- trusted GitHub API origins, authorization-free external redirects, constrained pagination continuation;
- unified pull-request diffs and LEFT/RIGHT review line indexing;
- bounded staged diff previews with safeguards against oversized input/output.

The logic is intentionally headless and has no GitHub network or account access in CI. The package includes 11 XCTest regressions. Build and run locally on macOS or Linux:

```bash
swift build --package-path ios/GitPilotCore --configuration release
swift test --package-path ios/GitPilotCore --parallel
```

The dedicated [iOS Core CI](../.github/workflows/ios-core.yml) runs both commands on `ubuntu-latest` and `macos-15` for each PR that changes this package.

## Remaining migration and release gates

**Not yet migrated into this GitHub repository:** the RC3 SwiftUI app, its full Core models/network stack, iOS Xcode project, assets, Keychain and OAuth flow, Cloudflare OAuth gateway, and platform-specific UI. The pre-existing RC3 archive includes those sources; it has not passed a native Xcode build and must be integrated and verified before TestFlight. Mac Swift Package tests are a foundation check, **not** an iOS simulator build or an iPhone QA pass.

After source integration, run `xcodebuild build` on macOS with iOS 26 SDK against a signing-disabled simulator destination, add on-simulator tests, verify the privacy manifest and entitlements, then complete the actual publisher signing/TestFlight evidence. Do not put OAuth client secrets, signing certificates or tokens into source control.

The corresponding Android milestones are tracked in draft PRs #1, #3, #5–#9. PR #9 passed Android CI and Android Emulator Smoke on commit `f76ea8d11bb76a2d8da42c17609e625c4a0f297c`; this does not imply any iOS app build succeeded.
