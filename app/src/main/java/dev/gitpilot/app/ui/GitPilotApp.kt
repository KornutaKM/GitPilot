package dev.gitpilot.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.gitpilot.app.data.BranchItem
import dev.gitpilot.app.data.CheckStatus
import dev.gitpilot.app.data.CommitItem
import dev.gitpilot.app.data.GitPilotViewModel
import dev.gitpilot.app.data.PullRequestItem
import dev.gitpilot.app.data.RepositoryItem
import dev.gitpilot.app.data.WorkflowRunItem
import dev.gitpilot.app.data.Workspace

enum class MainTab(val label: String) { HOME("Home"), REPOS("Repos"), PRS("PRs"), ACTIONS("Actions") }

private sealed interface Details {
    data class Repository(val id: Int) : Details
    data class PullRequest(val number: Int) : Details
    data class Workflow(val id: Long) : Details
}

@Composable
fun GitPilotApp(model: GitPilotViewModel = viewModel()) {
    var tab by rememberSaveable { mutableStateOf(MainTab.HOME) }
    var detail by remember { mutableStateOf<Details?>(null) }
    val workspace = model.workspace
    BackHandler(enabled = detail != null) { detail = null }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 24.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (detail != null) {
                        IconButton(onClick = { detail = null }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                    Column(Modifier.weight(1f)) {
                        Text("GitPilot", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                        Text(
                            if (detail == null) "Your GitHub. Under control." else "Workspace / Details",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    DemoTag()
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.30f))
            }
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                MainTab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item; detail = null },
                        label = { Text(item.label) },
                        icon = {
                            Icon(
                                when (item) {
                                    MainTab.HOME -> Icons.Default.Home
                                    MainTab.REPOS -> Icons.Default.Folder
                                    MainTab.PRS -> Icons.Default.Code
                                    MainTab.ACTIONS -> Icons.Default.PlayArrow
                                }, contentDescription = item.label
                            )
                        }
                    )
                }
            }
        }
    ) { inset ->
        Box(Modifier.fillMaxSize().padding(inset)) {
            when (val active = detail) {
                is Details.Repository -> workspace.repositories.find { it.id == active.id }?.let { repo ->
                    RepositoryDetail(repo, workspace, onBack = { detail = null })
                }
                is Details.PullRequest -> workspace.pullRequests.find { it.number == active.number }?.let { pr ->
                    PullRequestDetail(pr)
                }
                is Details.Workflow -> workspace.workflows.find { it.id == active.id }?.let { run ->
                    WorkflowDetail(run)
                }
                null -> when (tab) {
                    MainTab.HOME -> Dashboard(workspace,
                        onRepo = { detail = Details.Repository(it) },
                        onPr = { detail = Details.PullRequest(it) },
                        onWorkflow = { detail = Details.Workflow(it) })
                    MainTab.REPOS -> RepositoriesScreen(workspace.repositories) { detail = Details.Repository(it) }
                    MainTab.PRS -> PullRequestsScreen(workspace.pullRequests) { detail = Details.PullRequest(it) }
                    MainTab.ACTIONS -> ActionsScreen(workspace.workflows) { detail = Details.Workflow(it) }
                }
            }
        }
    }
}

@Composable
private fun DemoTag() {
    Text(
        "DEMO", color = MaterialTheme.colorScheme.primary,
        fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.13f), RoundedCornerShape(50))
            .padding(horizontal = 11.dp, vertical = 6.dp)
    )
}

@Composable
private fun Heading(title: String, description: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (description != null) Muted(description)
    }
}

@Composable
private fun Muted(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, color = MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun Panel(onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp), content = content)
    }
}

