package dev.gitpilot.app.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionRequestPolicyTest {
    @Test fun sameSessionAndWorkspaceGenerationMayApplyResult() {
        assertTrue(isCurrentWorkspaceRequest(4L, 7L, 4L, 7L))
        assertTrue(isCurrentSessionEpoch(4L, 4L))
    }

    @Test fun signedOutSessionRejectsOldDetailResponse() {
        assertFalse(isCurrentWorkspaceRequest(4L, 7L, 5L, 7L))
        assertFalse(isCurrentSessionEpoch(4L, 5L))
    }

    @Test fun refreshedWorkspaceRejectsOldDetailResponseEvenWithinSameAccount() {
        assertFalse(isCurrentWorkspaceRequest(4L, 7L, 4L, 8L))
    }

    @Test fun accountSwitchAndRefreshRejectOldResponse() {
        assertFalse(isCurrentWorkspaceRequest(4L, 7L, 5L, 8L))
    }

    @Test fun older401FromPreviousAccountMustNotInvalidateNewCredentials() {
        // A late HTTP 401 may only invalidate credentials for its own epoch.
        assertFalse(isCurrentSessionEpoch(12L, 13L))
        assertTrue(isCurrentSessionEpoch(13L, 13L))
    }

    @Test fun older401FromPreviousRefreshCannotResetCurrentUi() {
        assertFalse(isCurrentWorkspaceRequest(12L, 100L, 12L, 101L))
        assertFalse(isCurrentWorkspaceRequest(12L, 100L, 13L, 101L))
    }

    @Test fun requestGenerationAndAccountCannotBeInferredFromMatchingOneNumber() {
        assertFalse(isCurrentWorkspaceRequest(8L, 9L, 9L, 8L))
        assertFalse(isCurrentWorkspaceRequest(8L, 9L, 8L, 8L))
        assertFalse(isCurrentWorkspaceRequest(8L, 9L, 9L, 9L))
    }
}
