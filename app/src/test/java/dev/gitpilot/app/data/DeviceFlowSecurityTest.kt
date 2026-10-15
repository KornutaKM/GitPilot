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
}
