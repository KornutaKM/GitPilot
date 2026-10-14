package dev.gitpilot.app.data

/**
 * OAuth session metadata only. The entire object is encrypted at rest in Android Keystore.
 * Access tokens must never be logged, included in crash reports or bundled with the APK.
 */
data class OAuthCredentials(
    val accessToken: String,
    val accessExpiresAtMs: Long,
    val refreshToken: String?,
    val refreshExpiresAtMs: Long
) {
    fun accessUsable(nowMs: Long): Boolean =
        accessToken.isNotBlank() && nowMs < accessExpiresAtMs - 60_000L

    fun refreshUsable(nowMs: Long): Boolean =
        !refreshToken.isNullOrBlank() && nowMs < refreshExpiresAtMs - 60_000L
}
