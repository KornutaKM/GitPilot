package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Test

class DiffFormattingTest {
    @Test fun additionsAndDeletionsAreDistinct() {
        assertEquals(DiffLineKind.ADDED, classifyDiffLine("+ new code"))
        assertEquals(DiffLineKind.REMOVED, classifyDiffLine("- old code"))
    }

    @Test fun fileHeadersAreNeverMisclassifiedAsChanges() {
        assertEquals(DiffLineKind.META, classifyDiffLine("+++ b/example.kt"))
        assertEquals(DiffLineKind.META, classifyDiffLine("--- a/example.kt"))
        assertEquals(DiffLineKind.META, classifyDiffLine("diff --git a/x b/x"))
        assertEquals(DiffLineKind.META, classifyDiffLine("index 22..33"))
    }

    @Test fun hunkAndUnchangedLinesHaveTheirOwnStyle() {
        assertEquals(DiffLineKind.HUNK, classifyDiffLine("@@ -1,2 +1,2 @@"))
        assertEquals(DiffLineKind.CONTEXT, classifyDiffLine("   val unchanged = true"))
        assertEquals(DiffLineKind.CONTEXT, classifyDiffLine(""))
    }
}
