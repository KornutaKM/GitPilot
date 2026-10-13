package dev.gitpilot.app.data

enum class DiffLineKind { ADDED, REMOVED, HUNK, META, CONTEXT }

fun classifyDiffLine(line: String): DiffLineKind = when {
    line.startsWith("@@") -> DiffLineKind.HUNK
    line.startsWith("+++") || line.startsWith("---") ||
        line.startsWith("diff ") || line.startsWith("index ") -> DiffLineKind.META
    line.startsWith("+") -> DiffLineKind.ADDED
    line.startsWith("-") -> DiffLineKind.REMOVED
    else -> DiffLineKind.CONTEXT
}
