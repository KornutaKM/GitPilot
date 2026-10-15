package dev.gitpilot.app.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OAuthCredentialsTest {
    @Test fun accessTokenIsRefreshableBeforeExpiry() {
        val now = 1_000_000L
        val credentials = OAuthCredentials("ghu_redacted", now + 40_000, "ghr_redacted", now + 120_000)
        assertFalse(credentials.accessUsable(now))
        assertTrue(credentials.refreshUsable(now))
    }

    @Test fun refreshTokenExpiryRequiresNewSignIn() {
        val now = 1_000_000L
        val credentials = OAuthCredentials("ghu_redacted", now - 1, "ghr_redacted", now + 30_000)
        assertFalse(credentials.accessUsable(now))
        assertFalse(credentials.refreshUsable(now))
    }

    @Test fun missingRefreshTokenIsNotEligibleForRefresh() {
        val now = 1_000_000L
        val credentials = OAuthCredentials("legacy_access", now + 120_000, null, 0)
        assertTrue(credentials.accessUsable(now))
        assertFalse(credentials.refreshUsable(now))
    }

    @Test fun nonExpiringAccessTokenRemainsUsable() {
        val credentials = OAuthCredentials("legacy_access", Long.MAX_VALUE, null, 0)
        assertTrue(credentials.accessUsable(System.currentTimeMillis()))
    }

    @Test fun credentialToStringNeverContainsTokenValues() {
        val session = OAuthCredentials("very-secret-access", Long.MAX_VALUE,
            "very-secret-refresh", Long.MAX_VALUE)
        val shown = session.toString()
        assertFalse(shown.contains("very-secret-access"))
        assertFalse(shown.contains("very-secret-refresh"))
        assertTrue(shown.contains("<redacted>"))
        val legacy = OAuthCredentials("legacy-sensitive", Long.MAX_VALUE, null, 0)
        assertFalse(legacy.toString().contains("legacy-sensitive"))
    }
}
