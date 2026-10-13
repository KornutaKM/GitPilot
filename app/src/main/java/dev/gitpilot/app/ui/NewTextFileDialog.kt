package dev.gitpilot.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
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
import dev.gitpilot.app.data.RepositoryItem
import dev.gitpilot.app.data.repositoryPathKey
import dev.gitpilot.app.data.validateNewTextFile

@Composable
fun NewTextFileDialog(
    repo: RepositoryItem,
    branch: String,
    directory: String,
    busy: Boolean,
    lastWrittenFileKey: String?,
    onCreate: (String, String, String) -> Unit,
    onCompleted: () -> Unit,
    onDismiss: () -> Unit
) {
    var name by remember(repo.id, branch, directory) { mutableStateOf("") }
    var contents by remember(repo.id, branch, directory) { mutableStateOf("") }
    var commitMessage by remember(repo.id, branch, directory) { mutableStateOf("") }
    var review by remember(repo.id, branch, directory) { mutableStateOf(false) }

    val validation = remember(directory, name, contents, commitMessage) {
        runCatching { validateNewTextFile(directory, name, contents, commitMessage) }
    }
    val path = validation.getOrNull()?.first

    LaunchedEffect(lastWrittenFileKey, path) {
        if (lastWrittenFileKey != null && path != null &&
            lastWrittenFileKey == repositoryPathKey(repo, branch, path)) {
            onCompleted()
            onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(if (review) "Confirm new file commit" else "Create text file") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth().heightIn(max = 450.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(repo.owner + "/" + repo.name + " · " + branch,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("/" + directory,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary)
                if (review) {
                    Text("File: " + path)
                    Text("Commit: " + commitMessage.trim())
                    Text("New file size: " + contents.toByteArray(Charsets.UTF_8).size + " bytes")
                    Text("GitHub will create one new file on this branch. The operation fails if " +
                        "a file with this name already exists or branch rules prohibit writing.")
                } else {
                    OutlinedTextField(
                        modifier = Modifier.fillMaxWidth(),
                        value = name, onValueChange = { name = it },
                        singleLine = true,
                        label = { Text("Filename (e.g. notes.md)") }
                    )
                    OutlinedTextField(
                        modifier = Modifier.fillMaxWidth(),
                        value = contents, onValueChange = { contents = it },
                        minLines = 7, maxLines = 12,
                        label = { Text("UTF-8 text contents") }
                    )
                    OutlinedTextField(
                        modifier = Modifier.fillMaxWidth(),
                        value = commitMessage,
                        onValueChange = { commitMessage = it },
                        singleLine = true,
                        label = { Text("Commit message") }
                    )
                    validation.exceptionOrNull()?.message?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                    Text("One file at a time. Never paste passwords, tokens or secrets.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
        confirmButton = {
            Button(
                enabled = !busy && validation.isSuccess,
                onClick = {
                    if (review) onCreate(name, contents, commitMessage)
                    else review = true
                }
            ) { Text(if (review) "Commit on GitHub" else "Review changes") }
        },
        dismissButton = {
            TextButton(enabled = !busy, onClick = {
                if (review) review = false else onDismiss()
            }) { Text(if (review) "Edit" else "Cancel") }
        }
    )
}
