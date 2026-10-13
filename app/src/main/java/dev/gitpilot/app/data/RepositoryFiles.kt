package dev.gitpilot.app.data

enum class GitHubEntryType { DIRECTORY, FILE, SUBMODULE, OTHER }

data class GitHubFileEntry(
    val name: String,
    val path: String,
    val type: GitHubEntryType,
    val sizeBytes: Long,
    val htmlUrl: String
)

data class GitHubFilePreview(
    val name: String,
    val path: String,
    val text: String?,
    val message: String?,
    val htmlUrl: String,
    val blobSha: String = ""
)

/** Keys must include account/repository, branch and path to prevent cross-branch cache confusion. */
fun repositoryPathKey(repo: RepositoryItem, branch: String, path: String): String =
    repo.owner + "/" + repo.name + "@" + branch + ":" + path

fun parentDirectory(path: String): String =
    path.substringBeforeLast("/", missingDelimiterValue = "")

fun validateRepositoryPath(path: String): String {
    require(path.length <= 1024) { "Path is too long." }
    require(path.isEmpty() || path.split("/").all { component ->
        component.isNotBlank() && component != "." && component != ".." &&
            !component.contains('\\') && !component.contains('\u0000')
    }) { "Invalid repository path." }
    return path
}

/** UI preference order: folders first, then files, alphabetical within each group. */
fun sortDirectoryEntries(entries: List<GitHubFileEntry>): List<GitHubFileEntry> =
    entries.sortedWith(compareBy<GitHubFileEntry> { it.type != GitHubEntryType.DIRECTORY }
        .thenBy { it.name.lowercase() })


/**
 * GitHub Contents API updates exactly one existing file using its previous blob SHA.
 * Reject partial previews, unchanged content, malformed SHAs and overlarge payloads.
 */
fun validateFileCommit(
    originalText: String,
    changedText: String,
    message: String,
    blobSha: String
): String {
    val clean = message.trim()
    require(clean.isNotBlank()) { "Commit message is required." }
    require(clean.length <= 180) { "Commit message must be at most 180 characters." }
    require(blobSha.matches(Regex("[0-9a-fA-F]{40}"))) { "Missing GitHub file SHA." }
    require(originalText.length <= 32_000) { "This file is too large for editing." }
    require(changedText != originalText) { "No file changes to commit." }
    require(changedText.toByteArray(Charsets.UTF_8).size <= 96_000) {
        "Edited file exceeds the 96 KB limit."
    }
    return clean
}
