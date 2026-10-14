package dev.gitpilot.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * GitPilot Aurora: shared semantic colors with the native iOS edition.
 * Readable light and dark schemes; no network-loaded fonts or dynamic palettes.
 */
private val Ink = Color(0xFF0B0E16)
private val Panel = Color(0xFF151B28)
private val Lavender = Color(0xFFB0A1FF)
private val Mint = Color(0xFF66DDAF)
private val LightInk = Color(0xFF192034)

private val DarkPalette = darkColorScheme(
    primary = Lavender,
    onPrimary = Color(0xFF241D49),
    primaryContainer = Color(0xFF302752),
    onPrimaryContainer = Color(0xFFECE5FF),
    secondary = Mint,
    onSecondary = Ink,
    background = Ink,
    onBackground = Color(0xFFF6F5FC),
    surface = Panel,
    onSurface = Color(0xFFF6F5FC),
    surfaceVariant = Color(0xFF222A39),
    onSurfaceVariant = Color(0xFFB4BED0),
    outline = Color(0xFF435064),
    error = Color(0xFFFF7683),
    onError = Ink
)

private val LightPalette = lightColorScheme(
    primary = Color(0xFF6254BA),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFECE6FF),
    onPrimaryContainer = Color(0xFF30235D),
    secondary = Color(0xFF26795A),
    onSecondary = Color.White,
    background = Color(0xFFF7F7FC),
    onBackground = LightInk,
    surface = Color.White,
    onSurface = LightInk,
    surfaceVariant = Color(0xFFF0F1F8),
    onSurfaceVariant = Color(0xFF596278),
    outline = Color(0xFFD2D7E5),
    error = Color(0xFFBB344C),
    onError = Color.White
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
        colorScheme = if (isSystemInDarkTheme()) DarkPalette else LightPalette,
        shapes = AuroraShapes,
        typography = AuroraTypography,
        content = content
    )
}
