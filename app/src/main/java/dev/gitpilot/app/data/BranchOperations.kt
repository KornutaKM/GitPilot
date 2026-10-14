package dev.gitpilot.app.data

/** GitHub compare result relative to the selected repository's default branch. */
data class BranchComparison(
    val base: String,
    val head: String,
    val status: String,
    val aheadBy: Int,
    val behindBy: Int,
    val changedFiles: List<PullRequestFile>,
    val htmlUrl: String
) {
    val canOpenPullRequest: Boolean
        get() = aheadBy > 0 && base != head
}

/**
 * Checks PR draft input before submitting any GitHub mutation.
 * GitHub remains authoritative about permissions, required base and merge restrictions.
 */
fun validatedPullRequestDraft(title: String, body: String): Pair<String, String> {
    val cleanTitle = title.trim()
    val cleanBody = body.trim()
    require(cleanTitle.isNotBlank()) { "Add a pull request title." }
    require(cleanTitle.length <= 200) { "Title must be 200 characters or fewer." }
    require(cleanBody.length <= 10_000) { "Description must be 10,000 characters or fewer." }
    return cleanTitle to cleanBody
}
