package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FileCommitTest {
    private val sha = "0123456789abcdef0123456789abcdef01234567"

    @Test fun commitMessageIsValidatedAndTrimmed() {
        assertEquals("fix: update readme", validateFileCommit("before", "after",
            "  fix: update readme  ", sha))
    }

    @Test fun emptyUnchangedAndOverlongCommitsAreRejected() {
        assertTrue(runCatching { validateFileCommit("a", "b", "  ", sha) }.isFailure)
        assertTrue(runCatching { validateFileCommit("a", "a", "fix", sha) }.isFailure)
        assertTrue(runCatching { validateFileCommit("a", "b", "x".repeat(181), sha) }.isFailure)
        assertTrue(runCatching { validateFileCommit("a", "b", "fix", "shortsha") }.isFailure)
    }

    @Test fun cannotWriteTruncatedTextOrOversizedBytes() {
        assertTrue(runCatching {
            validateFileCommit("x".repeat(32_001), "new", "fix", sha)
        }.isFailure)
        assertTrue(runCatching {
            validateFileCommit("a", "\u00e9".repeat(50_000), "fix", sha)
        }.isFailure)
    }

    @Test fun upperCaseValidShaAndUtf8ContentAllowed() {
        assertEquals("Update internationalization",
            validateFileCommit("Hello", "Привет", "Update internationalization",
                sha.uppercase()))
    }
}
