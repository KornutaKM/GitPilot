package dev.gitpilot.app.data

enum class CheckStatus { SUCCESS, FAILED, RUNNING, PENDING, UNKNOWN }

data class RepositoryItem(
    val id: Long,
    val name: String,
    val owner: String,
    val description: String,
    val language: String,
    val branch: String,
    val activity: String,
    val starred: Boolean
)

data class BranchItem(
    val name: String,
    val isDefault: Boolean,
    val ahead: Int,
    val behind: Int
)

data class CommitItem(
    val sha: String,
    val subject: String,
    val author: String,
    val time: String,
    val filesChanged: Int,
    val additions: Int,
    val deletions: Int,
    val fullSha: String = sha
)

data class PullRequestItem(
    val number: Int,
    val title: String,
    val repo: String,
    val source: String,
    val target: String,
    val author: String,
    val changes: Int,
    val additions: Int,
    val deletions: Int,
    val check: CheckStatus,
    val requiresReview: Boolean,
    val owner: String = "acme",
    val headSha: String = "",
    val htmlUrl: String = ""
)

data class WorkflowStep(val name: String, val status: CheckStatus, val id: Long = 0)

data class WorkflowRunItem(
    val id: Long,
    val name: String,
    val repo: String,
    val branch: String,
    val age: String,
    val check: CheckStatus,
    val steps: List<WorkflowStep>,
    val logExcerpt: String,
    val owner: String = "acme",
    val htmlUrl: String = ""
)

data class Workspace(
    val repositories: List<RepositoryItem>,
    val pullRequests: List<PullRequestItem>,
    val workflows: List<WorkflowRunItem>,
    val branches: Map<Long, List<BranchItem>>,
    val commits: Map<Long, List<CommitItem>>
)


/** Keep the API's recency order within pinned and unpinned groups. */
/**
 * Parse manual GitHub workflow_dispatch inputs, entered one key=value per line.
 * Keep this independent of Android for deterministic JVM unit tests.
 */
fun parseWorkflowInputs(raw: String): Map<String, String> {
    val lines = raw.lines().filter { it.isNotBlank() }
    require(lines.size <= 10) { "GitHub supports up to 10 workflow inputs." }
    val values = linkedMapOf<String, String>()
    for (line in lines) {
        val equalsAt = line.indexOf('=')
        require(equalsAt > 0) { "Use one key=value pair per line." }
        val key = line.substring(0, equalsAt).trim()
        val value = line.substring(equalsAt + 1).trim()
        require(key.matches(Regex("[A-Za-z_][A-Za-z0-9_-]{0,63}"))) {
            "Invalid input name: " + key.take(40)
        }
        require(value.length <= 1024) { "Each workflow input must be no longer than 1024 characters." }
        require(key !in values) { "Duplicate workflow input name: " + key }
        values[key] = value
    }
    return values
}

fun validGitRefName(value: String): Boolean {
    if (value.isEmpty() || value.length > 120 ||
        !value.matches(Regex("[A-Za-z0-9._/-]+"))) return false
    return !value.startsWith("/") && !value.startsWith(".") &&
        !value.endsWith("/") && !value.endsWith(".") &&
        !value.endsWith(".lock") && !value.contains("//") &&
        !value.contains("..") && !value.contains("/.")
}

fun missingPinnedRepositories(
    recent: List<RepositoryItem>, pinned: Set<String>, username: String,
    signedIn: Boolean, max: Int = 12
): List<String> {
    val recentKeys = recent.map { (it.owner + "/" + it.name).lowercase() }.toSet()
    return pinned.asSequence().filter { key ->
        key !in recentKeys && key.count { ch -> ch == '/' } == 1 &&
            (signedIn || key.substringBefore('/').equals(username, ignoreCase = true))
    }.sorted().take(max).toList()
}

fun prioritizeRepositories(repositories: List<RepositoryItem>): List<RepositoryItem> =
    repositories.sortedWith(compareByDescending { it.starred })

/** Deduplicate by GitHub's immutable repository ID across the pinned and paged result sets. */
/** Bound manual pagination to five pages and only offer it when GitHub returns a full page. */
fun hasAnotherRepositoryPage(received: Int, pageSize: Int, page: Int): Boolean =
    page in 1..4 && received == pageSize

