package dev.gitpilot.app.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Both GitHub access and refresh tokens are AES-GCM encrypted under an Android Keystore
 * non-exportable key. Backups are disabled in the manifest. Never log either token.
 */
class SecureTokenStore(context: Context) {
    private val prefs = context.getSharedPreferences("gitpilot_session", Context.MODE_PRIVATE)
    private val alias = "gitpilot_oauth_token_v1"

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    fun save(
        accessToken: String, expiresInSeconds: Long?,
        refreshToken: String? = null, refreshExpiresInSeconds: Long? = null
    ) {
        val now = System.currentTimeMillis()
        // GitHub may omit expiry for a non-expiring user token.
        val accessExpiry = expiration(now, expiresInSeconds)
        val refreshExpiry = if (refreshToken.isNullOrBlank()) 0L
            else expiration(now, refreshExpiresInSeconds)
        val json = JSONObject()
            .put("version", 2)
            .put("access", accessToken)
            .put("access_expires_at", accessExpiry)
            .put("refresh", refreshToken ?: "")
            .put("refresh_expires_at", refreshExpiry)
            .toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(json.toByteArray(Charsets.UTF_8))
        prefs.edit()
            .putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .remove("expires_at")
            .apply()
    }

    /**
     * Also reads the old alpha access-token-only format, so upgrades do not
     * discard a still-valid session. Corrupt storage is erased rather than used.
     */
    fun readCredentials(): OAuthCredentials? {
        val encrypted = prefs.getString("ciphertext", null) ?: return null
        val iv = prefs.getString("iv", null) ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
            val data = String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), Charsets.UTF_8)
            if (data.startsWith("{")) {
                val json = JSONObject(data)
                require(json.optInt("version") == 2)
                val access = checkedOAuthToken(json.optString("access"), "stored access token")!!
                val refresh = checkedOAuthToken(json.optString("refresh"), "stored refresh token", required = false)
                OAuthCredentials(access, json.getLong("access_expires_at"),
                    refresh, json.optLong("refresh_expires_at"))
            } else {
                OAuthCredentials(data, prefs.getLong("expires_at", 0L), null, 0L)
            }
        } catch (_: Exception) {
            clear()
            null
        }
    }

    fun read(): String? = readCredentials()?.takeIf {
        it.accessUsable(System.currentTimeMillis())
    }?.accessToken

    fun clear() {
        // Persist removal before sign-out returns; do not leave encrypted tokens on disk.
        prefs.edit().clear().commit()
    }

    private fun expiration(now: Long, seconds: Long?): Long {
        if (seconds == null) return Long.MAX_VALUE
        val capped = seconds.coerceIn(0, 10L * 365L * 24L * 60L * 60L)
        return now + capped * 1000L
    }
}
