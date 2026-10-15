package dev.gitpilot.app.data

/**
 * GitHub detail endpoints expose paged results. Stop on a partial page, never
 * scan an unbounded account or silently claim an incomplete first page is all.
 *
 * Fetching is sequential to respect authenticated and anonymous API quotas.
 * Caller cancellation and HTTP failures propagate without returning partial data.
 */
internal suspend fun <T> collectBoundedGitHubPages(
    pageSize: Int,
    maxPages: Int,
    fetchPage: suspend (Int) -> List<T>
): List<T> {
    require(pageSize in 1..100) { "GitHub page size must be 1..100" }
    require(maxPages in 1..5) { "GitHub detail pagination must be 1..5 pages" }

    val combined = ArrayList<T>(pageSize * maxPages)
    for (page in 1..maxPages) {
        val items = fetchPage(page)
        check(items.size <= pageSize) { "GitHub returned more items than the requested page size" }
        combined.addAll(items)
        if (items.size < pageSize) break
    }
    return combined
}

/** Detail APIs have no existing query parameters; reject ambiguous paths. */
internal fun gitHubPagedPath(path: String, pageSize: Int, page: Int): String {
    require(path.startsWith("/") && !path.startsWith("//")) { "Invalid GitHub endpoint" }
    require('?' !in path && '#' !in path && '\n' !in path && '\r' !in path) {
        "GitHub endpoint must not contain a query, fragment, or newline"
    }
    require(pageSize in 1..100) { "Invalid GitHub page size" }
    require(page in 1..5) { "Invalid GitHub page number" }
    return "$path?per_page=$pageSize&page=$page"
}


/**
 * Multiple Compose recompositions must not trigger duplicate costly detail loads.
 * A refresh uses a new generation so an old request cannot block new data.
 */
internal class GitHubDetailRequestGate {
    private val active = mutableSetOf<Pair<Long, String>>()

    @Synchronized
    fun begin(generation: Long, key: String): Boolean =
        active.add(generation to key)

    @Synchronized
    fun finish(generation: Long, key: String) {
        active.remove(generation to key)
    }
}
