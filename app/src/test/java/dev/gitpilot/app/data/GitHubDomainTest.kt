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

    @Test fun signedLogRedirectsRejectAlternateOriginsAndCredentials() {
        assertTrue(isSafeJobLogURL("https://pipelines.actions.githubusercontent.com/log.txt"))
        assertTrue(isSafeJobLogURL("https://builds.blob.core.windows.net:443/archive"))
        assertFalse(isSafeJobLogURL("http://pipelines.actions.githubusercontent.com/log.txt"))
        assertFalse(isSafeJobLogURL("https://pipelines.actions.githubusercontent.com:8443/log"))
        assertFalse(isSafeJobLogURL("https://user:secret@pipelines.actions.githubusercontent.com/log"))
        assertFalse(isSafeJobLogURL("https://pipelines.actions.githubusercontent.com/log#fragment"))
        assertFalse(isSafeJobLogURL("https://pipelines.actions.githubusercontent.com.evil.test/log"))
    }

    @Test fun restResponseReaderEnforcesByteLimit() {
        assertEquals("ok", readBoundedGitHubBody("ok".byteInputStream(), maxBytes = 2))
        val tooLarge = runCatching {
            readBoundedGitHubBody("oversized".byteInputStream(), maxBytes = 3)
        }.exceptionOrNull()
        assertTrue(tooLarge is java.io.IOException)
        val invalidLimit = runCatching {
            readBoundedGitHubBody("x".byteInputStream(), maxBytes = 0)
        }.exceptionOrNull()
        assertTrue(invalidLimit is IllegalArgumentException)
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

    @Test fun oauthCredentialsRejectMalformedAndOversizedTokens() {
        assertEquals("ghu_sample", checkedOAuthToken("ghu_sample", "access token"))
        assertEquals(null, checkedOAuthToken(null, "refresh token", required = false))
        assertEquals(null, checkedOAuthToken("null", "refresh token", required = false))
        assertTrue(runCatching { checkedOAuthToken("", "access token") }.exceptionOrNull() is java.io.IOException)
        assertTrue(runCatching { checkedOAuthToken("ghu bad", "access token") }.exceptionOrNull() is java.io.IOException)
        assertTrue(runCatching { checkedOAuthToken("ghu\nbad", "access token") }.exceptionOrNull() is java.io.IOException)
        assertTrue(runCatching { checkedOAuthToken("x".repeat(4097), "access token") }.exceptionOrNull() is java.io.IOException)
        assertEquals("x".repeat(4096), checkedOAuthToken("x".repeat(4096), "access token"))
    }

    @Test fun deviceCodeAndOAuthResultDoNotPrintSecrets() {
        val device = GitHubDeviceCode("sensitive-device-code", "sensitive-user-code",
            "https://github.com/login/device", 900, 5)
        assertFalse(device.toString().contains("sensitive-device-code"))
        assertFalse(device.toString().contains("sensitive-user-code"))
        val result = PollResult.Authorized("sensitive-access", 3600, "sensitive-refresh", 7200)
        assertFalse(result.toString().contains("sensitive-access"))
        assertFalse(result.toString().contains("sensitive-refresh"))
        assertTrue(result.toString().contains("<redacted>"))
    }

    @Test fun permanentOAuthFailuresAreDistinguishedFromTemporaryFailures() {
        assertTrue(isPermanentRefreshFailure("bad_refresh_token"))
        assertTrue(isPermanentRefreshFailure("invalid_grant"))
        assertTrue(isPermanentRefreshFailure("expired_token"))
        assertFalse(isPermanentRefreshFailure("temporarily_unavailable"))
        assertFalse(isPermanentRefreshFailure("authorization_pending"))
        assertFalse(GitHubOAuthException("invalid_grant").message.orEmpty().contains("token-value"))
    }

    @Test fun parallelWorkspaceAppendDoesNotLoseResults() {
        val entries = synchronizedWorkspaceList<Int>()
        val workers = (0 until 8).map { worker ->
            Thread { repeat(500) { entries.add(worker * 500 + it) } }
        }
        workers.forEach { it.start() }
        workers.forEach { it.join() }
        assertEquals(4_000, entries.size)
        assertEquals(4_000, entries.toSet().size)
    }
}
