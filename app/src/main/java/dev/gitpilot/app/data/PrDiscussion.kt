package dev.gitpilot.app.data

/** A GitHub issue conversation comment or inline pull-request review comment. */
enum class DiscussionKind { CONVERSATION, INLINE_REVIEW }

data class DiscussionEntry(
    val id: Long,
    val kind: DiscussionKind,
    val author: String,
    val body: String,
    val createdAt: String,
    val htmlUrl: String,
    val path: String? = null,
    val line: Int? = null
)

/** The PR comment API creates public GitHub comments; reject empty and unbounded submissions. */
fun validateDiscussionDraft(raw: String): String {
    val value = raw.trim()
    require(value.isNotBlank()) { "Enter a comment before submitting." }
    require(value.length <= 10_000) { "Comment must be 10,000 characters or fewer." }
    return value
}

/** Consistent chronological order across issue comments and inline review comments. */
fun combineDiscussion(
    conversation: List<DiscussionEntry>,
    inline: List<DiscussionEntry>
): List<DiscussionEntry> = (conversation + inline)
    .sortedWith(compareBy<DiscussionEntry> { it.createdAt }.thenBy { it.id })
