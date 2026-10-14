# Security notes for GitPilot Android

GitPilot is an **alpha** GitHub client. Successful compilation, unit tests and Android Lint do not replace a device security review or an end-to-end GitHub App authorization test.

## Authentication
- Sign-in uses GitHub App OAuth Device Flow and only the GitHub App's **public Client ID** is configured at build time.
- No GitHub App private key, client secret, personal access token or refresh token may be committed to the repository, included in APK build properties or placed in CI output.
- Access and refresh tokens are encrypted with a non-exportable Android Keystore AES-GCM key. Backups are disabled and shared preferences are additionally excluded from cloud/device-transfer extraction rules.
- GitHub controls installation access and repository permissions. Apps should request the minimum permissions required for the enabled actions.
- Signing out erases local tokens, private workspace caches and all locally pinned repository identifiers. Reauthorization after token expiration may also reset pins.

## Network
- GitHub API and OAuth requests use HTTPS to github.com and api.github.com.
- Android cleartext network traffic is disabled through manifest and network security configuration.
- Workflow log downloads may redirect to temporary signed hosts. Those redirects are checked against a narrow list of expected HTTPS host suffixes, and the GitHub bearer token is never sent to the redirected URL.
- API rate limits, HTTP permission errors and conflicts should be shown in the UI, not treated as success.

## Remote writes
- PR comments/reviews, merges, branch creation, GitHub Actions operations, and Contents API writes require an authenticated user and confirmation.
- One-file edits supply the previous GitHub blob SHA. This protects against **file-level** concurrent modifications. Repository branch protections and GitHub's API are authoritative; this does not implement arbitrary Git history rebases or transactional multi-file commits.
- New-file commits omit the SHA so GitHub refuses to overwrite an existing file silently.
- Mobile text previews are bounded; large, binary and unsupported file types are not edited in-app.
- Never include credentials in commit messages, workflow-dispatch inputs or PR comments. Use GitHub Actions encrypted secrets where appropriate.

## Security review and vulnerability reporting
Run tests against a disposable GitHub repo and keep PR #1 as Draft until the device QA checklist in issue #2 is complete. If GitHub private vulnerability reporting is enabled for this repository, use it for sensitive disclosures; otherwise contact the maintainer privately rather than posting secrets in a public issue.

Known gaps: no dedicated dynamic penetration test, no physical-device OAuth/write-flow acceptance run, no audit of third-party SDK source packages and no security review of an App Store / Play Store production release.
