package dev.gitpilot.app.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.gitpilot.app.data.CheckStatus
import dev.gitpilot.app.data.PullRequestFile
import dev.gitpilot.app.data.PullRequestItem
import dev.gitpilot.app.data.WorkflowRunItem
import dev.gitpilot.app.data.WorkflowStep

@Composable
private fun LiveCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            content()
        }
    }
}

@Composable
fun LivePullRequestDetail(
    pr: PullRequestItem,
    files: List<PullRequestFile>?,
    loading: Boolean,
    authenticated: Boolean,
    onReview: (String, String) -> Unit,
    onMerge: () -> Unit
) {
    val browser = LocalUriHandler.current
    var reviewEvent by remember(pr.owner, pr.repo, pr.number) { mutableStateOf<String?>(null) }
    var reviewMessage by remember(pr.owner, pr.repo, pr.number) { mutableStateOf("") }
    var mergeConfirmation by remember(pr.owner, pr.repo, pr.number) { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(pr.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(pr.owner + "/" + pr.repo + " • #" + pr.number,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            LiveCard {
                Text(pr.source + " → " + pr.target, fontWeight = FontWeight.Medium)
                Text("Opened by @" + pr.author, style = MaterialTheme.typography.bodySmall)
                Text("The merge operation respects GitHub's branch rules and permissions.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (pr.htmlUrl.startsWith("https://github.com/")) {
                    OutlinedButton(onClick = { browser.openUri(pr.htmlUrl) }) { Text("Open on GitHub") }
                }
            }
        }
        item {
            Text("Changed files", style = MaterialTheme.typography.titleLarge)
            if (files == null) {
                Text(if (loading) "Loading actual diff from GitHub…" else "Diff not loaded yet.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (files.isEmpty()) {
                Text("No changed files returned.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (files != null) {
            items(files, key = { it.filename }) { file ->
                LiveCard {
                    Text(file.filename, fontWeight = FontWeight.SemiBold)
                    Text(file.status, style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary)
                    SelectionContainer {
                        Text(file.patch, modifier = Modifier.horizontalScroll(rememberScrollState()),
                            fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        item {
            LiveCard {
                Text("Review actions", style = MaterialTheme.typography.titleMedium)
                if (!authenticated) {
                    Text("Read-only public mode. Connect GitHub to review or merge.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall)
                }
                Button(modifier = Modifier.fillMaxWidth(), enabled = authenticated,
                    onClick = { reviewEvent = "APPROVE" }) { Text("Approve") }
                OutlinedButton(modifier = Modifier.fillMaxWidth(), enabled = authenticated,
                    onClick = { reviewEvent = "REQUEST_CHANGES" }) { Text("Request changes") }
                HorizontalDivider()
                OutlinedButton(modifier = Modifier.fillMaxWidth(),
                    enabled = authenticated && pr.headSha.isNotBlank(),
                    onClick = { mergeConfirmation = true }) { Text("Merge (squash)") }
            }
        }
    }

    if (reviewEvent != null) {
        val event = reviewEvent ?: ""
        AlertDialog(
            onDismissRequest = { reviewEvent = null },
            title = { Text(if (event == "APPROVE") "Approve pull request?" else "Request changes?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("This posts a real review on GitHub. The author will see it.")
                    OutlinedTextField(value = reviewMessage, onValueChange = { reviewMessage = it },
                        label = { Text(if (event == "APPROVE") "Optional comment" else "Required explanation") },
                        modifier = Modifier.fillMaxWidth(), minLines = 2)
                }
            },
            confirmButton = {
                Button(enabled = event == "APPROVE" || reviewMessage.isNotBlank(),
                    onClick = { onReview(event, reviewMessage); reviewEvent = null; reviewMessage = "" }) {
                    Text("Submit review")
                }
            },
            dismissButton = { TextButton(onClick = { reviewEvent = null }) { Text("Cancel") } }
        )
    }
    if (mergeConfirmation) {
        AlertDialog(
            onDismissRequest = { mergeConfirmation = false },
            title = { Text("Merge pull request?") },
            text = { Text("Squash-merge #" + pr.number + " into " + pr.target + "? This changes the remote GitHub repository and cannot be undone automatically.") },
            confirmButton = {
                Button(onClick = { onMerge(); mergeConfirmation = false }) { Text("Merge on GitHub") }
            },
            dismissButton = { TextButton(onClick = { mergeConfirmation = false }) { Text("Cancel") } }
        )
    }
}

@Composable
fun LiveWorkflowDetail(
    run: WorkflowRunItem,
    jobs: List<WorkflowStep>?,
    loading: Boolean,
    authenticated: Boolean,
    onRerunFailed: () -> Unit
) {
    val browser = LocalUriHandler.current
    var confirmRetry by remember(run.id) { mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(run.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(run.owner + "/" + run.repo + " • #" + run.id,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            LiveCard {
                Text("Branch: " + run.branch)
                Text("Status: " + when (run.check) {
                    CheckStatus.SUCCESS -> "Passed"
                    CheckStatus.FAILED -> "Failed"
                    CheckStatus.RUNNING -> "Running"
                    CheckStatus.PENDING -> "Pending"
                    CheckStatus.UNKNOWN -> "Unknown"
                }, fontWeight = FontWeight.Medium)
                Text("Last updated: " + run.age, style = MaterialTheme.typography.bodySmall)
                if (run.htmlUrl.startsWith("https://github.com/")) {
                    OutlinedButton(onClick = { browser.openUri(run.htmlUrl) }) { Text("Full logs on GitHub") }
                }
            }
        }
        item {
            Text("Jobs", style = MaterialTheme.typography.titleLarge)
            if (jobs == null) Text(if (loading) "Loading jobs…" else "Jobs not loaded yet.",
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (jobs != null) {
            items(jobs) { job ->
                LiveCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(job.name, modifier = Modifier.weight(1f))
                        Text(job.status.name.lowercase(), color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
        item {
            LiveCard {
                Text("Workflow actions", style = MaterialTheme.typography.titleMedium)
                if (!authenticated) Text("Sign in to modify workflow runs.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = authenticated && run.check == CheckStatus.FAILED,
                    onClick = { confirmRetry = true }
                ) { Text("Rerun failed jobs") }
            }
        }
    }
    if (confirmRetry) {
        AlertDialog(
            onDismissRequest = { confirmRetry = false },
            title = { Text("Rerun failed jobs?") },
            text = { Text("GitHub will start new attempts for failed jobs in run #" + run.id + ".") },
            confirmButton = {
                Button(onClick = { onRerunFailed(); confirmRetry = false }) {
                    Text("Rerun on GitHub")
                }
            },
            dismissButton = { TextButton(onClick = { confirmRetry = false }) { Text("Cancel") } }
        )
    }
}
