# GitPilot OAuth Worker — RC3 gateway migration

This Cloudflare Worker contains the **server-only GitHub App OAuth client secret** and performs code exchange/refresh for the native iOS RC3 migration. Its public endpoints are only the fixed routes `/oauth/exchange`, `/oauth/refresh`, the callback fallback, health, and domain-association files. It cannot make GitHub repo changes.

## Non-production defaults

The source code and CI **do not deploy the Worker or configure an OAuth account**. `workers_dev = false` deliberately disables the default public workers.dev host. Production deployment requires a registered GitHub App (expiring user access tokens, refresh enabled), an owned HTTPS custom domain, matching GitHub callback, Cloudflare Worker rate-limit binding and WAF, verified Apple App Site Association and device signing entitlements.

The publisher must provision `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_CALLBACK_URI`, `APPLE_APP_SITE_ASSOCIATION` and `ANDROID_ASSETLINKS` as Cloudflare secrets or secure variables outside Git history. Never commit the client secret, production signing identifiers, OAuth codes, access tokens, or real refresh tokens.

The backend checks a server-injected `CF-Connecting-IP` value, enforces rate limits per IP and endpoint, rejects oversized/malformed payloads, uses a configured fixed redirect URI, forbids upstream redirects, sanitizes provider errors and requires a complete expiring access/refresh-token rotation. A missing rate limiter fails closed. IP-based rate limits are abuse mitigation, **not authentication**; add Cloudflare WAF, provider monitoring and audit/incident procedures before public deployment.

## Offline verification

```bash
node --version   # Node 20 or newer
npm --prefix backend test
```

The OAuth Gateway CI workflow runs the deterministic Node tests on every gateway change. No GitHub credentials or network connectivity are needed. Real GitHub OAuth and HTTPS Universal Link verification on a signed iPhone remain separate, outstanding acceptance gates.

iOS build configuration is described in [ios/README.md](../ios/README.md). Passing backend tests does not make the SwiftUI preview release-ready.
