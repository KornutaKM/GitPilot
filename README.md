# GitPilot for Android

Native GitHub control center built with Kotlin, Jetpack Compose and Material 3.

## Version 0.2.0-alpha

Live public repository browsing now works without a GitHub login. GitHub App Device Flow sign-in and remote operations (reviews, squash merge and retry failed workflow jobs) are implemented; signed-in features require a GitHub App Client ID and installation permissions.

- Overview: pinned and recent repositories, pull requests and GitHub Actions from live GitHub REST endpoints.
- Repositories: default-branch and selected-branch history, actual commit patches and confirmed creation of a remote branch from a chosen commit.
- PRs: real changed-file patches loaded on demand, optional review/comment and merge confirmation.
- Actions: real workflow runs and on-demand job lists, full-log links, rerun failed jobs with confirmation.
- Account: choose public GitHub username, connect/disconnect GitHub App user authorization.
- Native light/dark theme, manual refresh and visible API errors.

## Run

1. Open the repository in Android Studio with JDK 17 and Android SDK Platform 36.
2. Build with the verified Gradle 8.13 wrapper: ./gradlew :app:assembleDebug or ./gradlew testDebugUnitTest (Windows: gradlew.bat).
3. Run on Android 8.0 (API 26) or newer.
4. Download the debug APK from GitHub Actions -> Android CI -> Artifacts -> GitPilot-debug.

Gradle Wrapper launchers and JAR are included, sourced from the official Gradle v8.13.0 tag. No manually installed Gradle version is required.

## GitHub App authorization (optional)

GitPilot uses GitHub App OAuth Device Flow. This protocol uses a public client ID rather than a client secret in the Android app.

1. Register a GitHub App in GitHub Developer Settings. Enable Device Flow in its app settings.
2. Select the minimum required repository permissions: Metadata read, Contents read/write to create branches, Pull requests read/write if review and merge are desired, and Actions read/write for reruns.
3. Install the GitHub App on the selected repositories.
4. Set the public client ID as Gradle property gitpilot.githubClientId=YOUR_CLIENT_ID in your user-level Gradle properties, or pass -Pgitpilot.githubClientId=YOUR_CLIENT_ID when building.
5. For APKs made by GitHub Actions, set repository Actions variable GITPILOT_GITHUB_CLIENT_ID.
6. On the phone, open Account -> Connect GitHub. Follow the browser device code prompt.

Access tokens are encrypted in local storage via Android Keystore AES-GCM; Android backups are disabled. No client secret or token is embedded in the APK or tracked in the repository. The user must authorize again after token expiry.

In public mode, remote mutations are disabled. When signed in, every review, merge and rerun requires confirmation and GitHub enforces the repository permissions and branch protection rules. Failed API calls are shown, not simulated.

## Alpha limitations

- Up to 12 public or 20 authenticated repositories in the list, with 4 public or 8 authenticated repositories queried for related PRs and Actions.
- Branch-specific commits load when selecting a branch; individual commit patches load on tap. Creating a remote branch requires authorization and confirmation.
- PR check status comes from GitHub Checks for a bounded subset of PRs; it remains Unknown if no check data is available.
- On-demand PR file patches and workflow job lists. Full logs open in GitHub.
- No push notifications, offline persistent cache, advanced API pagination, rebase or code editor.
- Anonymous API use is rate limited by GitHub; refresh is manual.

## Code structure

- app/src/main/java/dev/gitpilot/app/data: models, REST integration, encrypted session and ViewModel.
- app/src/main/java/dev/gitpilot/app/ui: Compose screens and account / remote action flows.
- .github/workflows/android.yml: unit tests, assemble debug APK and publish artifact.

## License

Not selected.
