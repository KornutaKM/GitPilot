package dev.gitpilot.app.data

/**
 * Network responses are account-scoped, and many details are also scoped to a
 * particular workspace refresh. A response from before sign-out, reauthorization
 * or refresh must never repopulate stale/private UI state.
 */
internal fun isCurrentSessionEpoch(requestEpoch: Long, currentEpoch: Long): Boolean =
    requestEpoch == currentEpoch

internal fun isCurrentWorkspaceRequest(
    requestEpoch: Long,
    requestGeneration: Long,
    currentEpoch: Long,
    currentGeneration: Long
): Boolean =
    isCurrentSessionEpoch(requestEpoch, currentEpoch) &&
        requestGeneration == currentGeneration
