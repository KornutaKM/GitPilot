package dev.gitpilot.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class GitHubApiException(val statusCode: Int, message: String, val rateLimited: Boolean = false) : IOException(message)

private fun enc(part: String): String = URLEncoder.encode(part, "UTF-8").replace("+", "%20")

/** Only HTTPS signed log-download hosts used by GitHub Actions are eligible. */
fun isSafeJobLogHost(host: String): Boolean {
    val normalized = host.lowercase()
    return normalized.endsWith(".actions.githubusercontent.com") ||
        normalized.endsWith(".blob.core.windows.net")
}

class GitHubHttp {
    suspend fun get(path: String, token: String? = null): String =
        exchange("https://api.github.com" + path, "GET", token)

    suspend fun post(path: String, token: String, json: JSONObject? = null): String =
        exchange("https://api.github.com" + path, "POST", token, json?.toString() ?: "{}")

    suspend fun put(path: String, token: String, json: JSONObject): String =
        exchange("https://api.github.com" + path, "PUT", token, json.toString())

    /**
     * GitHub responds with a short-lived signed URL for job logs.
     * The GitHub bearer token is sent ONLY to api.github.com, never to that URL.
     */
    suspend fun jobLog(path: String, token: String?): String = withContext(Dispatchers.IO) {
        val first = URL("https://api.github.com" + path).openConnection() as HttpURLConnection
        first.instanceFollowRedirects = false
        first.connectTimeout = 15000
        first.readTimeout = 20000
        first.setRequestProperty("Accept", "application/vnd.github+json")
        first.setRequestProperty("User-Agent", "GitPilot-Android")
        if (!token.isNullOrBlank()) first.setRequestProperty("Authorization", "Bearer " + token)
        try {
            val status = first.responseCode
            if (status in 200..299) {
                return@withContext tailOfLog(first)
            }
            if (status !in 300..399) throw GitHubApiException(status, "Job logs unavailable: GitHub HTTP " + status)
            val location = first.getHeaderField("Location") ?: throw IOException("Missing job log redirect")
            val redirect = URL(location)
            if (redirect.protocol != "https" || !isSafeJobLogHost(redirect.host)) {
                throw IOException("Job log redirect host is not trusted. Open logs on GitHub instead.")
            }
            val second = redirect.openConnection() as HttpURLConnection
            second.instanceFollowRedirects = false
            second.connectTimeout = 15000
            second.readTimeout = 30000
            try {
                if (second.responseCode != 200) throw IOException("Job log download HTTP " + second.responseCode)
                tailOfLog(second)
            } finally {
                second.disconnect()
            }
        } finally {
            first.disconnect()
        }
    }

    private fun tailOfLog(connection: HttpURLConnection): String {
        val capacity = 65536
        val buffer = ByteArray(capacity)
        val chunk = ByteArray(8192)
        var cursor = 0
        var count = 0L
        var downloadLimitReached = false
        connection.inputStream.use { input ->
            while (count < 5_000_000L) {
                val read = input.read(chunk)
                if (read <= 0) break
                for (i in 0 until read) {
                    buffer[cursor] = chunk[i]
                    cursor = (cursor + 1) % capacity
                }
                count += read
            }
            downloadLimitReached = count >= 5_000_000L
        }
        val size = minOf(count, capacity.toLong()).toInt()
        val output = ByteArray(size)
        val start = if (count >= capacity) cursor else 0
        for (i in 0 until size) output[i] = buffer[(start + i) % capacity]
        val prefix = if (count > capacity) "[Showing recent " + capacity + " bytes of job output]\n" else ""
        val warning = if (downloadLimitReached) "\n[Preview stopped at 5 MB; open GitHub for full logs.]" else ""
        return prefix + String(output, Charsets.UTF_8).takeLast(30000) + warning
    }

    suspend fun oauth(path: String, fields: Map<String, String>): JSONObject {
        val form = fields.entries.joinToString("&") { enc(it.key) + "=" + enc(it.value) }
        return JSONObject(exchange("https://github.com" + path, "POST", null, form, true))
    }

