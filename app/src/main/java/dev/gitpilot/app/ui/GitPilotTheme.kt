package dev.gitpilot.app.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * GitPilot Aurora: shared semantic colors with the native iOS edition.
 * Accessible lavender/mint/peach colors; no network fonts or dynamic secrets.
 */
private val Ink = Color(0xFF332C4A)
private val Lavender = Color(0xFFE8DDF9)
private val Mint = Color(0xFFD5F2E2)
private val Peach = Color(0xFFFFE5D6)
private val Blush = Color(0xFFF9DDEB)
private val LilacAccent = Color(0xFF6950B0)
private val MintAccent = Color(0xFF2D7557)

private val PastelPalette = lightColorScheme(
    primary = LilacAccent,
    onPrimary = Color.White,
    primaryContainer = Lavender,
    onPrimaryContainer = Ink,
    secondary = MintAccent,
    onSecondary = Color.White,
    secondaryContainer = Mint,
    onSecondaryContainer = Ink,
    tertiary = Color(0xFFA75575),
    onTertiary = Color.White,
    tertiaryContainer = Blush,
    onTertiaryContainer = Ink,
    background = Color(0xFFF8F5FB),
    onBackground = Ink,
    surface = Color.White,
    onSurface = Ink,
    surfaceVariant = Color(0xFFF1EBF9),
    onSurfaceVariant = Color(0xFF635D7A),
    surfaceTint = LilacAccent,
    outline = Color(0xFFDCD3EB),
    outlineVariant = Color(0xFFEDE5F4),
    error = Color(0xFFA74764),
    onError = Color.White,
    errorContainer = Peach,
    onErrorContainer = Ink,
    inverseSurface = Ink,
    inverseOnSurface = Color(0xFFF8F5FB)
)

private val AuroraShapes = Shapes(
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(18.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp)
)

private val AuroraTypography = Typography(
    headlineSmall = TextStyle(
        fontSize = 27.sp, lineHeight = 32.sp,
        fontWeight = FontWeight.SemiBold, letterSpacing = (-0.5).sp
    ),
    titleLarge = TextStyle(
        fontSize = 21.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold
    ),
    titleMedium = TextStyle(
        fontSize = 16.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold
    ),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp),
    labelMedium = TextStyle(fontSize = 12.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 15.sp, fontWeight = FontWeight.Medium)
)

@Composable
fun GitPilotTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = PastelPalette,
        shapes = AuroraShapes,
        typography = AuroraTypography,
        content = content
    )
}
