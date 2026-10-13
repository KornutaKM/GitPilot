package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BranchOperationsTest {
    @Test fun branchComparisonOnlyAllowsPullRequestWhenAhead() {
        val withChanges = BranchComparison("main", "feature/safe", "ahead", 2, 0, emptyList(), "")
        val unchanged = withChanges.copy(aheadBy = 0, status = "identical")
        val sameBranch = withChanges.copy(head = "main")
        assertTrue(withChanges.canOpenPullRequest)
        assertFalse(unchanged.canOpenPullRequest)
        assertFalse(sameBranch.canOpenPullRequest)
    }

    @Test fun pullRequestTitleIsRequiredAndTrimmed() {
        assertEquals("Improve CI", validatedPullRequestDraft("  Improve CI  ", "  Description ").first)
        assertEquals("Description", validatedPullRequestDraft("Improve CI", "  Description ").second)
        assertTrue(runCatching { validatedPullRequestDraft("   ", "") }.isFailure)
    }

    @Test fun oversizedPrDraftsAreRejected() {
        assertTrue(runCatching { validatedPullRequestDraft("x".repeat(201), "") }.isFailure)
        assertTrue(runCatching { validatedPullRequestDraft("Title", "x".repeat(10_001)) }.isFailure)
        assertEquals(200, validatedPullRequestDraft("x".repeat(200), "").first.length)
    }

    @Test fun comparisonKeepsBaseAndSourceReferences() {
        val comparison = BranchComparison("develop", "fix/login", "diverged", 3, 1, emptyList(), "")
        assertEquals("develop", comparison.base)
        assertEquals("fix/login", comparison.head)
        assertEquals(3, comparison.aheadBy)
        assertEquals(1, comparison.behindBy)
    }
}
