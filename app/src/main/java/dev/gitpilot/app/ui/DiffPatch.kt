package dev.gitpilot.app.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.sp
import dev.gitpilot.app.data.DiffLineKind
import dev.gitpilot.app.data.classifyDiffLine

/**
 * A compact syntax-aware unified diff view. Limits rendered lines for smooth
 * Compose scrolling and makes additions/removals recognizable at a glance.
 */
@Composable
fun DiffPatch(patch: String, maxLines: Int = 200) {
    val colorScheme = MaterialTheme.colorScheme
    val lines = patch.lines()
    val rendered = lines.take(maxLines)
    val text = buildAnnotatedString {
        rendered.forEach { line ->
            val foreground = when (classifyDiffLine(line)) {
                DiffLineKind.ADDED -> Color(0xFF36BD88)
                DiffLineKind.REMOVED -> Color(0xFFE76B7A)
                DiffLineKind.HUNK -> colorScheme.primary
                DiffLineKind.META -> colorScheme.secondary
                DiffLineKind.CONTEXT -> colorScheme.onSurfaceVariant
            }
            withStyle(SpanStyle(color = foreground)) {
                append(line)
                append('\n')
            }
        }
        if (lines.size > maxLines) {
            withStyle(SpanStyle(color = colorScheme.primary)) {
                append("… Diff preview truncated at " + maxLines + " lines.\n")
            }
        }
    }
    Text(
        text = text,
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        fontFamily = FontFamily.Monospace,
        fontSize = 12.sp,
        lineHeight = 18.sp
    )
}
