package dev.gitpilot.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Midnight = Color(0xFF0D1018)
private val DarkSurface = Color(0xFF191E2A)
private val DarkForeground = Color(0xFFF2F4FB)
private val Indigo = Color(0xFF9BA8FF)

private val DarkPalette = darkColorScheme(
    primary = Indigo,
    onPrimary = Color(0xFF151B46),
    background = Midnight,
    onBackground = DarkForeground,
    surface = DarkSurface,
    onSurface = DarkForeground,
    surfaceVariant = Color(0xFF262D3B),
    onSurfaceVariant = Color(0xFFB0B8CB),
    outline = Color(0xFF41485A)
)

private val LightPalette = lightColorScheme(
    primary = Color(0xFF4357CC),
    onPrimary = Color.White,
    background = Color(0xFFF5F6FA),
    onBackground = Color(0xFF181D2A),
    surface = Color.White,
    onSurface = Color(0xFF181D2A),
    surfaceVariant = Color(0xFFE9ECF5),
    onSurfaceVariant = Color(0xFF545D6F),
    outline = Color(0xFFD3D8E4)
)

@Composable
fun GitPilotTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkPalette else LightPalette,
        content = content
    )
}
