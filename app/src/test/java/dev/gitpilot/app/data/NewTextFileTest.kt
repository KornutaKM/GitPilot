package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NewTextFileTest {
    @Test fun createsPathWithinSelectedDirectory() {
        val result = validateNewTextFile("docs/guides", " quickstart.md ", "# Hello\n", " docs: add guide ")
        assertEquals("docs/guides/quickstart.md", result.first)
        assertEquals("docs: add guide", result.second)
        assertEquals(".gitignore", validateNewTextFile("", ".gitignore", "*.log", "chore: ignore").first)
    }

    @Test fun refusesTraversalAndReservedGitMetadata() {
        for (name in listOf("../secrets", "other/readme.md", ".", "..", ".git", "temp.lock",
                "a\\b", "x\nname", "a name")) {
            assertTrue(name, runCatching {
                validateNewTextFile("docs", name, "contents", "feat: add file")
            }.isFailure)
        }
        assertTrue(runCatching {
            validateNewTextFile("../outside", "file.txt", "", "add")
        }.isFailure)
    }

    @Test fun boundsTextAndHandlesMultibyteUtf8() {
        assertTrue(runCatching {
            validateNewTextFile("", "large.txt", "a".repeat(32_001), "add")
        }.isFailure)
        // 32K CJK chars encode to 96KB: still within the maximum.
        assertEquals("wide.txt",
            validateNewTextFile("", "wide.txt", "界".repeat(32_000), "add").first)
        assertEquals("empty.txt", validateNewTextFile("", "empty.txt", "", "add empty").first)
    }

    @Test fun requiresBoundedCommitMessage() {
        assertTrue(runCatching { validateNewTextFile("", "a.txt", "data", " \n") }.isFailure)
        assertTrue(runCatching {
            validateNewTextFile("", "a.txt", "data", "x".repeat(181))
        }.isFailure)
        assertEquals(180, validateNewTextFile("", "file.txt", "data",
            "x".repeat(180)).second.length)
    }
}