    private suspend fun exchange(
        endpoint: String, method: String, token: String?,
        body: String? = null, form: Boolean = false
    ): String = withContext(Dispatchers.IO) {
        val conn = URL(endpoint).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 15000
            conn.readTimeout = 20000
            conn.setRequestProperty("Accept", if (form) "application/json" else "application/vnd.github+json")
            conn.setRequestProperty("User-Agent", "GitPilot-Android")
            if (!form) conn.setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
            if (!token.isNullOrBlank()) conn.setRequestProperty("Authorization", "Bearer " + token)
            if (body != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", if (form) "application/x-www-form-urlencoded" else "application/json")
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val result = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                val reason = runCatching { JSONObject(result).optString("message") }.getOrNull().orEmpty()
                val limited = code == 429 || (code == 403 &&
                    conn.getHeaderField("X-RateLimit-Remaining") == "0")
                val explanation = if (limited) "GitHub API rate limit reached. Retry after the limit resets."
                    else "GitHub HTTP " + code + if (reason.isBlank()) "" else ": " + reason.take(160)
                throw GitHubApiException(code, explanation, limited)
            }
            result
        } finally {
            conn.disconnect()
        }
    }
}

data class GitHubDeviceCode(
    val deviceCode: String, val userCode: String, val verificationUri: String,
    val expiresInSeconds: Long, val intervalSeconds: Long
)
sealed interface PollResult {
    data object Pending : PollResult
    data class SlowDown(val intervalSeconds: Long) : PollResult
    data class Authorized(
        val accessToken: String, val expiresInSeconds: Long?,
        val refreshToken: String? = null, val refreshExpiresInSeconds: Long? = null
    ) : PollResult
}

class GitHubDeviceAuth(private val http: GitHubHttp = GitHubHttp()) {
    suspend fun begin(clientId: String): GitHubDeviceCode {
        val json = http.oauth("/login/device/code", mapOf("client_id" to clientId))
        if (json.has("error")) throw IOException(json.optString("error_description", json.optString("error")))
        return GitHubDeviceCode(
            json.getString("device_code"), json.getString("user_code"),
            json.getString("verification_uri"), json.optLong("expires_in", 900),
            json.optLong("interval", 5).coerceAtLeast(5)
        )
    }

    suspend fun poll(clientId: String, code: GitHubDeviceCode): PollResult {
        val json = http.oauth("/login/oauth/access_token", mapOf(
            "client_id" to clientId,
            "device_code" to code.deviceCode,
            "grant_type" to "urn:ietf:params:oauth:grant-type:device_code"
        ))
        return when (json.optString("error")) {
            "" -> {
                val token = json.optString("access_token")
                if (token.isBlank()) throw IOException("GitHub did not return an access token")
                PollResult.Authorized(
                    token,
                    if (json.has("expires_in")) json.optLong("expires_in") else null,
                    json.optString("refresh_token").takeIf { it.isNotBlank() },
                    if (json.has("refresh_token_expires_in")) json.optLong("refresh_token_expires_in") else null
                )
            }
            "authorization_pending" -> PollResult.Pending
            "slow_down" -> PollResult.SlowDown(json.optLong("interval", code.intervalSeconds + 5))
            else -> throw IOException(json.optString("error_description", json.optString("error")))
        }
    }
    suspend fun renew(clientId: String, refreshToken: String): PollResult.Authorized {
        val json = http.oauth("/login/oauth/access_token", mapOf(
            "client_id" to clientId,
            "grant_type" to "refresh_token",
            "refresh_token" to refreshToken
        ))
        val error = json.optString("error")
        if (error.isNotBlank()) {
            throw IOException(json.optString("error_description", error))
        }
        val token = json.optString("access_token")
        if (token.isBlank()) throw IOException("GitHub did not provide renewed access credentials")
        return PollResult.Authorized(
            token,
            if (json.has("expires_in")) json.optLong("expires_in") else null,
            json.optString("refresh_token").takeIf { it.isNotBlank() },
            if (json.has("refresh_token_expires_in")) json.optLong("refresh_token_expires_in") else null
        )
    }

}

