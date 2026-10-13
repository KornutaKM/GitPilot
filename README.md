# GitPilot for Android

A native, focused GitHub control center for Android. **Alpha 0.1** includes a functional Compose interface with demo data; it is **not connected to a GitHub account yet**.

## Screens

- **Overview**: work needing attention, repository snapshot, failed CI and reviews.
- **Repositories**: searchable repository list, branch selector, commit history, commit detail.
- **Pull requests**: review queue, PR detail, checks and sample diff.
- **Actions**: workflow runs, failed step breakdown and sample log output.

All demo content is intentionally labelled. There is no token collection, no backend and no real destructive or write actions in this release. Review/merge/re-run actions are *not* exposed until authentication and permission handling exist.

## Run

1. Open this repository in recent **Android Studio**, with **JDK 17** and Android SDK Platform **36** installed.
2. Let Gradle sync, then run the `app` configuration on an Android emulator/device with Android 8.0 (API 26) or newer.
3. For command-line builds, install **Gradle 8.13** and run `gradle :app:assembleDebug` or `gradle testDebugUnitTest`. The official wrapper JAR and launchers have not been included in this starter archive; generate them with `gradle wrapper --gradle-version 8.13` before contributing.
4. Find the debug APK at `app/build/outputs/apk/debug/app-debug.apk`.

The project uses AGP 8.11.1, Kotlin 2.2.20, Gradle 8.13 and Jetpack Compose (BOM 2025.12.00).

## Proposed architecture / next milestones

- `data/`: immutable domain models, a `WorkspaceRepository` abstraction and a demo data source.
- `ui/`: composable navigation and screen components; `GitPilotViewModel` exposes repository data.
- **Next**: GitHub App sign-in through a confidential backend OAuth code exchange with PKCE. Never ship a GitHub client secret inside an APK; encrypt local access-token storage and request minimum required permissions. Respect branch protection, role checks, token expiry, API pagination and rate limits.
- **Then**: integrate read-only REST APIs (repos, commits, branches, PRs, workflow runs), and separately implement reviews, merge, branch creation and rerun with confirmation and error handling.
- **Later**: local caching, push notifications and account switching.

## Product principles

Fast orientation, low cognitive load, one-handed use, honest status indicators, no imitation of successful remote actions, and a deliberate distinction between read-only preview and authorized mutations.

## Licensing

No license has been selected yet.

> **Starter packaging note:** Gradle wrapper properties are present, but the binary wrapper JAR and launch scripts need to be generated once with Gradle 8.13. No APK has been built or verified in this environment.
