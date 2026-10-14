package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    @Test fun pinnedRepositoriesComeFirstWithoutLosingRecencyWithinGroups() {
        val demo = DemoWorkspaceRepository.snapshot().repositories
        val input = listOf(demo[3], demo[0], demo[1], demo[2])
        val ordered = prioritizeRepositories(input)
        assertEquals(listOf(demo[0].id, demo[1].id, demo[2].id, demo[3].id), ordered.map { it.id })
    }

    @Test fun jobLogRedirectsUseOnlyKnownDownloadHosts() {
        assertTrue(isSafeJobLogHost("pipelines.actions.githubusercontent.com"))
        assertTrue(isSafeJobLogHost("builds.blob.core.windows.net"))
        assertFalse(isSafeJobLogHost("actions.githubusercontent.com.evil.example"))
        assertFalse(isSafeJobLogHost("example.org"))
    }

    @Test fun workflowDispatchRefValidationRejectsUnsafeNames() {
        assertTrue(validGitRefName("main"))
        assertTrue(validGitRefName("release/1.2.0"))
        assertFalse(validGitRefName("release..bad"))
        assertFalse(validGitRefName("foo//bar"))
        assertFalse(validGitRefName("/main"))
        assertFalse(validGitRefName("main.lock"))
        assertFalse(validGitRefName("hello world"))
        assertFalse(validGitRefName(""))
    }

    @Test fun anonymousPinnedDiscoveryNeverLeaksOtherProfiles() {
        val item = RepositoryItem(9, "recent", "alice", "", "Kotlin", "main", "", false)
        val missing = missingPinnedRepositories(
            listOf(item), setOf("alice/recent", "alice/older", "bob/private"),
            "alice", signedIn = false
        )
        assertEquals(listOf("alice/older"), missing)
    }

    @Test fun signedInPinnedDiscoveryIsBoundedAndSorted() {
        val result = missingPinnedRepositories(
            emptyList(), setOf("zeta/repo", "alpha/repo", "beta/repo"),
            "alice", signedIn = true, max = 2
        )
        assertEquals(listOf("alpha/repo", "beta/repo"), result)
    }

    @Test fun unknownDoesNotMeanSuccessful() {
        assertNotEquals(CheckStatus.SUCCESS, CheckStatus.UNKNOWN)
    }
}
