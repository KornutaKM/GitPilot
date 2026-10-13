package dev.gitpilot.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoWorkspaceRepositoryTest {
    @Test fun demoDataHasValidCrossReferences() {
        val state = DemoWorkspaceRepository.snapshot()
        val repositoryNames = state.repositories.map { it.name }.toSet()
        assertTrue(state.pullRequests.all { it.repo in repositoryNames })
        assertTrue(state.workflows.all { it.repo in repositoryNames })
        assertEquals(state.repositories.size, state.branches.size)
        assertEquals(state.repositories.size, state.commits.size)
    }

    @Test fun failuresAreVisibleForAttentionQueue() {
        val state = DemoWorkspaceRepository.snapshot()
        assertTrue(state.workflows.any { it.check == CheckStatus.FAILED })
        assertTrue(state.pullRequests.any { it.requiresReview })
    }
}
