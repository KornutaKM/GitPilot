package dev.gitpilot.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class DeviceFlowSecurityTest {
    private fun validResponse(): JSONObject = JSONObject()
        .put("device_code", "redacted-device-token")
        .put("user_code", "ABCD-EFGH")
        .put("verification_uri", "https://github.com/login/device")
        .put("expires_in", 900)
        .put("interval", 5)

    @Test fun githubDeviceVerificationAcceptsOnlyTheExactSecureOrigin() {
        assertTrue(isSafeGitHubDeviceVerificationUri("https://github.com/login/device"))
        assertTrue(isSafeGitHubDeviceVerificationUri("https://github.com:443/login/device"))
        listOf(
            "http://github.com/login/device",
            "https://github.com.evil.example/login/device",
            "https://evil.github.com/login/device",
            "https://user:password@github.com/login/device",
            "https://github.com:444/login/device",
            "https://github.com/login/device?return_to=https://evil.test",
            "https://github.com/login/device#token",
            "https://github.com/login/other",
            "https://github.com/login/device/../settings",
            "//github.com/login/device",
            "javascript:alert(1)",
            "https://github.com./login/device",
            ""
        ).forEach { assertFalse("Unexpectedly trusted: $it", isSafeGitHubDeviceVerificationUri(it)) }
    }

    @Test fun pollingIntervalsAreBoundedToAvoidBusyLoopsOrOverflow() {
        assertEquals(5L, safeDevicePollInterval(0))
        assertEquals(5L, safeDevicePollInterval(-1))
        assertEquals(5L, safeDevicePollInterval(5))
        assertEquals(30L, safeDevicePollInterval(30))
        assertEquals(60L, safeDevicePollInterval(3600))
        assertEquals(60L, safeDevicePollInterval(Long.MAX_VALUE))
    }

    @Test fun authorizationExpiryMustRemainWithinAReasonableWindow() {
        assertEquals(1L, safeDeviceExpiry(1L))
        assertEquals(900L, safeDeviceExpiry(900L))
        assertEquals(1800L, safeDeviceExpiry(1800L))
        listOf(0L, -1L, 1801L, Long.MAX_VALUE).forEach {
            assertTrue(runCatching { safeDeviceExpiry(it) }.exceptionOrNull() is IOException)
        }
    }

    @Test fun validGitHubDeviceResponseIsParsedWithControlledDefaults() {
        val result = decodeGitHubDeviceCode(validResponse())
        assertEquals("redacted-device-token", result.deviceCode)
        assertEquals("ABCD-EFGH", result.userCode)
        assertEquals("https://github.com/login/device", result.verificationUri)
        assertEquals(900L, result.expiresInSeconds)
        assertEquals(5L, result.intervalSeconds)
        val deferred = decodeGitHubDeviceCode(validResponse().put("interval", 3600))
        assertEquals(60L, deferred.intervalSeconds)
    }

    @Test fun untrustedVerificationLinksFailBeforeOpeningBrowser() {
        val payload = validResponse()
            .put("verification_uri", "https://login.github.com.evil.test/verify")
        val failure = runCatching { decodeGitHubDeviceCode(payload) }.exceptionOrNull()
        assertTrue(failure is IOException)
        assertFalse(failure?.message.orEmpty().contains("evil.test"))
    }

    @Test fun malformedOrIncompleteDeviceResponsesFailClosed() {
        val cases = listOf(
            validResponse().put("device_code", JSONObject.NULL),
            validResponse().put("device_code", ""),
            validResponse().put("device_code", "contains whitespace"),
            validResponse().put("user_code", JSONObject.NULL),
            validResponse().put("user_code", "incorrect code"),
            validResponse().put("verification_uri", "http://github.com/login/device"),
            validResponse().put("expires_in", 0),
            validResponse().put("expires_in", 1801)
        )
        cases.forEach { assertTrue(runCatching { decodeGitHubDeviceCode(it) }.isFailure) }
    }

    @Test fun deviceCodesStayRedactedEvenWhenStateIsConvertedToText() {
        val device = decodeGitHubDeviceCode(validResponse())
        val dumped = device.toString()
        assertFalse(dumped.contains(device.deviceCode))
        assertFalse(dumped.contains(device.userCode))
    }

    @Test fun nonExpiringUserOAuthTokenRemainsSupported() {
        val response = JSONObject().put("access_token", "ghu_sample")
        val creds = decodeOAuthAuthorization(response)
        assertEquals("ghu_sample", creds.accessToken)
        assertEquals(null, creds.expiresInSeconds)
        assertEquals(null, creds.refreshToken)
        assertEquals(null, creds.refreshExpiresInSeconds)
    }

    @Test fun completeExpiringAndRenewedTokensAreAccepted() {
        val response = JSONObject()
            .put("access_token", "ghu_rotated")
            .put("expires_in", 28_800)
            .put("refresh_token", "ghr_rotated")
            .put("refresh_token_expires_in", 15_897_600)
        val creds = decodeOAuthAuthorization(response, requireRefresh = true)
        assertEquals(28_800L, creds.expiresInSeconds)
        assertEquals("ghr_rotated", creds.refreshToken)
        assertEquals(15_897_600L, creds.refreshExpiresInSeconds)
        assertFalse(creds.toString().contains("ghu_rotated"))
        assertFalse(creds.toString().contains("ghr_rotated"))
    }

    @Test fun incompleteTokenRotationFailsBeforeReplacingTheStoredSession() {
        val full = JSONObject()
            .put("access_token", "ghu_rotated")
            .put("expires_in", 28_800)
            .put("refresh_token", "ghr_rotated")
            .put("refresh_token_expires_in", 15_897_600)
        val missing = listOf("expires_in", "refresh_token", "refresh_token_expires_in")
        missing.forEach { field ->
            val copy = JSONObject(full.toString())
            copy.remove(field)
            assertTrue("Unexpected success without $field", runCatching {
                decodeOAuthAuthorization(copy, requireRefresh = true)
            }.isFailure)
        }
        assertTrue(runCatching {
            decodeOAuthAuthorization(JSONObject().put("access_token", "ghu_only"), requireRefresh = true)
        }.isFailure)
    }

    @Test fun malformedOAuthTokenLifetimeIsRejected() {
        listOf(0L, -2L, 315_360_001L, Long.MAX_VALUE).forEach { invalid ->
            val value = JSONObject().put("access_token", "ghu_test")
                .put("expires_in", invalid)
            assertTrue(runCatching { decodeOAuthAuthorization(value) }.isFailure)
        }
    }

    @Test fun oauthErrorTypesNeverEchoTheProviderDescription() {
        val failure = GitHubOAuthException("invalid_grant")
        assertFalse(failure.message.orEmpty().contains("refresh_token"))
        assertTrue(failure.message.orEmpty().contains("expired"))
        val unknown = GitHubOAuthException("custom-malicious-secret")
        assertFalse(unknown.message.orEmpty().contains("custom-malicious-secret"))
    }
}
