package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GitHubDomainTest {
    @Test fun repositoryIdsRemain64Bit() {
        val id = 3_500_000_000L
        val repo = RepositoryItem(id, "repo", "owner", "desc", "Kotlin", "main", "today", false)
        val workspace = Workspace(listOf(repo), emptyList(), emptyList(), mapOf(id to emptyList()), mapOf(id to emptyList()))
        assertEquals(id, workspace.repositories.single().id)
        assertTrue(workspace.branches.containsKey(id))
    }

    @Test fun fullCommitShaSurvivesShortLabel() {
        val fullSha = "0123456789abcdef0123456789abcdef01234567"
        val commit = CommitItem(fullSha.take(8), "A commit", "dev", "today", -1, 0, 0, fullSha)
        assertNotEquals(commit.sha, commit.fullSha)
        assertEquals(fullSha, commit.fullSha)
    }

    @Test fun unknownDoesNotMeanSuccessful() {
        assertNotEquals(CheckStatus.SUCCESS, CheckStatus.UNKNOWN)
    }
}
