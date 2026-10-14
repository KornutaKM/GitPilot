package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RepositoryFilesTest {
    private val repo = RepositoryItem(3_500_000_000L, "GitPilot", "KornutaKM",
        "Android client", "Kotlin", "main", "today", true)

    @Test fun folderAndParentNavigationUsesExactPaths() {
        assertEquals("", parentDirectory(""))
        assertEquals("", parentDirectory("app"))
        assertEquals("app/src/main", parentDirectory("app/src/main/java"))
        assertEquals("app/src", parentDirectory("app/src/main"))
    }

    @Test fun pathValidationRejectsTraversalAndMalformedComponents() {
        for (path in listOf("../secret", "app/../secret", "app//build", "/root",
                "app/./file", "a\\b", "a/\u0000file")) {
            assertTrue(path, runCatching { validateRepositoryPath(path) }.isFailure)
        }
        assertEquals("", validateRepositoryPath(""))
        assertEquals("app/src/main", validateRepositoryPath("app/src/main"))
    }

    @Test fun folderSortIsStableAndCaseInsensitive() {
        val files = listOf(
            GitHubFileEntry("README.md", "README.md", GitHubEntryType.FILE, 45, ""),
            GitHubFileEntry("zeta", "zeta", GitHubEntryType.DIRECTORY, 0, ""),
            GitHubFileEntry("app", "app", GitHubEntryType.DIRECTORY, 0, ""),
            GitHubFileEntry("build.gradle.kts", "build.gradle.kts", GitHubEntryType.FILE, 12, "")
        )
        assertEquals(listOf("app", "zeta", "build.gradle.kts", "README.md"),
            sortDirectoryEntries(files).map { it.name })
    }

    @Test fun cacheKeysAreSeparatedByBranchAndRepositoryAndPath() {
        val base = repositoryPathKey(repo, "main", "app/build.gradle.kts")
        assertTrue(base != repositoryPathKey(repo, "feature/x", "app/build.gradle.kts"))
        assertTrue(base != repositoryPathKey(repo, "main", "README.md"))
        assertTrue(base != repositoryPathKey(repo.copy(owner = "Other"), "main", "app/build.gradle.kts"))
    }
}
