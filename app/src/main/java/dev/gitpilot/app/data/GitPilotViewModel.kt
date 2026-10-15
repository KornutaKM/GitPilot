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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException

data class PullRequestFile(val filename: String, val status: String, val patch: String)

data class GitPilotState(
    val workspace: Workspace = Workspace(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
    val loading: Boolean = false,
    val hasMoreRepositories: Boolean = false,
    val repositoryPage: Int = 1,
    val loadingMoreRepositories: Boolean = false,
    val loadingRepoDetailsId: Long? = null,
    val authenticatedAs: String? = null,
    val publicUsername: String = "KornutaKM",
    val error: String? = null,
    val message: String? = null,
    val warnings: List<String> = emptyList(),
    val deviceCode: GitHubDeviceCode? = null,
    val signingIn: Boolean = false,
    val diffs: Map<String, List<PullRequestFile>> = emptyMap(),
    val discussion: Map<String, List<DiscussionEntry>> = emptyMap(),
    val loadingDiscussionKey: String? = null,
    val jobs: Map<Long, List<WorkflowStep>> = emptyMap(),
    val jobLogs: Map<Long, String> = emptyMap(),
    val loadingJobId: Long? = null,
    val branchCommits: Map<String, List<CommitItem>> = emptyMap(),
    val directoryContents: Map<String, List<GitHubFileEntry>> = emptyMap(),
    val filePreviews: Map<String, GitHubFilePreview> = emptyMap(),
    val lastWrittenFileKey: String? = null,
    val loadingDirectoryKey: String? = null,
    val loadingFileKey: String? = null,
    val comparisons: Map<String, BranchComparison> = emptyMap(),
    val loadingComparisonKey: String? = null,
    val commitFiles: Map<String, List<PullRequestFile>> = emptyMap(),
    val branchLoading: Boolean = false,
    val detailLoading: Boolean = false,
    val definitions: Map<Long, List<WorkflowDefinition>> = emptyMap(),
    val loadingDefinitionsId: Long? = null
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
    private val credentialMutex = Mutex()
    private var authEpoch = 0L
    private var mutationInProgress = false
    private var workspaceGeneration = 0L
    private val detailRequestGate = GitHubDetailRequestGate()

    init { refresh() }

    /** Rotate expiring device-flow credentials, never putting a client secret in Android. */

    private fun invalidateSession() {
        authEpoch += 1
        session.clear()
        // Repository names may themselves be confidential. Clear locally pinned
        // identifiers when credentials are revoked or the user explicitly signs out.
        preferences.edit().remove("pinned_repositories").commit()
        mutable.update {
            it.copy(
                authenticatedAs = null, error = null, message = null,
                deviceCode = null, signingIn = false,
                workspace = Workspace(emptyList(), emptyList(), emptyList(), emptyMap(), emptyMap()),
                diffs = emptyMap(), discussion = emptyMap(), loadingDiscussionKey = null,
                jobs = emptyMap(), jobLogs = emptyMap(),
                branchCommits = emptyMap(), comparisons = emptyMap(), loadingComparisonKey = null,
                directoryContents = emptyMap(), filePreviews = emptyMap(), lastWrittenFileKey = null,
                loadingDirectoryKey = null, loadingFileKey = null,
                commitFiles = emptyMap(),
                definitions = emptyMap(), loading = false, detailLoading = false,
                hasMoreRepositories = false, repositoryPage = 1,
                loadingMoreRepositories = false, loadingRepoDetailsId = null,
                loadingJobId = null, loadingDefinitionsId = null, branchLoading = false,
                warnings = emptyList()
            )
        }
    }

    private suspend fun currentToken(): String? = credentialMutex.withLock {
        val saved = session.readCredentials() ?: return@withLock null
        val now = System.currentTimeMillis()
        if (saved.accessUsable(now)) return@withLock saved.accessToken
        if (!canSignIn || !saved.refreshUsable(now)) {
            invalidateSession()
            return@withLock null
        }
        val epoch = authEpoch
        val renewed = try {
            deviceAuth.renew(clientId, saved.refreshToken!!)
        } catch (e: GitHubOAuthException) {
            // A network outage must not destroy a recoverable session, but GitHub's
            // explicit revocation/expiry response makes existing credentials unusable.
            if (isPermanentRefreshFailure(e.oauthCode) && epoch == authEpoch) {
                invalidateSession()
            }
            throw e
        }
        if (epoch != authEpoch) return@withLock null
        session.save(renewed.accessToken, renewed.expiresInSeconds,
            renewed.refreshToken, renewed.refreshExpiresInSeconds)
        renewed.accessToken
    }


    fun refresh() {
        refreshJob?.cancel()
        workspaceGeneration += 1
        val generation = workspaceGeneration
        val epoch = authEpoch
        refreshJob = viewModelScope.launch {
            mutable.update { it.copy(loading = true, loadingMoreRepositories = false, error = null) }
            try {
                val token = currentToken()
                val user = if (token == null) null else service.viewerLogin(token)
                val selected = user ?: mutable.value.publicUsername
                val result = service.load(selected, token, preferences.getStringSet("pinned_repositories", emptySet()).orEmpty().toSet())
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                mutable.update {
                    it.copy(workspace = result.workspace, loading = false,
                        authenticatedAs = user, warnings = result.warnings,
                        hasMoreRepositories = result.hasMoreRepositories,
                        repositoryPage = 1, loadingMoreRepositories = false,
                        loadingRepoDetailsId = null,
                        diffs = emptyMap(), discussion = emptyMap(), loadingDiscussionKey = null,
                jobs = emptyMap(), jobLogs = emptyMap(), loadingJobId = null,
                        branchCommits = emptyMap(), comparisons = emptyMap(), loadingComparisonKey = null,
                directoryContents = emptyMap(), filePreviews = emptyMap(),
                loadingDirectoryKey = null, loadingFileKey = null,
                        commitFiles = emptyMap(), branchLoading = false, detailLoading = false)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (e is GitHubApiException && e.statusCode == 401) invalidateSession()
                mutable.update { it.copy(loading = false, error = cleanError(e)) }
            }
        }
    }

    fun loadMoreRepositories() {
        val initial = mutable.value
        if (!initial.hasMoreRepositories || initial.loadingMoreRepositories ||
            initial.loading || initial.repositoryPage >= 5) return
        val page = initial.repositoryPage + 1
        val epoch = authEpoch
        val generation = workspaceGeneration
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            mutable.update { it.copy(loadingMoreRepositories = true, error = null) }
            try {
                val token = currentToken()
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                val username = if (token == null) mutable.value.publicUsername
                    else mutable.value.authenticatedAs ?: service.viewerLogin(token)
                val pins = preferences.getStringSet("pinned_repositories", emptySet()).orEmpty().toSet()
                val result = service.repositoryPage(username, token, page, pins)
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { old ->
                        old.copy(
                            workspace = old.workspace.copy(repositories =
                                mergeRepositoryPages(old.workspace.repositories, result.repositories)),
                            repositoryPage = page,
                            hasMoreRepositories = result.hasMore,
                            loadingMoreRepositories = false
                        )
                    }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(loadingMoreRepositories = false, error = cleanError(e)) }
                }
            }
        }
    }

    fun loadRepositoryDetails(repo: RepositoryItem) {
        val current = mutable.value
        if (current.workspace.branches.containsKey(repo.id) &&
            current.workspace.commits.containsKey(repo.id)) return
        if (current.loadingRepoDetailsId == repo.id) return
        val epoch = authEpoch
        val generation = workspaceGeneration
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            mutable.update { it.copy(loadingRepoDetailsId = repo.id, error = null) }
            try {
                val (branches, commits) = service.repositoryDetails(repo, currentToken())
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { old ->
                        old.copy(
                            workspace = old.workspace.copy(
                                branches = old.workspace.branches + (repo.id to branches),
                                commits = old.workspace.commits + (repo.id to commits)
                            ),
                            loadingRepoDetailsId = null
                        )
                    }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(loadingRepoDetailsId = null, error = cleanError(e)) }
                }
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
        if (mutable.value.authenticatedAs == null) refresh()
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
                // Server values are validated by decodeGitHubDeviceCode.
                val deadline = System.currentTimeMillis() + code.expiresInSeconds * 1000L
                var interval = safeDevicePollInterval(code.intervalSeconds)
                while (System.currentTimeMillis() < deadline) {
                    delay(interval * 1000L)
                    when (val answer = deviceAuth.poll(clientId, code)) {
                        is PollResult.Pending -> Unit
                        is PollResult.SlowDown ->
                            interval = safeDevicePollInterval(maxOf(interval + 5L, answer.intervalSeconds))
                        is PollResult.Authorized -> {
                            // Replace every account-scoped cache BEFORE saving credentials.
                            // Otherwise the prior account's private diffs and file previews
                            // remain visible while the new viewer's workspace loads.
                            invalidateSession()
                            session.save(answer.accessToken, answer.expiresInSeconds,
                                answer.refreshToken, answer.refreshExpiresInSeconds)
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
        invalidateSession()
        mutable.update { it.copy(message = "Signed out") }
        refresh()
    }

    fun loadDirectory(repo: RepositoryItem, branch: String, path: String) {
        val key = repositoryPathKey(repo, branch, path)
        if (mutable.value.directoryContents.containsKey(key) ||
            mutable.value.loadingDirectoryKey == key) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            mutable.update { it.copy(loadingDirectoryKey = key, error = null) }
            try {
                val contents = service.listDirectory(repo, branch, path, currentToken())
                if (epoch == authEpoch) mutable.update {
                    it.copy(directoryContents = it.directoryContents + (key to contents),
                        loadingDirectoryKey = null)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update {
                    it.copy(loadingDirectoryKey = null, error = cleanError(e))
                }
            }
        }
    }

    fun loadRepositoryFile(repo: RepositoryItem, branch: String, file: GitHubFileEntry) {
        val key = repositoryPathKey(repo, branch, file.path)
        if (mutable.value.filePreviews.containsKey(key) ||
            mutable.value.loadingFileKey == key) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            mutable.update { it.copy(loadingFileKey = key, error = null) }
            try {
                val preview = service.readFile(repo, branch, file, currentToken())
                if (epoch == authEpoch) mutable.update {
                    it.copy(filePreviews = it.filePreviews + (key to preview),
                        loadingFileKey = null)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update {
                    it.copy(loadingFileKey = null, error = cleanError(e))
                }
            }
        }
    }

    fun loadBranchComparison(repo: RepositoryItem, branch: String) {
        if (branch == repo.branch) return
        val key = branchKey(repo, branch)
        if (mutable.value.comparisons.containsKey(key) ||
            mutable.value.loadingComparisonKey == key) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            mutable.update { it.copy(loadingComparisonKey = key, error = null) }
            try {
                val comparison = service.compareBranches(repo, branch, currentToken())
                if (epoch == authEpoch) mutable.update {
                    it.copy(comparisons = it.comparisons + (key to comparison),
                        loadingComparisonKey = null)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update {
                    it.copy(loadingComparisonKey = null, error = cleanError(e))
                }
            }
        }
    }

    fun loadBranchCommits(repo: RepositoryItem, branch: String) {
        val key = branchKey(repo, branch)
        if (mutable.value.branchCommits.containsKey(key)) return
        val epoch = authEpoch
        val generation = workspaceGeneration
        val requestKey = "commits:$key"
        if (!detailRequestGate.begin(generation, requestKey)) return
        viewModelScope.launch {
            try {
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                mutable.update { it.copy(branchLoading = true, error = null) }
                val commits = service.commitsForBranch(repo, branch, currentToken())
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(branchCommits = it.branchCommits + (key to commits), branchLoading = false) }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(branchLoading = false, error = cleanError(e)) }
                }
            } finally {
                detailRequestGate.finish(generation, requestKey)
            }
        }
    }

    fun loadCommitFiles(repo: RepositoryItem, commit: CommitItem) {
        val key = commitKey(repo, commit)
        if (mutable.value.commitFiles.containsKey(key)) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            if (epoch == authEpoch) mutable.update { it.copy(detailLoading = true, error = null) }
            try {
                val files = service.commitFiles(repo, commit, currentToken())
                if (epoch == authEpoch) mutable.update { it.copy(commitFiles = it.commitFiles + (key to files), detailLoading = false) }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
            }
        }
    }

    fun loadPullDiscussion(pr: PullRequestItem, force: Boolean = false) {
        val key = diffKey(pr)
        if (!force && mutable.value.discussion.containsKey(key)) return
        val epoch = authEpoch
        val generation = workspaceGeneration
        val requestKey = "discussion:$key"
        if (!detailRequestGate.begin(generation, requestKey)) return
        viewModelScope.launch {
            try {
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                mutable.update { it.copy(loadingDiscussionKey = key, error = null) }
                val entries = service.pullDiscussion(pr, currentToken())
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update {
                        it.copy(discussion = it.discussion + (key to entries), loadingDiscussionKey = null)
                    }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(loadingDiscussionKey = null, error = cleanError(e)) }
                }
            } finally {
                detailRequestGate.finish(generation, requestKey)
            }
        }
    }

    fun loadPullFiles(pr: PullRequestItem) {
        val key = diffKey(pr)
        if (mutable.value.diffs.containsKey(key)) return
        val epoch = authEpoch
        val generation = workspaceGeneration
        val requestKey = "pr-files:$key"
        if (!detailRequestGate.begin(generation, requestKey)) return
        viewModelScope.launch {
            try {
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                mutable.update { it.copy(detailLoading = true, error = null) }
                val files = service.pullFiles(pr, currentToken())
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(diffs = it.diffs + (key to files), detailLoading = false) }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
                }
            } finally {
                detailRequestGate.finish(generation, requestKey)
            }
        }
    }

    fun loadJobLog(run: WorkflowRunItem, step: WorkflowStep) {
        if (step.id <= 0 || mutable.value.jobLogs.containsKey(step.id)) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            if (epoch == authEpoch) mutable.update { it.copy(loadingJobId = step.id, error = null) }
            try {
                val text = service.fetchJobLog(run, step, currentToken())
                if (epoch == authEpoch) mutable.update { it.copy(jobLogs = it.jobLogs + (step.id to text), loadingJobId = null) }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update { it.copy(loadingJobId = null, error = cleanError(e)) }
            }
        }
    }

    fun loadWorkflowJobs(run: WorkflowRunItem) {
        if (mutable.value.jobs.containsKey(run.id)) return
        val epoch = authEpoch
        val generation = workspaceGeneration
        val requestKey = "jobs:${run.id}"
        if (!detailRequestGate.begin(generation, requestKey)) return
        viewModelScope.launch {
            try {
                if (epoch != authEpoch || generation != workspaceGeneration) return@launch
                mutable.update { it.copy(detailLoading = true, error = null) }
                val jobs = service.workflowJobs(run, currentToken())
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(jobs = it.jobs + (run.id to jobs), detailLoading = false) }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch && generation == workspaceGeneration) {
                    mutable.update { it.copy(detailLoading = false, error = cleanError(e)) }
                }
            } finally {
                detailRequestGate.finish(generation, requestKey)
            }
        }
    }

    fun createTextFile(
        repo: RepositoryItem, branch: String, directory: String,
        name: String, text: String, message: String
    ) {
        val (path, cleanMessage) = try {
            validateNewTextFile(directory, name, text, message)
        } catch (e: IllegalArgumentException) {
            mutable.update { it.copy(error = e.message ?: "Invalid new file.") }
            return
        }
        val key = repositoryPathKey(repo, branch, path)
        mutable.update { it.copy(lastWrittenFileKey = null) }
        runAuthorized("New file committed to GitHub", onSuccess = {
            mutable.update { it.copy(lastWrittenFileKey = key) }
        }) { token ->
            service.createTextFile(repo, branch, directory, name, text, cleanMessage, token)
        }
    }

    fun commitExistingFile(
        repo: RepositoryItem, branch: String, preview: GitHubFilePreview,
        editedText: String, rawCommitMessage: String
    ) {
        val original = preview.text ?: run {
            mutable.update { it.copy(error = "This file cannot be edited.") }
            return
        }
        val message = try {
            validateFileCommit(original, editedText, rawCommitMessage, preview.blobSha)
        } catch (e: IllegalArgumentException) {
            mutable.update { it.copy(error = e.message ?: "Invalid commit.") }
            return
        }
        val key = repositoryPathKey(repo, branch, preview.path)
        mutable.update { it.copy(lastWrittenFileKey = null) }
        runAuthorized("File committed on GitHub", onSuccess = {
            mutable.update { it.copy(lastWrittenFileKey = key) }
        }) { token ->
            service.updateExistingTextFile(repo, branch, preview, editedText, message, token)
        }
    }

    fun createPullRequest(repo: RepositoryItem, sourceBranch: String, title: String, body: String) {
        val compared = mutable.value.comparisons[branchKey(repo, sourceBranch)]
        if (compared == null || !compared.canOpenPullRequest) {
            mutable.update { it.copy(error = "Compare a branch with new commits before creating a PR.") }
            return
        }
        val validated = try {
            validatedPullRequestDraft(title, body)
        } catch (e: IllegalArgumentException) {
            mutable.update { it.copy(error = e.message ?: "Invalid pull request.") }
            return
        }
        runAuthorized("Pull request created on GitHub") { token ->
            service.createPullRequest(repo, sourceBranch, validated.first, validated.second, token)
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

    fun comment(pr: PullRequestItem, rawDraft: String) {
        val validated = try {
            validateDiscussionDraft(rawDraft)
        } catch (e: IllegalArgumentException) {
            mutable.update { it.copy(error = e.message ?: "Invalid comment") }
            return
        }
        runAuthorized("Comment posted on GitHub") { token ->
            service.postPullComment(pr, token, validated)
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


    fun loadWorkflowDefinitions(repo: RepositoryItem) {
        if (mutable.value.definitions.containsKey(repo.id)) return
        val epoch = authEpoch
        viewModelScope.launch {
            if (epoch != authEpoch) return@launch
            if (epoch == authEpoch) mutable.update { it.copy(loadingDefinitionsId = repo.id, error = null) }
            try {
                val definitions = service.listWorkflows(repo, currentToken())
                if (epoch == authEpoch) mutable.update { it.copy(
                    definitions = it.definitions + (repo.id to definitions),
                    loadingDefinitionsId = null
                ) }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (epoch == authEpoch) mutable.update { it.copy(loadingDefinitionsId = null, error = cleanError(e)) }
            }
        }
    }

    fun dispatchWorkflow(
        repo: RepositoryItem, workflow: WorkflowDefinition, ref: String, rawInputs: String
    ) {
        val trimmed = ref.trim()
        if (!validGitRefName(trimmed)) {
            mutable.update { it.copy(error = "Select a valid branch or tag reference.") }
            return
        }
        val inputs = try {
            parseWorkflowInputs(rawInputs)
        } catch (e: IllegalArgumentException) {
            mutable.update { it.copy(error = e.message ?: "Invalid workflow inputs.") }
            return
        }
        runAuthorized("Workflow dispatch accepted by GitHub") { token ->
            service.dispatchWorkflow(repo, workflow.id, trimmed, token, inputs)
        }
    }

    fun cancelWorkflowRun(run: WorkflowRunItem) {
        if (run.check != CheckStatus.RUNNING) {
            mutable.update { it.copy(error = "Only running or queued workflows can be cancelled.") }
            return
        }
        runAuthorized("GitHub accepted the workflow cancellation") { token ->
            service.cancelWorkflowRun(run, token)
        }
    }

    fun rerunFailed(run: WorkflowRunItem) {
        runAuthorized("GitHub accepted the retry request") { token -> service.rerunFailed(run, token) }
    }

    private fun runAuthorized(
        success: String,
        onSuccess: (() -> Unit)? = null,
        operation: suspend (String) -> Unit
    ) {
        if (mutationInProgress) {
            mutable.update { it.copy(error = "An operation is already in progress.") }
            return
        }
        mutationInProgress = true
        val epoch = authEpoch
        viewModelScope.launch {
            try {
                val token = currentToken()
                if (token.isNullOrBlank()) {
                    throw IOException("Sign in with GitHub to perform this action.")
                }
                if (epoch != authEpoch) return@launch
                mutable.update { it.copy(loading = true, error = null, message = null) }
                operation(token)
                if (epoch == authEpoch) {
                    onSuccess?.invoke()
                    mutable.update { it.copy(message = success) }
                    refresh()
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (e is GitHubApiException && e.statusCode == 401) invalidateSession()
                if (epoch == authEpoch) {
                    mutable.update { it.copy(loading = false, error = cleanError(e)) }
                }
            } finally {
                mutationInProgress = false
                if (epoch == authEpoch) mutable.update { it.copy(loading = false) }
            }
        }
    }

    fun consumeFileWriteEvent() { mutable.update { it.copy(lastWrittenFileKey = null) } }
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
