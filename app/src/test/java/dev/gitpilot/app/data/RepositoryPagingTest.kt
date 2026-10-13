package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RepositoryPagingTest {
    private fun repo(id: Long, pinned: Boolean = false): RepositoryItem =
        RepositoryItem(id, "repo" + id, "owner", "", "Kotlin", "main", "recent", pinned)

    @Test fun mergesDeduplicateExistingPinsAndKeepStableOrder() {
        val existing = listOf(repo(1L, true), repo(2L), repo(3L))
        val page = listOf(repo(2L), repo(4L, true), repo(5L))
        val merged = mergeRepositoryPages(existing, page)
        assertEquals(listOf(1L, 4L, 2L, 3L, 5L), merged.map { it.id })
        assertEquals(5, merged.size)
    }

    @Test fun fullPageOffersLoadMoreAndLastOrPartialPageStops() {
        assertTrue(hasAnotherRepositoryPage(20, 20, 1))
        assertTrue(hasAnotherRepositoryPage(12, 12, 4))
        assertFalse(hasAnotherRepositoryPage(19, 20, 1))
        assertFalse(hasAnotherRepositoryPage(0, 20, 2))
        assertFalse(hasAnotherRepositoryPage(20, 20, 5))
        assertFalse(hasAnotherRepositoryPage(20, 20, 6))
    }

    @Test fun mergePreservesOriginalGitHubRepositoryIdentity() {
        val original = repo(123L, true)
        val later = original.copy(name = "renamed", starred = false)
        val merged = mergeRepositoryPages(listOf(original), listOf(later))
        assertEquals(1, merged.size)
        assertEquals("repo123", merged.single().name)
        assertTrue(merged.single().starred)
    }
}
