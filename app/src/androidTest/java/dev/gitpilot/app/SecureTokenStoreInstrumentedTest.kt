package dev.gitpilot.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.gitpilot.app.data.SecureTokenStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The actual Android Keystore is exercised on a disposable CI emulator.
 * Never use a real GitHub token in instrumentation test fixtures.
 */
@RunWith(AndroidJUnit4::class)
class SecureTokenStoreInstrumentedTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test fun credentialsRoundTripThroughRealAndroidKeystore() {
        val store = SecureTokenStore(context)
        store.clear()
        try {
            store.save(
                accessToken = "test-only-access-token",
                expiresInSeconds = 3600L,
                refreshToken = "test-only-refresh-token",
                refreshExpiresInSeconds = 7200L
            )
            val restored = store.readCredentials()
            assertEquals("test-only-access-token", restored?.accessToken)
            assertEquals("test-only-refresh-token", restored?.refreshToken)
            assertEquals("test-only-access-token", store.read())

            val prefs = context.getSharedPreferences("gitpilot_session", Context.MODE_PRIVATE)
            val persisted = prefs.all.values.joinToString(",")
            assertTrue(prefs.contains("ciphertext"))
            assertTrue(prefs.contains("iv"))
            assertFalse(persisted.contains("test-only-access-token"))
            assertFalse(persisted.contains("test-only-refresh-token"))
        } finally {
            store.clear()
        }
    }

    @Test fun logoutPermanentlyClearsEncryptedCredentialPreferences() {
        val store = SecureTokenStore(context)
        store.clear()
        store.save("test-only-access-token", 3600L, "test-only-refresh-token", 7200L)
        store.clear()

        val prefs = context.getSharedPreferences("gitpilot_session", Context.MODE_PRIVATE)
        assertTrue(prefs.all.isEmpty())
        assertNull(store.readCredentials())
        assertNull(store.read())
    }

    @Test fun corruptedCiphertextFailsClosedAndErasesTheStoredSession() {
        val store = SecureTokenStore(context)
        store.clear()
        try {
            store.save("test-only-access-token", 3600L)
            val prefs = context.getSharedPreferences("gitpilot_session", Context.MODE_PRIVATE)
            prefs.edit().putString("ciphertext", "not-valid-base64!").commit()
            assertNull(store.readCredentials())
            assertTrue(prefs.all.isEmpty())
        } finally {
            store.clear()
        }
    }
}
