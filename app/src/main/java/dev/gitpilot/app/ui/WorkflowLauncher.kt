package dev.gitpilot.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.gitpilot.app.data.GitPilotState
import dev.gitpilot.app.data.RepositoryItem
import dev.gitpilot.app.data.WorkflowDefinition
import dev.gitpilot.app.data.validGitRefName
import dev.gitpilot.app.data.parseWorkflowInputs

/**
 * A bounded workflow_dispatch launcher. We do not pretend to support required custom
 * workflow inputs; GitHub returns 422 for workflows that need them.
 */
@Composable
fun WorkflowLauncher(
    state: GitPilotState,
    onLoad: (RepositoryItem) -> Unit,
    onDispatch: (RepositoryItem, WorkflowDefinition, String, String) -> Unit,
    onDismiss: () -> Unit
) {
    val repos = state.workspace.repositories
    var selectedRepoId by remember { mutableStateOf(repos.firstOrNull()?.id) }
    val repo = repos.firstOrNull { it.id == selectedRepoId }
    val definitions = repo?.let { state.definitions[it.id] }
    var repoDropdown by remember { mutableStateOf(false) }
    var workflowDropdown by remember { mutableStateOf(false) }
    var selectedWorkflowId by remember { mutableStateOf<Long?>(null) }
    val workflow = definitions?.firstOrNull { it.id == selectedWorkflowId }
    var ref by remember { mutableStateOf(repo?.branch.orEmpty()) }
    var inputs by remember { mutableStateOf("") }
    val inputError = remember(inputs) { runCatching { parseWorkflowInputs(inputs) }.exceptionOrNull()?.message }
    var confirm by remember { mutableStateOf(false) }

    LaunchedEffect(repo?.id) {
        selectedWorkflowId = null
        ref = repo?.branch.orEmpty()
        inputs = ""
        if (repo != null) onLoad(repo)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Run GitHub workflow") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("Choose a repository, workflow, and branch or tag. This starts a real run on GitHub.",
                    style = MaterialTheme.typography.bodySmall)
                Box {
                    OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = { repoDropdown = true }) {
                        Text(repo?.let { it.owner + "/" + it.name } ?: "Choose repository")
                    }
                    DropdownMenu(expanded = repoDropdown, onDismissRequest = { repoDropdown = false }) {
                        repos.forEach { item ->
                            DropdownMenuItem(text = { Text(item.owner + "/" + item.name) }, onClick = {
                                selectedRepoId = item.id
                                repoDropdown = false
                            })
                        }
                    }
                }
                if (repo != null) {
                    Text(
                        when {
                            definitions == null && state.loadingDefinitionsId == repo.id ->
                                "Loading workflows from GitHub…"
                            definitions == null -> "No workflows loaded. Choose a repository to retry."
                            definitions.isEmpty() -> "No active workflows found in this repository."
                            else -> "Select an active workflow"
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Box {
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !definitions.isNullOrEmpty(),
                        onClick = { workflowDropdown = true }
                    ) { Text(workflow?.name ?: "Choose workflow") }
                    DropdownMenu(expanded = workflowDropdown, onDismissRequest = { workflowDropdown = false }) {
                        definitions.orEmpty().forEach { item ->
                            DropdownMenuItem(text = { Text(item.name) }, onClick = {
                                selectedWorkflowId = item.id
                                workflowDropdown = false
                            })
                        }
                    }
                }
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = ref,
                    onValueChange = { ref = it },
                    singleLine = true,
                    label = { Text("Branch or tag ref") }
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = inputs,
                    onValueChange = { inputs = it },
                    minLines = 3,
                    maxLines = 6,
                    label = { Text("Optional inputs, one key=value per line") },
                    placeholder = { Text("environment=staging\nversion=1.2.0") },
                    isError = inputError != null
                )
                if (inputError != null) {
                    Text(inputError, color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall)
                }
                Text("A workflow must support workflow_dispatch. Up to 10 inputs are accepted. Never enter passwords or secrets as inputs; use GitHub Actions secrets instead.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            Button(enabled = repo != null && workflow != null && validGitRefName(ref) && inputError == null,
                onClick = { confirm = true }) { Text("Review action") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )

    if (confirm && repo != null && workflow != null) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Start workflow on GitHub?") },
            text = {
                Text("Run '" + workflow.name + "' in " + repo.owner + "/" + repo.name +
                    " at ref '" + ref + "' with " + parseWorkflowInputs(inputs).size +
                    " input(s)? It may deploy software or change external systems.")
            },
            confirmButton = {
                Button(onClick = {
                    onDispatch(repo, workflow, ref, inputs)
                    confirm = false
                    onDismiss()
                }) { Text("Start workflow") }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Back") } }
        )
    }
}
