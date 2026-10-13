# GitPilot for Android

Native GitHub control center built with Kotlin, Jetpack Compose and Material 3.

## Version 0.9.0-alpha

Live public repository browsing now works without a GitHub login. GitHub App Device Flow sign-in and remote operations (reviews, squash merge and retry failed workflow jobs) are implemented; signed-in features require a GitHub App Client ID and installation permissions.

- Overview: pinned and recent repositories, pull requests and GitHub Actions from live GitHub REST endpoints. Pinned projects remain accessible even after dropping out of GitHub recent activity.
- Repositories: read-only folder navigation and UTF-8 text-file preview and single-file commit editing in the selected branch, history and commit patches, branch comparisons, branch creation and PR creation.
- PRs: real changed-file patches, GitHub conversation and inline review history, public PR comments with a confirmation dialog, review actions, and squash merge.
- Actions: real workflow runs and job logs, explicit cancellation of running runs, rerun failed jobs, and manually dispatch active workflows from a chosen branch or tag, with up to ten key=value inputs.
- Account: choose public GitHub username, connect/disconnect GitHub App user authorization.
- Native light/dark theme, color-coded unified diffs, manual refresh and visible API errors.

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

Access and refresh tokens are encrypted together using Android Keystore AES-GCM; Android backups are disabled. For expiring GitHub App user tokens obtained via Device Flow, GitPilot silently rotates credentials before they expire. Expired refresh credentials or revoked authorizations require signing in again. No client secret or token is embedded in the APK or tracked in the repository.

In public mode, remote mutations are disabled. When signed in, comments, reviews, merge, cancellation and rerun require confirmation and GitHub enforces the repository permissions and branch protection rules. Failed API calls are shown, not simulated.

## Alpha limitations

- Up to 12 public or 20 authenticated repositories in the list, with 4 public or 8 authenticated repositories queried for related PRs and Actions.
- Branch-specific commits load when selecting a branch; individual commit patches load on tap. Creating a remote branch requires authorization and confirmation.
- PR check status comes from GitHub Checks for a bounded subset of PRs; it remains Unknown if no check data is available.
- On-demand PR file patches, discussion history (first 50 issue comments and first 50 inline review comments) and workflow job lists. Job log previews show bounded output; full logs remain available on GitHub. Signed log redirects never receive the GitHub bearer token.
- Manual dispatch is available for workflows enabled with workflow_dispatch; supply any required inputs as key=value lines. No push notifications, offline persistent cache, advanced API pagination, rebase or code editor.
- Anonymous API use is rate limited by GitHub; refresh is manual.

## Code structure

- app/src/main/java/dev/gitpilot/app/data: models, REST integration, encrypted session and ViewModel.
- app/src/main/java/dev/gitpilot/app/ui: Compose screens and account / remote action flows.
- .github/workflows/android.yml: unit tests, assemble debug APK and publish artifact.

## License

Not selected.

## Network reliability

Workspace requests for recent repositories are performed with a concurrency limit of three. GitHub API rate-limit responses stop the refresh early instead of repeatedly retrying forbidden requests; authentication failures and coroutine cancellation propagate, while ordinary per-repository permission errors appear in Account warnings. Refresh remains manual, with a bounded number of monitored repositories and PR checks.

## Logout and session isolation

Signing out clears the in-memory workspace, private diffs, cached jobs, workflow definitions and encrypted credentials immediately, even while offline. In-flight detail requests use a session generation guard so they cannot reintroduce data from a previous account. Destructive operations are serialized to prevent duplicate submissions from repeated taps. Actual remote mutations still require user confirmation and GitHub permissions.

## UX improvements

The GitHub device authorization code can be copied directly to the Android clipboard before opening the browser. A failed or empty first workspace load now offers an explicit retry action; empty repository and Actions filters no longer silently show blank screens.

## Manual workflow parameters

For Actions → Run a workflow, select a repository, an active workflow and branch or tag. Supply optional inputs one per line, e.g. environment=staging. GitHub's workflow_dispatch endpoint is used and requires Actions write permission. The app validates names and duplicates but does not infer the required inputs from workflow YAML. Never enter credentials as inputs; use repository secrets.

## Pull request discussion and workflow cancellation

Open a PR to load its GitHub issue conversation and inline review comments together in chronological order. The app currently loads at most 50 entries from each endpoint; older/longer discussions may require opening the PR on GitHub. Signed-in users can post a conversation comment after seeing a confirmation dialog. GitHub checks permission and exposes comments to people with access to the PR. Input is trimmed, empty comments are rejected and submissions are bounded to 10,000 characters. Comments do not directly modify files.

On a running/queued Actions run, signed-in users can request cancellation after confirmation; the operation is unavailable once the run is completed. GitHub determines whether cancellation is still possible, including race conditions with completion. These actions never simulate remote success.

## Branch comparison and PR creation

Choose a non-default branch on a repository screen to fetch GitHub's base...head comparison against its default branch. The comparison reports ahead/behind counts and a bounded preview of the changed files. A signed-in user can create a pull request when the comparison contains at least one head-only commit, after entering a validated title and optional description and confirming the remote operation. GitHub remains authoritative for permissions and existing PRs; API errors are displayed. This alpha only compares against the default branch, not arbitrary branch pairs.

## Repository file browser

Repository details now have **Browse files** for the selected branch. GitPilot uses the GitHub Contents API to fetch one directory at a time; no bulk recursive checkout is performed. Folders appear first, filenames are alphabetical, and tapping a file loads a read-only UTF-8 preview. Files above 96 KB, binary files and unsupported encodings show a clear limitation; use **Open file on GitHub**. The first 32,000 characters of text are rendered on the phone. The browser keys its cache by owner, repository, branch and path, and clears private contents on sign-out. File edits and commits are still outside the alpha scope.

## Editing and committing a file

Signed-in users may edit a **complete UTF-8 preview of an existing file** (at most 32,000 characters) and submit a one-file commit on the selected branch. Choose **Edit and commit file**, modify the text, enter a commit message and confirm the remote write. The GitHub Contents API receives the previously fetched file blob SHA: concurrent edits cause a conflict instead of silently overwriting newer content. GitHub enforces Contents write permission and protected-branch rules. The editor refuses unchanged, binary, truncated and oversized files and never stores unsaved edits outside the current screen. Multi-file staging, creating new files, amend/rebase, and conflict resolution are not supported. To edit larger files use GitHub on the web.

## Mobile diff readability

PR files, commit diffs and branch comparisons now render bounded unified patches with distinct colors for additions, removals, metadata and hunk markers. The renderer works on GitHub-provided patches and deliberately truncates very long diffs to protect UI performance. Full diffs remain accessible on GitHub.
