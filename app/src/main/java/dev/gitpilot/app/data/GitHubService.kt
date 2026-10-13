package dev.gitpilot.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class GitHubApiException(val statusCode: Int, message: String) : IOException(message)

private fun enc(part: String): String = URLEncoder.encode(part, "UTF-8").replace("+", "%20")

class GitHubHttp {
    suspend fun get(path: String, token: String? = null): String =
        exchange("https://api.github.com" + path, "GET", token)

    suspend fun post(path: String, token: String, json: JSONObject? = null): String =
        exchange("https://api.github.com" + path, "POST", token, json?.toString() ?: "{}")

    suspend fun put(path: String, token: String, json: JSONObject): String =
        exchange("https://api.github.com" + path, "PUT", token, json.toString())

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
                throw GitHubApiException(code, "GitHub HTTP " + code + if (reason.isBlank()) "" else ": " + reason.take(160))
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
    data class Authorized(val accessToken: String, val expiresInSeconds: Long?) : PollResult
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
                PollResult.Authorized(token, if (json.has("expires_in")) json.optLong("expires_in") else null)
            }
            "authorization_pending" -> PollResult.Pending
            "slow_down" -> PollResult.SlowDown(json.optLong("interval", code.intervalSeconds + 5))
            else -> throw IOException(json.optString("error_description", json.optString("error")))
        }
    }
}

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
        val all = prioritizeRepositories(entries.map { json ->
            val item = repositoryFromJson(json)
            item.copy(starred = (item.owner + "/" + item.name).lowercase() in pinned)
        })
        val branches = mutableMapOf<Long, List<BranchItem>>()
        val commits = mutableMapOf<Long, List<CommitItem>>()
        val prs = mutableListOf<PullRequestItem>()
        val runs = mutableListOf<WorkflowRunItem>()
        val warnings = mutableListOf<String>()
        // Limit requests in anonymous mode (60 requests/hour shared by IP).
        val monitored = all.take(if (signedIn) 8 else 4)
        for (repo in monitored) {
            val root = "/repos/" + enc(repo.owner) + "/" + enc(repo.name)
            try {
                val response = JSONArray(http.get(root + "/branches?per_page=30", token))
                branches[repo.id] = (0 until response.length()).map { i ->
                    val item = response.getJSONObject(i)
                    BranchItem(item.getString("name"), item.getString("name") == repo.branch, -1, -1)
                }
            } catch (e: Exception) {
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
                warnings += repo.name + " Actions: " + e.message.orEmpty()
            }
        }
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
                if (e.statusCode == 403 || e.statusCode == 401) break
            } catch (e: Exception) {
                warnings += "Checks: " + e.message.orEmpty()
            }
        }
        return WorkspaceLoadResult(
            Workspace(all, prs, runs.sortedByDescending { it.id }, branches, commits),
            warnings
        )
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
            WorkflowStep(item.optString("name"), parseStatus(item.optString("status"), item.optString("conclusion")))
        }
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

    suspend fun createBranch(repo: RepositoryItem, sha: String, branch: String, token: String) {
        val path = "/repos/" + enc(repo.owner) + "/" + enc(repo.name) + "/git/refs"
        http.post(path, token, JSONObject().put("ref", "refs/heads/" + branch).put("sha", sha))
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
