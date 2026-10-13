package dev.gitpilot.app.data

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.gitpilot.app.BuildConfig
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.IOException

data class PullRequestFile(val filename: String, val status: String, val patch: String)

data class GitPilotState(
    val workspace: Workspace = Workspace(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
    val loading: Boolean = false,
    val authenticatedAs: String? = null,
    val publicUsername: String = "KornutaKM",
    val error: String? = null,
    val message: String? = null,
    val warnings: List<String> = emptyList(),
    val deviceCode: GitHubDeviceCode? = null,
    val signingIn: Boolean = false,
    val diffs: Map<String, List<PullRequestFile>> = emptyMap(),
    val jobs: Map<Long, List<WorkflowStep>> = emptyMap(),
    val branchCommits: Map<String, List<CommitItem>> = emptyMap(),
    val commitFiles: Map<String, List<PullRequestFile>> = emptyMap(),
    val branchLoading: Boolean = false,
    val detailLoading: Boolean = false
)

class GitPilotViewModel(app: Application) : AndroidViewModel(app) {
    private val preferences = app.getSharedPreferences("gitpilot_preferences", 0)
    private val session = SecureTokenStore(app)
    private val service = LiveGitHubWorkspace()
    private val deviceAuth = GitHubDeviceAuth()
    private val clientId = BuildConfig.GITHUB_CLIENT_ID
    private val mutable = MutableStateFlow(
        GitPilotState(publicUsername = preferences.getString("public_username", "KornutaKM") ?: "KornutaKM")
    )
    val state: StateFlow<GitPilotState> = mutable
    val canSignIn: Boolean get() = clientId.isNotBlank()
    private var refreshJob: Job? = null
    private var signInJob: Job? = null

    init { refresh() }

    fun refresh() {
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            mutable.update { it.copy(loading = true, error = null) }
            try {
                val token = session.read()
                val user = if (token == null) null else service.viewerLogin(token)
                val selected = user ?: mutable.value.publicUsername
                val result = service.load(selected, token, preferences.getStringSet("pinned_repositories", emptySet()).orEmpty().toSet())
                mutable.update {
                    it.copy(workspace = result.workspace, loading = false,
                        authenticatedAs = user, warnings = result.warnings,
                        diffs = emptyMap(), jobs = emptyMap(), branchCommits = emptyMap(),
                        commitFiles = emptyMap(), branchLoading = false, detailLoading = false)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (e is GitHubApiException && e.statusCode == 401) session.clear()
                mutable.update { it.copy(loading = false, error = cleanError(e)) }
            }
        }
    }

    fun togglePin(repo: RepositoryItem) {
        val key = (repo.owner + "/" + repo.name).lowercase()
        val pins = preferences.getStringSet("pinned_repositories", emptySet()).orEmpty().toMutableSet()
        if (key in pins) pins.remove(key) else pins.add(key)
        preferences.edit().putStringSet("pinned_repositories", pins).apply()
        mutable.update { current ->
            val repos = current.workspace.repositories.map { item ->
                item.copy(starred = (item.owner + "/" + item.name).lowercase() in pins)
            }
            current.copy(workspace = current.workspace.copy(repositories = prioritizeRepositories(repos)))
        }
        refresh()
    }

    fun setPublicUsername(input: String) {
        val username = input.trim()
        if (!Regex("^[A-Za-z0-9][A-Za-z0-9-]{0,37}$").matches(username) ||
            username.endsWith("-")) {
            mutable.update { it.copy(error = "Enter a valid GitHub username.") }
            return
        }
        preferences.edit().putString("public_username", username).apply()
        mutable.update { it.copy(publicUsername = username, error = null) }
        if (session.read() == null) refresh()
    }

    fun signIn() {
        if (!canSignIn) {
            mutable.update { it.copy(error = "Configure gitpilot.githubClientId to enable GitHub sign-in.") }
            return
        }
        signInJob?.cancel()
        signInJob = viewModelScope.launch {
            mutable.update { it.copy(signingIn = true, deviceCode = null, error = null) }
            try {
                val code = deviceAuth.begin(clientId)
                mutable.update { it.copy(deviceCode = code) }
                val deadline = System.currentTimeMillis() + code.expiresInSeconds * 1000L
                var interval = code.intervalSeconds
                while (System.currentTimeMillis() < deadline) {
                    delay(interval * 1000L)
                    when (val answer = deviceAuth.poll(clientId, code)) {
                        is PollResult.Pending -> Unit
                        is PollResult.SlowDown -> interval = answer.intervalSeconds.coerceAtLeast(5)
                        is PollResult.Authorized -> {
                            session.save(answer.accessToken, answer.expiresInSeconds)
                            mutable.update { it.copy(deviceCode = null, signingIn = false) }
                            refresh()
                            return@launch
                        }
                    }
                }
                throw IOException("Authorization expired. Please try again.")
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                mutable.update { it.copy(signingIn = false, deviceCode = null, error = cleanError(e)) }
            }
        }
    }

    fun cancelSignIn() {
        signInJob?.cancel()
        mutable.update { it.copy(deviceCode = null, signingIn = false) }
    }

    fun signOut() {
        cancelSignIn()
        session.clear()
        mutable.update { it.copy(authenticatedAs = null, message = "Signed out") }
        refresh()
    }

    fun loadBranchCommits(repo: RepositoryItem, branch: String) {
        val key = branchKey(repo, branch)
        if (mutable.value.branchCommits.containsKey(key)) return
        viewModelScope.launch {
            mutable.update { it.copy(branchLoading = true, error = null) }
            try {
                val commits = service.commitsForBranch(repo, branch, session.read())
                mutable.update { it.copy(branchCommits = it.branchCommits + (key to commits), branchLoading = false) }
            } catch (e: Exception) {
                mutable.update { it.copy(branchLoading = false, error = cleanError(e)) }
            }
        }
    }

    fun loadCommitFiles(repo: RepositoryItem, commit: CommitItem) {
        val key = commitKey(repo, commit)
        if (mutable.value.commitFiles.containsKey(key)) return
        viewModelScope.launch {
            mutable.update { it.copy(detailLoading = true, error = null) }
            try {
                val files = service.commitFiles(repo, commit, session.read())
                mutable.update { it.copy(commitFiles = it.commitFiles + (key to files), detailLoading = false) }
            } catch (e: Exception) {
                mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
            }
        }
    }

    fun loadPullFiles(pr: PullRequestItem) {
        val key = diffKey(pr)
        if (mutable.value.diffs.containsKey(key)) return
        viewModelScope.launch {
            mutable.update { it.copy(detailLoading = true, error = null) }
            try {
                val files = service.pullFiles(pr, session.read())
                mutable.update { it.copy(diffs = it.diffs + (key to files), detailLoading = false) }
            } catch (e: Exception) {
                mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
            }
        }
    }

    fun loadWorkflowJobs(run: WorkflowRunItem) {
        if (mutable.value.jobs.containsKey(run.id)) return
        viewModelScope.launch {
            mutable.update { it.copy(detailLoading = true, error = null) }
            try {
                val jobs = service.workflowJobs(run, session.read())
                mutable.update { it.copy(jobs = it.jobs + (run.id to jobs), detailLoading = false) }
            } catch (e: Exception) {
                mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
            }
        }
    }

    fun createBranch(repo: RepositoryItem, commit: CommitItem, proposedName: String) {
        val branchName = proposedName.trim()
        val valid = branchName.matches(Regex("[A-Za-z0-9._/-]{1,120}")) &&
            !branchName.startsWith(".") && !branchName.startsWith("/") &&
            !branchName.endsWith(".") && !branchName.endsWith("/") &&
            !branchName.endsWith(".lock") && !branchName.contains("..") &&
            !branchName.contains("//") && !branchName.contains("/.")
        if (!valid) {
            mutable.update { it.copy(error = "Invalid Git branch name. Use letters, digits, dots, dashes, underscores and slashes.") }
            return
        }
        runAuthorized("Created branch " + branchName + " on GitHub") { token ->
            service.createBranch(repo, commit.fullSha, branchName, token)
        }
    }

    fun review(pr: PullRequestItem, event: String, message: String) {
        runAuthorized("Review submitted to GitHub") { token ->
            if (event == "REQUEST_CHANGES" && message.isBlank()) throw IOException("Explain the requested changes.")
            service.approve(pr, token, message, event)
        }
    }

    fun merge(pr: PullRequestItem) {
        runAuthorized("Pull request merged on GitHub") { token -> service.merge(pr, token) }
    }

    fun rerunFailed(run: WorkflowRunItem) {
        runAuthorized("GitHub accepted the retry request") { token -> service.rerunFailed(run, token) }
    }

    private fun runAuthorized(success: String, operation: suspend (String) -> Unit) {
        viewModelScope.launch {
            val token = session.read()
            if (token.isNullOrBlank()) {
                mutable.update { it.copy(error = "Sign in with GitHub to perform this action.") }
                return@launch
            }
            mutable.update { it.copy(loading = true, error = null, message = null) }
            try {
                operation(token)
                mutable.update { it.copy(message = success) }
                refresh()
            } catch (e: Exception) {
                if (e is GitHubApiException && e.statusCode == 401) session.clear()
                mutable.update { it.copy(loading = false, error = cleanError(e)) }
            }
        }
    }

    fun consumeMessage() { mutable.update { it.copy(message = null) } }
    fun dismissError() { mutable.update { it.copy(error = null) } }

    companion object {
        fun diffKey(pr: PullRequestItem): String = pr.owner + "/" + pr.repo + "#" + pr.number
        fun branchKey(repo: RepositoryItem, branch: String): String = repo.owner + "/" + repo.name + ":" + branch
        fun commitKey(repo: RepositoryItem, commit: CommitItem): String = repo.owner + "/" + repo.name + "@" + commit.fullSha
        private fun cleanError(error: Exception): String =
            (error.message ?: "Request failed").take(220)
    }
}
