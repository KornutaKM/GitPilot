package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PrDiscussionTest {
    @Test fun commentDraftIsTrimmedAndPreservesMeaningfulLineBreaks() {
        assertEquals("First line\nSecond line", validateDiscussionDraft(" \nFirst line\nSecond line \n"))
    }

    @Test fun blankAndExcessiveCommentsAreRejected() {
        assertTrue(runCatching { validateDiscussionDraft(" \n \t") }.isFailure)
        assertTrue(runCatching { validateDiscussionDraft("x".repeat(10_001)) }.isFailure)
        assertEquals(10_000, validateDiscussionDraft("x".repeat(10_000)).length)
    }

    @Test fun discussionCombinesIssueAndInlineReviewChronologically() {
        val newer = DiscussionEntry(41, DiscussionKind.CONVERSATION, "alice", "Later",
            "2026-10-13T12:00:00Z", "https://github.com/example/repo/pull/1")
        val inline = DiscussionEntry(99, DiscussionKind.INLINE_REVIEW, "bob", "Earlier",
            "2026-10-12T12:00:00Z", "https://github.com/example/repo/pull/1", "src/app.kt", 12)
        val sameDateSmallerId = newer.copy(id = 40)
        val actual = combineDiscussion(listOf(newer, sameDateSmallerId), listOf(inline))
        assertEquals(listOf(99L, 40L, 41L), actual.map { it.id })
        assertEquals("src/app.kt", actual.first().path)
    }

    @Test fun emptyDiscussionIsAnEmptyList() {
        assertTrue(combineDiscussion(emptyList(), emptyList()).isEmpty())
    }
}