data class WorkflowDefinition(val id: Long, val name: String, val active: Boolean)

data class WorkspaceLoadResult(val workspace: Workspace, val warnings: List<String>)

class LiveGitHubWorkspace(private val http: GitHubHttp = GitHubHttp()) {
    suspend fun load(username: String, token: String?, pinned: Set<String> = emptySet()): WorkspaceLoadResult {
        val signedIn = !token.isNullOrBlank()
        val route = if (signedIn) {
            "/user/repos?sort=pushed&affiliation=owner%2Ccollaborator%2Corganization_member&per_page=20"
        } else {
            "/users/" + enc(username) + "/repos?sort=pushed&per_page=12"
        }
        val repos = JSONArray(http.get(route, token))
        val entries = (0 until repos.length()).map { repos.getJSONObject(it) }
        val warnings = mutableListOf<String>()
        val recent = entries.map { json ->
            val item = repositoryFromJson(json)
            item.copy(starred = (item.owner + "/" + item.name).lowercase() in pinned)
        }
        // Pinning a project must not lose it just because newer repositories
        // push it beyond the first API page. Fetch missing pins individually.
        val missingPinned = missingPinnedRepositories(recent, pinned, username, signedIn)
        val pinnedExtras = mutableListOf<RepositoryItem>()
        for (key in missingPinned) {
            val owner = key.substringBefore('/')
            val name = key.substringAfter('/')
            try {
                val response = JSONObject(http.get("/repos/" + enc(owner) + "/" + enc(name), token))
                pinnedExtras += repositoryFromJson(response).copy(starred = true)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += "Pinned " + key + ": " + e.message.orEmpty()
            }
        }
        val all = prioritizeRepositories((recent + pinnedExtras).distinctBy { it.id })
        val branches = mutableMapOf<Long, List<BranchItem>>()
        val commits = mutableMapOf<Long, List<CommitItem>>()
        val prs = mutableListOf<PullRequestItem>()
        val runs = mutableListOf<WorkflowRunItem>()
        
        // Limit requests in anonymous mode (60 requests/hour shared by IP).
        val monitored = all.take(if (signedIn) 8 else 4)
        // At most three repositories are fetched simultaneously to keep the mobile
        // dashboard responsive without overwhelming GitHub or the user's connection.
        coroutineScope {
            val gate = Semaphore(3)
            monitored.map { repo -> async {
                gate.withPermit {
            val root = "/repos/" + enc(repo.owner) + "/" + enc(repo.name)
            try {
                val response = JSONArray(http.get(root + "/branches?per_page=30", token))
                branches[repo.id] = (0 until response.length()).map { i ->
                    val item = response.getJSONObject(i)
                    BranchItem(item.getString("name"), item.getString("name") == repo.branch, -1, -1)
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += repo.name + " branches: " + e.message.orEmpty()
            }
            try {
                val response = JSONArray(http.get(root + "/commits?per_page=12", token))
                commits[repo.id] = (0 until response.length()).map { i ->
                    val item = response.getJSONObject(i)
                    val details = item.getJSONObject("commit")
                    val author = item.optJSONObject("author")?.optString("login")
                        .orEmpty().ifBlank { details.optJSONObject("author")?.optString("name").orEmpty() }
                    val sha = item.getString("sha")
                    CommitItem(sha.take(8), details.optString("message").lineSequence().firstOrNull().orEmpty(),
                        author, details.optJSONObject("author")?.optString("date").orEmpty().take(10), -1, 0, 0, sha)
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += repo.name + " commits: " + e.message.orEmpty()
            }
            try {
                val response = JSONArray(http.get(root + "/pulls?state=open&per_page=20", token))
                for (i in 0 until response.length()) {
                    val item = response.getJSONObject(i)
                    val head = item.getJSONObject("head")
                    val base = item.getJSONObject("base")
                    val requested = item.optJSONArray("requested_reviewers") ?: JSONArray()
                    val reviewForViewer = signedIn && (0 until requested.length()).any { j ->
                        requested.getJSONObject(j).optString("login").equals(username, ignoreCase = true)
                    }
                    prs += PullRequestItem(item.getInt("number"), item.optString("title"), repo.name,
                        head.optString("ref"), base.optString("ref"),
                        item.optJSONObject("user")?.optString("login").orEmpty(),
                        item.optInt("changed_files", -1), item.optInt("additions", -1),
                        item.optInt("deletions", -1), CheckStatus.UNKNOWN,
                        reviewForViewer, repo.owner, head.optString("sha"), item.optString("html_url"))
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += repo.name + " PRs: " + e.message.orEmpty()
            }
            try {
                val response = JSONObject(http.get(root + "/actions/runs?per_page=12", token))
                    .optJSONArray("workflow_runs") ?: JSONArray()
                for (i in 0 until response.length()) {
                    val item = response.getJSONObject(i)
                    val conclusion = item.optString("conclusion")
                    val status = item.optString("status")
                    runs += WorkflowRunItem(item.getLong("id"), item.optString("name"),
                        repo.name, item.optString("head_branch"),
                        item.optString("updated_at").take(10),
                        parseStatus(status, conclusion), emptyList(),
                        "Open the workflow in GitHub to inspect the full logs.",
                        repo.owner, item.optString("html_url"))
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += repo.name + " Actions: " + e.message.orEmpty()
            }
                }
            } }.awaitAll()
        }
        // Preserve selected-repository priority despite out-of-order network responses.
        val order = monitored.withIndex().associate { it.value.owner.lowercase() + "/" +
            it.value.name.lowercase() to it.index }
        prs.sortWith(compareBy({ order[it.owner.lowercase() + "/" + it.repo.lowercase()] ?: Int.MAX_VALUE }, { it.number }))
        // Limit per-PR checks requests; lack of access is not equivalent to passed CI.
        val maxChecks = if (signedIn) 12 else 5
        for (index in 0 until minOf(prs.size, maxChecks)) {
            val pr = prs[index]
            if (pr.headSha.isBlank()) continue
            val path = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo) +
                "/commits/" + enc(pr.headSha) + "/check-runs?per_page=100"
            try {
                val checks = JSONObject(http.get(path, token)).optJSONArray("check_runs") ?: JSONArray()
                if (checks.length() == 0) continue
                val all = (0 until checks.length()).map { checks.getJSONObject(it) }
                val status = when {
                    all.any { it.optString("conclusion") in listOf("failure", "timed_out", "cancelled", "action_required") } ->
                        CheckStatus.FAILED
                    all.any { it.optString("status") != "completed" } ->
                        CheckStatus.RUNNING
                    all.all { it.optString("conclusion") == "success" || it.optString("conclusion") == "skipped" } ->
                        CheckStatus.SUCCESS
                    else -> CheckStatus.UNKNOWN
                }
                prs[index] = pr.copy(check = status)
            } catch (e: GitHubApiException) {
                warnings += "Checks: " + e.message.orEmpty()
                if (e.rateLimited || e.statusCode == 401) throw e
                if (e.statusCode == 403) break
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (e is GitHubApiException && (e.rateLimited || e.statusCode == 401)) throw e
                warnings += "Checks: " + e.message.orEmpty()
            }
        }
        return WorkspaceLoadResult(
            Workspace(all, prs, runs.sortedByDescending { it.id }, branches, commits),
            warnings
        )
    }

    /** Load the first 50 issue conversation and 50 inline review comments. */
    suspend fun pullDiscussion(pr: PullRequestItem, token: String?): List<DiscussionEntry> {
        val root = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo)
        val issue = JSONArray(http.get(root + "/issues/" + pr.number + "/comments?per_page=50", token))
        val review = JSONArray(http.get(root + "/pulls/" + pr.number + "/comments?per_page=50", token))
        val conversation = (0 until issue.length()).map { index ->
            val value = issue.getJSONObject(index)
            DiscussionEntry(
                id = value.getLong("id"),
                kind = DiscussionKind.CONVERSATION,
                author = value.optJSONObject("user")?.optString("login").orEmpty(),
                body = value.optString("body").takeIf { it != "null" }.orEmpty(),
                createdAt = value.optString("created_at"),
                htmlUrl = value.optString("html_url")
            )
        }
        val inline = (0 until review.length()).map { index ->
            val value = review.getJSONObject(index)
            DiscussionEntry(
                id = value.getLong("id"),
                kind = DiscussionKind.INLINE_REVIEW,
                author = value.optJSONObject("user")?.optString("login").orEmpty(),
                body = value.optString("body").takeIf { it != "null" }.orEmpty(),
                createdAt = value.optString("created_at"),
                htmlUrl = value.optString("html_url"),
                path = value.optString("path").takeIf { it.isNotBlank() && it != "null" },
                line = if (value.isNull("line")) null else value.optInt("line")
            )
        }
        return combineDiscussion(conversation, inline)
    }

    suspend fun postPullComment(pr: PullRequestItem, token: String, rawBody: String) {
        val root = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo)
        http.post(root + "/issues/" + pr.number + "/comments", token,
            JSONObject().put("body", validateDiscussionDraft(rawBody)))
    }

    suspend fun pullFiles(pr: PullRequestItem, token: String?): List<PullRequestFile> {
        val path = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo) +
            "/pulls/" + pr.number + "/files?per_page=30"
        val array = JSONArray(http.get(path, token))
        return (0 until array.length()).map {
            val file = array.getJSONObject(it)
            PullRequestFile(file.optString("filename"),
                file.optString("status"), file.optString("patch", "Diff unavailable for this file").take(12000))
        }
    }