@Composable
private fun Status(status: CheckStatus) {
    val color = when (status) {
        CheckStatus.SUCCESS -> Color(0xFF39C68A)
        CheckStatus.FAILED -> Color(0xFFEE7180)
        CheckStatus.RUNNING -> Color(0xFF8CA7FF)
        CheckStatus.PENDING -> Color(0xFFE6BC6C)
    }
    val label = when (status) {
        CheckStatus.SUCCESS -> "Passed"
        CheckStatus.FAILED -> "Failed"
        CheckStatus.RUNNING -> "Running"
        CheckStatus.PENDING -> "Pending"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.background(color.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 5.dp)
    ) {
        Icon(
            when (status) {
                CheckStatus.SUCCESS -> Icons.Default.CheckCircle
                CheckStatus.FAILED -> Icons.Default.Error
                CheckStatus.RUNNING -> Icons.Default.Refresh
                CheckStatus.PENDING -> Icons.Default.Schedule
            }, contentDescription = null, tint = color, modifier = Modifier.size(14.dp)
        )
        Text(label, color = color, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun Stat(number: String, label: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(number, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Muted(label)
        }
    }
}

@Composable
private fun Dashboard(
    ws: Workspace,
    onRepo: (Int) -> Unit,
    onPr: (Int) -> Unit,
    onWorkflow: (Long) -> Unit
) {
    val failed = ws.workflows.filter { it.check == CheckStatus.FAILED }
    val reviews = ws.pullRequests.filter { it.requiresReview }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item { Heading("Your workspace", "All the important changes in one place") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Stat(ws.repositories.size.toString().padStart(2, '0'), "Repositories", Modifier.weight(1f))
                Stat(reviews.size.toString().padStart(2, '0'), "Reviews", Modifier.weight(1f))
                Stat(failed.size.toString().padStart(2, '0'), "Failed CI", Modifier.weight(1f))
            }
        }
        item { Text("Needs attention", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        items(failed) { run -> WorkflowRow(run, onClick = { onWorkflow(run.id) }) }
        items(reviews) { pr -> PullRequestRow(pr, onClick = { onPr(pr.number) }) }
        item { Text("Pinned projects", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        items(ws.repositories.filter { it.starred }) { repo -> RepositoryRow(repo, onClick = { onRepo(repo.id) }) }
        item { Muted("Preview data only. Connect GitHub in a future milestone to see live status.") }
    }
}

@Composable
private fun RepositoryRow(repo: RepositoryItem, onClick: () -> Unit) {
    Panel(onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Folder, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(repo.name, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted("${repo.owner} · ${repo.language} · ${repo.branch}")
            }
            if (repo.starred) Icon(Icons.Default.Star, contentDescription = "Pinned", tint = Color(0xFFE3B66C), modifier = Modifier.size(17.dp))
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Muted(repo.activity)
    }
}

@Composable
private fun RepositoriesScreen(repos: List<RepositoryItem>, onRepo: (Int) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val visible = repos.filter { (it.name + it.owner + it.description).contains(query, ignoreCase = true) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading("Repositories", "Browse branches and recent commits") }
        item {
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                label = { Text("Search repositories") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)
            )
        }
        items(visible, key = { it.id }) { repo -> RepositoryRow(repo) { onRepo(repo.id) } }
        if (visible.isEmpty()) item { Muted("No repositories match your search.") }
    }
}

@Composable
private fun RepositoryDetail(repo: RepositoryItem, ws: Workspace, onBack: () -> Unit) {
    var selectedBranch by remember(repo.id) { mutableStateOf(repo.branch) }
    var selectedCommit by remember(repo.id) { mutableStateOf<CommitItem?>(null) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading(repo.name, repo.description) }
        item {
            Panel {
                Muted("DEFAULT BRANCH")
                Text(repo.branch, fontWeight = FontWeight.SemiBold)
                Muted("${repo.owner} · ${repo.language}")
            }
        }
        item { Text("Branches", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        items(ws.branches[repo.id].orEmpty()) { branch ->
            BranchRow(branch, selected = selectedBranch == branch.name) { selectedBranch = branch.name }
        }
        item { Text("Recent commits", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        items(ws.commits[repo.id].orEmpty()) { commit ->
            Panel(onClick = { selectedCommit = if (selectedCommit?.sha == commit.sha) null else commit }) {
                Text(commit.subject, fontWeight = FontWeight.Medium)
                Muted("${commit.sha} · ${commit.author} · ${commit.time}")
                if (selectedCommit?.sha == commit.sha) {
                    HorizontalDivider()
                    Muted("${commit.filesChanged} changed files · +${commit.additions} / −${commit.deletions}")
                    Muted("Full commit diff will be available after GitHub API integration.")
                }
            }
        }
        item { Muted("Branch selection is a local preview; demo commit history is not branch-filtered.") }
    }
}

@Composable
private fun BranchRow(branch: BranchItem, selected: Boolean, onClick: () -> Unit) {
    Panel(onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.AccountTree, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(branch.name, fontWeight = FontWeight.Medium)
                Muted(if (branch.isDefault) "Default branch" else "${branch.ahead} ahead · ${branch.behind} behind")
            }
            if (selected) Text("Selected", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun PullRequestRow(pr: PullRequestItem, onClick: () -> Unit) {
    Panel(onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("#${pr.number}", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
            Text(pr.repo, style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f))
            Status(pr.check)
        }
        Text(pr.title, fontWeight = FontWeight.SemiBold)
        Muted("${pr.source} → ${pr.target} · ${pr.changes} files")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Muted("+${pr.additions} / −${pr.deletions} · @${pr.author}", Modifier.weight(1f))
            if (pr.requiresReview) Text("Review needed", color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun PullRequestsScreen(prs: List<PullRequestItem>, onPr: (Int) -> Unit) {
    var needsReviewOnly by rememberSaveable { mutableStateOf(true) }
    val visible = prs.filter { !needsReviewOnly || it.requiresReview }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading("Pull requests", "Focus on reviews that need your attention") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = needsReviewOnly, onClick = { needsReviewOnly = true }, label = { Text("Needs review") })
                FilterChip(selected = !needsReviewOnly, onClick = { needsReviewOnly = false }, label = { Text("All PRs") })
            }
        }
        items(visible, key = { it.number }) { pr -> PullRequestRow(pr) { onPr(pr.number) } }
        if (visible.isEmpty()) item { Muted("No pull requests in this filter.") }
    }
}

@Composable
private fun PullRequestDetail(pr: PullRequestItem) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading(pr.title, "${pr.repo} / #${pr.number}") }
        item {
            Panel {
                Muted("BRANCHES")
                Text("${pr.source} → ${pr.target}", fontWeight = FontWeight.Medium)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Muted("${pr.changes} files · +${pr.additions} / −${pr.deletions}", Modifier.weight(1f))
                    Status(pr.check)
                }
                Muted("Opened by @${pr.author}")
            }
        }
        item { Text("Changes · demo diff", fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium) }
        item {
            Panel {
                Muted("src/auth/TokenRepository.kt")
                Text(
                    "@@ -12,3 +12,4 @@\n- val token = cache.read()\n+ val token = cache.readValid()\n+ if (token == null) refresh()",
                    fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                    lineHeight = 19.sp,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
        item {
            Panel {
                Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Muted("Preview only. Approve, request changes and merge require authenticated GitHub access and permission checks.")
                Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) { Text("Connect GitHub to review") }
            }
        }
    }
}

@Composable
private fun WorkflowRow(run: WorkflowRunItem, onClick: () -> Unit) {
    Panel(onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(run.name, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Status(run.check)
        }
        Muted("${run.repo} · ${run.branch} · ${run.age}")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Muted("${run.steps.size} jobs · run #${run.id}", Modifier.weight(1f))
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ActionsScreen(workflows: List<WorkflowRunItem>, onWorkflow: (Long) -> Unit) {
    var failedOnly by rememberSaveable { mutableStateOf(false) }
    val visible = workflows.filter { !failedOnly || it.check == CheckStatus.FAILED }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading("GitHub Actions", "Inspect checks, workflow runs and failures") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = !failedOnly, onClick = { failedOnly = false }, label = { Text("All runs") })
                FilterChip(selected = failedOnly, onClick = { failedOnly = true }, label = { Text("Failures") })
            }
        }
        items(visible, key = { it.id }) { run -> WorkflowRow(run) { onWorkflow(run.id) } }
    }
}

@Composable
private fun WorkflowDetail(run: WorkflowRunItem) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Heading(run.name, "${run.repo} · ${run.branch} · #${run.id}") }
        item {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Workflow run", modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                    Status(run.check)
                }
                Muted("Last updated ${run.age}")
            }
        }
        item { Text("Jobs", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        items(run.steps) { step ->
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(step.name, modifier = Modifier.weight(1f))
                    Status(step.status)
                }
            }
        }
        item { Text("Log excerpt · demo", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        item {
            Panel {
                Text(run.logExcerpt, fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                    lineHeight = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            Muted("Read-only preview. Rerun becomes available after secure GitHub authorization.")
            Spacer(Modifier.height(8.dp))
            Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) { Text("Rerun failed jobs") }
        }
    }
}
