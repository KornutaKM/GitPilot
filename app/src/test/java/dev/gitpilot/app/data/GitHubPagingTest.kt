package dev.gitpilot.app.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class GitHubPagingTest {
    @Test fun shortFirstPageStopsWithoutExtraRequests() = runBlocking {
        val requested = mutableListOf<Int>()
        val result = collectBoundedGitHubPages(pageSize = 30, maxPages = 4) { page ->
            requested += page
            listOf("a", "b")
        }
        assertEquals(listOf(1), requested)
        assertEquals(listOf("a", "b"), result)
    }

    @Test fun exactFullPageLoadsMoreAndStopsOnPartialPage() = runBlocking {
        val requested = mutableListOf<Int>()
        val result = collectBoundedGitHubPages(pageSize = 3, maxPages = 4) { page ->
            requested += page
            when (page) {
                1 -> listOf(1, 2, 3)
                2 -> listOf(4, 5)
                else -> throw AssertionError("Extra GitHub request")
            }
        }
        assertEquals(listOf(1, 2), requested)
        assertEquals(listOf(1, 2, 3, 4, 5), result)
    }

    @Test fun fullPagesNeverExceedSpecifiedRequestBudget() = runBlocking {
        val requested = mutableListOf<Int>()
        val result = collectBoundedGitHubPages(pageSize = 50, maxPages = 3) { page ->
            requested += page
            (1..50).map { (page - 1) * 50 + it }
        }
        assertEquals(listOf(1, 2, 3), requested)
        assertEquals(150, result.size)
        assertEquals(150, result.last())
    }

    @Test fun emptyFirstPageReturnsEmptyData() = runBlocking {
        val requested = mutableListOf<Int>()
        val result = collectBoundedGitHubPages<Int>(pageSize = 100, maxPages = 2) { page ->
            requested += page
            emptyList()
        }
        assertTrue(result.isEmpty())
        assertEquals(listOf(1), requested)
    }

    @Test fun oversizedPageFailsClosed() = runBlocking {
        val error = runCatching {
            collectBoundedGitHubPages(pageSize = 2, maxPages = 4) {
                listOf(1, 2, 3)
            }
        }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
    }

    @Test fun pagingPreservesHttpErrorsInsteadOfDisplayingTruncatedSuccess() = runBlocking {
        val error = runCatching {
            collectBoundedGitHubPages(pageSize = 2, maxPages = 3) { page ->
                if (page == 2) throw IOException("GitHub unavailable")
                listOf(1, 2)
            }
        }.exceptionOrNull()
        assertTrue(error is IOException)
    }

    @Test fun cancellationIsNotSwallowedByPagination() = runBlocking {
        val error = runCatching {
            collectBoundedGitHubPages(pageSize = 2, maxPages = 3) { page ->
                if (page == 2) throw CancellationException("Cancelled by view model")
                listOf(1, 2)
            }
        }.exceptionOrNull()
        assertTrue(error is CancellationException)
    }

    @Test fun pagedPathEncodesBoundedParametersOnce() {
        assertEquals(
            "/repos/octocat/Hello-World/pulls/3/files?per_page=30&page=2",
            gitHubPagedPath("/repos/octocat/Hello-World/pulls/3/files", 30, 2)
        )
        assertEquals(
            "/repos/o/r/actions/runs/99/jobs?per_page=100&page=5",
            gitHubPagedPath("/repos/o/r/actions/runs/99/jobs", 100, 5)
        )
    }

    @Test fun paginationNeverAcceptsUserControlledQueriesOrInvalidParameters() {
        val invalidPaths = listOf(
            "", "https://evil.example/api", "//evil.example/path",
            "/path?token=bad", "/path#fragment", "/path\nmalformed", "/path\rmalformed"
        )
        invalidPaths.forEach { path ->
            assertTrue(path, runCatching { gitHubPagedPath(path, 30, 1) }.isFailure)
        }
        assertFalse(runCatching { gitHubPagedPath("/repos/o/r", 50, 1) }.isFailure)
        assertTrue(runCatching { gitHubPagedPath("/repos/o/r", 0, 1) }.isFailure)
        assertTrue(runCatching { gitHubPagedPath("/repos/o/r", 101, 1) }.isFailure)
        assertTrue(runCatching { gitHubPagedPath("/repos/o/r", 30, 0) }.isFailure)
        assertTrue(runCatching { gitHubPagedPath("/repos/o/r", 30, 6) }.isFailure)
    }

    @Test fun recompositionCannotStartTheSameDetailRequestTwice() {
        val gate = GitHubDetailRequestGate()
        assertTrue(gate.begin(1L, "pr-files:repo#7"))
        assertFalse(gate.begin(1L, "pr-files:repo#7"))
        assertTrue(gate.begin(1L, "jobs:12"))
        gate.finish(1L, "pr-files:repo#7")
        assertTrue(gate.begin(1L, "pr-files:repo#7"))
    }

    @Test fun olderRefreshCannotReleaseOrBlockNewGeneration() {
        val gate = GitHubDetailRequestGate()
        assertTrue(gate.begin(10L, "discussion:repo#7"))
        assertTrue(gate.begin(11L, "discussion:repo#7"))
        gate.finish(10L, "discussion:repo#7")
        assertFalse(gate.begin(11L, "discussion:repo#7"))
        gate.finish(11L, "discussion:repo#7")
        assertTrue(gate.begin(11L, "discussion:repo#7"))
    }

    @Test fun concurrentDuplicateRequestsAcquireExactlyOneSlot() {
        val gate = GitHubDetailRequestGate()
        val accepted = java.util.Collections.synchronizedList(mutableListOf<Boolean>())
        val workers = (1..16).map {
            Thread { accepted.add(gate.begin(3L, "commits:main")) }
        }
        workers.forEach { it.start() }
        workers.forEach { it.join() }
        assertEquals(1, accepted.count { it })
        gate.finish(3L, "commits:main")
        assertTrue(gate.begin(3L, "commits:main"))
    }
}