    suspend fun workflowJobs(run: WorkflowRunItem, token: String?): List<WorkflowStep> {
        val path = "/repos/" + enc(run.owner) + "/" + enc(run.repo) +
            "/actions/runs/" + run.id + "/jobs?per_page=100"
        val array = JSONObject(http.get(path, token)).optJSONArray("jobs") ?: JSONArray()
        return (0 until array.length()).map {
            val item = array.getJSONObject(it)
            WorkflowStep(item.optString("name"), parseStatus(item.optString("status"), item.optString("conclusion")), item.optLong("id"))
        }
    }

    suspend fun compareBranches(repo: RepositoryItem, branch: String, token: String?): BranchComparison {
        require(validGitRefName(branch)) { "Invalid source branch." }
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) +
            "/compare/" + enc(repo.branch) + "..." + enc(branch) + "?per_page=50"
        val json = JSONObject(http.get(path, token))
        val files = json.optJSONArray("files") ?: JSONArray()
        val patches = (0 until files.length()).map { index ->
            val item = files.getJSONObject(index)
            PullRequestFile(item.optString("filename"), item.optString("status"),
                item.optString("patch", "Diff unavailable for this file").take(12_000))
        }
        return BranchComparison(
            repo.branch, branch, json.optString("status"),
            json.optInt("ahead_by"), json.optInt("behind_by"),
            patches, json.optString("html_url")
        )
    }

    suspend fun createPullRequest(
        repo: RepositoryItem, branch: String, title: String, body: String, token: String
    ) {
        require(validGitRefName(branch) && branch != repo.branch) {
            "Choose a non-default source branch."
        }
        val validated = validatedPullRequestDraft(title, body)
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) + "/pulls"
        http.post(path, token, JSONObject()
            .put("title", validated.first)
            .put("body", validated.second)
            .put("base", repo.branch)
            .put("head", branch)
        )
    }

    suspend fun commitsForBranch(repo: RepositoryItem, branch: String, token: String?): List<CommitItem> {
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) +
            "/commits?sha=" + enc(branch) + "&per_page=12"
        val array = JSONArray(http.get(path, token))
        return (0 until array.length()).map { i ->
            val item = array.getJSONObject(i)
            val details = item.getJSONObject("commit")
            val sha = item.getString("sha")
            val author = item.optJSONObject("author")?.optString("login").orEmpty()
                .ifBlank { details.optJSONObject("author")?.optString("name").orEmpty() }
            CommitItem(sha.take(8), details.optString("message").lineSequence().firstOrNull().orEmpty(),
                author, details.optJSONObject("author")?.optString("date").orEmpty().take(10),
                -1, 0, 0, sha)
        }
    }

    suspend fun commitFiles(repo: RepositoryItem, commit: CommitItem, token: String?): List<PullRequestFile> {
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) +
            "/commits/" + enc(commit.fullSha)
        val array = JSONObject(http.get(path, token)).optJSONArray("files") ?: JSONArray()
        return (0 until array.length()).map { i ->
            val file = array.getJSONObject(i)
            PullRequestFile(file.optString("filename"), file.optString("status"),
                file.optString("patch", "Diff unavailable for this file").take(12000))
        }
    }

    suspend fun viewerLogin(token: String): String =
        JSONObject(http.get("/user", token)).getString("login")

    suspend fun approve(pr: PullRequestItem, token: String, message: String, event: String) {
        val path = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo) + "/pulls/" + pr.number + "/reviews"
        http.post(path, token, JSONObject().put("event", event).put("body", message))
    }

    suspend fun merge(pr: PullRequestItem, token: String) {
        val path = "/repos/" + enc(pr.owner) + "/" + enc(pr.repo) + "/pulls/" + pr.number + "/merge"
        http.put(path, token, JSONObject().put("sha", pr.headSha).put("merge_method", "squash"))
    }

    suspend fun fetchJobLog(run: WorkflowRunItem, step: WorkflowStep, token: String?): String {
        if (step.id <= 0) throw IOException("Missing job identifier")
        val path = "/repos/" + enc(run.owner) + "/" + enc(run.repo) +
            "/actions/jobs/" + step.id + "/logs"
        return http.jobLog(path, token)
    }

    suspend fun createBranch(repo: RepositoryItem, sha: String, branch: String, token: String) {
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) + "/git/refs"
        http.post(path, token, JSONObject().put("ref", "refs/heads/" + branch).put("sha", sha))
    }


    suspend fun listWorkflows(repo: RepositoryItem, token: String?): List<WorkflowDefinition> {
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) + "/actions/workflows?per_page=100"
        val response = JSONObject(http.get(path, token)).optJSONArray("workflows") ?: JSONArray()
        return (0 until response.length()).map { index ->
            val item = response.getJSONObject(index)
            WorkflowDefinition(item.getLong("id"), item.optString("name"), item.optString("state") == "active")
        }.filter { it.active }
    }

    suspend fun dispatchWorkflow(
        repo: RepositoryItem, workflowId: Long, ref: String, token: String,
        inputs: Map<String, String>
    ) {
        require(workflowId > 0) { "Invalid workflow" }
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) +
            "/actions/workflows/" + workflowId + "/dispatches"
        http.post(path, token, JSONObject().put("ref", ref).put("inputs", JSONObject(inputs)))
    }

    suspend fun cancelWorkflowRun(run: WorkflowRunItem, token: String) {
        val path = "/repos/" + enc(run.owner) + "/" + enc(run.repo) +
            "/actions/runs/" + run.id + "/cancel"
        http.post(path, token)
    }

    suspend fun rerunFailed(run: WorkflowRunItem, token: String) {
        val path = "/repos/" + enc(run.owner) + "/" + enc(run.repo) +
            "/actions/runs/" + run.id + "/rerun-failed-jobs"
        http.post(path, token)
    }

    private fun repositoryFromJson(item: JSONObject): RepositoryItem {
        val language = if (item.isNull("language")) "Unknown" else item.optString("language")
        return RepositoryItem(item.getLong("id"), item.optString("name"),
            item.getJSONObject("owner").optString("login"),
            item.optString("description").takeIf { it != "null" }.orEmpty(),
            language, item.optString("default_branch"),
            "Updated " + item.optString("pushed_at").take(10),
            false)
    }

    private fun parseStatus(status: String, conclusion: String): CheckStatus =
        when {
            conclusion == "success" -> CheckStatus.SUCCESS
            conclusion in listOf("failure", "timed_out", "cancelled", "action_required") -> CheckStatus.FAILED
            status in listOf("in_progress", "queued", "requested", "waiting", "pending") -> CheckStatus.RUNNING
            else -> CheckStatus.UNKNOWN
        }
}