fun mergeRepositoryPages(
    existing: List<RepositoryItem>, additional: List<RepositoryItem>
): List<RepositoryItem> = prioritizeRepositories((existing + additional).distinctBy { it.id })


interface WorkspaceRepository {
    fun snapshot(): Workspace
}

object DemoWorkspaceRepository : WorkspaceRepository {
    override fun snapshot() = Workspace(
        repositories = listOf(
            RepositoryItem(1, "backend-api", "acme", "API services and jobs", "Kotlin", "main", "CI failed 8m ago", true),
            RepositoryItem(2, "mobile-app", "acme", "Android client", "Kotlin", "develop", "PR awaiting review", true),
            RepositoryItem(3, "web-dashboard", "acme", "Web administration", "TypeScript", "develop", "4 recent commits", true),
            RepositoryItem(4, "documentation", "acme", "Product documentation", "Markdown", "main", "Up to date", false)
        ),
        pullRequests = listOf(
            PullRequestItem(142, "Fix authentication flow", "backend-api", "feature/auth", "develop", "alex", 5, 82, 24, CheckStatus.SUCCESS, true),
            PullRequestItem(87, "Update checkout component", "web-dashboard", "feature/checkout", "develop", "morgan", 3, 41, 18, CheckStatus.FAILED, true),
            PullRequestItem(121, "Refactor settings navigation", "mobile-app", "feature/settings", "develop", "sam", 8, 205, 114, CheckStatus.RUNNING, false)
        ),
        workflows = listOf(
            WorkflowRunItem(
                248, "Deploy production", "backend-api", "main", "8m ago", CheckStatus.FAILED,
                listOf(WorkflowStep("Build", CheckStatus.SUCCESS), WorkflowStep("Unit tests", CheckStatus.SUCCESS), WorkflowStep("Deploy", CheckStatus.FAILED)),
                "Error: deployment step returned exit code 1\nUnable to publish release artifact."
            ),
            WorkflowRunItem(
                247, "Android CI", "mobile-app", "develop", "18m ago", CheckStatus.RUNNING,
                listOf(WorkflowStep("Compile", CheckStatus.SUCCESS), WorkflowStep("Unit tests", CheckStatus.RUNNING)),
                "Unit tests are currently running."
            ),
            WorkflowRunItem(
                246, "Frontend CI", "web-dashboard", "develop", "22m ago", CheckStatus.SUCCESS,
                listOf(WorkflowStep("Build", CheckStatus.SUCCESS), WorkflowStep("Tests", CheckStatus.SUCCESS)),
                "Build completed successfully."
            )
        ),
        branches = mapOf(
            1L to listOf(BranchItem("main", true, 0, 0), BranchItem("develop", false, 12, 0), BranchItem("feature/auth", false, 2, 1)),
            2L to listOf(BranchItem("main", true, 0, 0), BranchItem("develop", false, 7, 0), BranchItem("feature/settings", false, 3, 0)),
            3L to listOf(BranchItem("main", true, 0, 0), BranchItem("develop", false, 4, 0), BranchItem("feature/checkout", false, 6, 1)),
            4L to listOf(BranchItem("main", true, 0, 0))
        ),
        commits = mapOf(
            1L to listOf(
                CommitItem("c82af18", "fix: refresh access token", "alex", "12m ago", 3, 28, 9),
                CommitItem("90e6c31", "test: add authentication coverage", "alex", "1h ago", 2, 57, 4),
                CommitItem("6c1d8ae", "chore: update dependencies", "sam", "Yesterday", 4, 17, 12)
            ),
            2L to listOf(
                CommitItem("b6a92e1", "refactor: settings navigation", "sam", "28m ago", 8, 205, 114),
                CommitItem("2dd8a81", "feat: add account settings", "sam", "Yesterday", 4, 72, 11)
            ),
            3L to listOf(
                CommitItem("ec390fd", "fix: order totals", "morgan", "42m ago", 2, 19, 6),
                CommitItem("a30fe1d", "test: checkout flow", "morgan", "1h ago", 3, 41, 8)
            ),
            4L to listOf(CommitItem("f92c0da", "docs: update onboarding", "morgan", "2d ago", 2, 25, 3))
        )
    )
}
