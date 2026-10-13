package dev.gitpilot.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.gitpilot.app.data.GitHubEntryType
import dev.gitpilot.app.data.GitHubFileEntry
import dev.gitpilot.app.data.GitPilotViewModel
import dev.gitpilot.app.data.RepositoryItem
import dev.gitpilot.app.data.parentDirectory
import dev.gitpilot.app.data.repositoryPathKey

/**
 * Browse GitHub Contents API one directory at a time. It does not download the entire tree.
 * Only UTF-8 files <=96 KB are previewed. Other files can be opened on GitHub.
 */
@Composable
fun RepositoryFilesScreen(
    repo: RepositoryItem,
    branch: String,
    model: GitPilotViewModel,
    onClose: () -> Unit
) {
    val state by model.state.collectAsState()
    var currentDirectory by remember(repo.id, branch) { mutableStateOf("") }
    var selectedFile by remember(repo.id, branch) { mutableStateOf<GitHubFileEntry?>(null) }
    val browser = LocalUriHandler.current
    val dirKey = repositoryPathKey(repo, branch, currentDirectory)
    val selectedKey = selectedFile?.let { repositoryPathKey(repo, branch, it.path) }
    var editMode by remember(repo.id, branch, selectedKey) { mutableStateOf(false) }
    var editedText by remember(repo.id, branch, selectedKey) { mutableStateOf("") }
    var commitMessage by remember(repo.id, branch, selectedKey) { mutableStateOf("") }
    var confirmCommit by remember(repo.id, branch, selectedKey) { mutableStateOf(false) }

    fun goBack() {
        if (selectedFile != null) selectedFile = null
        else if (currentDirectory.isNotEmpty()) currentDirectory = parentDirectory(currentDirectory)
        else onClose()
    }

    BackHandler { goBack() }

    LaunchedEffect(repo.id, branch, currentDirectory, state.workspace) {
        model.loadDirectory(repo, branch, currentDirectory)
    }
    LaunchedEffect(repo.id, branch, selectedKey, state.workspace) {
        selectedFile?.let { model.loadRepositoryFile(repo, branch, it) }
    }

    val files = state.directoryContents[dirKey]
    val preview = selectedKey?.let { state.filePreviews[it] }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            TextButton(onClick = { goBack() }) {
                Text(if (selectedFile != null) "← Back to directory"
                    else if (currentDirectory.isNotEmpty()) "← Parent directory"
                    else "← Repository")
            }
        }
        item {
            Text("Files", style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold)
            Text(repo.owner + "/" + repo.name + " · " + branch,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("/" + (selectedFile?.path ?: currentDirectory),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary)
        }

        if (selectedFile != null) {
            item {
                Text("File preview", style = MaterialTheme.typography.titleMedium)
                if (preview == null) {
                    Text(if (state.loadingFileKey == selectedKey) "Loading file from GitHub…"
                        else "Preview unavailable. Reopen the file to retry.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Card(colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface
                    )) {
                        Column(Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(preview.name, fontWeight = FontWeight.SemiBold)
                            if (preview.text != null) {
                                if (editMode) {
                                    Text("Editing one file on " + branch,
                                        color = MaterialTheme.colorScheme.primary,
                                        style = MaterialTheme.typography.titleSmall)
                                    OutlinedTextField(
                                        value = editedText,
                                        onValueChange = { editedText = it },
                                        modifier = Modifier.fillMaxWidth(),
                                        minLines = 12,
                                        maxLines = 22,
                                        label = { Text("File contents") },
                                        textStyle = MaterialTheme.typography.bodySmall.copy(
                                            fontFamily = FontFamily.Monospace)
                                    )
                                    OutlinedTextField(
                                        value = commitMessage,
                                        onValueChange = { commitMessage = it },
                                        modifier = Modifier.fillMaxWidth(),
                                        singleLine = true,
                                        label = { Text("Commit message") }
                                    )
                                    Text("One-file commit. GitHub will reject stale file SHAs or protected branches.",
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        style = MaterialTheme.typography.bodySmall)
                                    Button(
                                        modifier = Modifier.fillMaxWidth(),
                                        enabled = !state.loading && commitMessage.isNotBlank() &&
                                            editedText != preview.text &&
                                            editedText.toByteArray(Charsets.UTF_8).size <= 96_000,
                                        onClick = { confirmCommit = true }
                                    ) { Text("Review file commit") }
                                    TextButton(onClick = { editMode = false }) { Text("Discard local edits") }
                                } else {
                                    SelectionContainer {
                                        Text(
                                            preview.text.take(32_000) +
                                                if (preview.text.length > 32_000) "\n[Preview truncated]" else "",
                                            fontFamily = FontFamily.Monospace,
                                            style = MaterialTheme.typography.bodySmall,
                                            modifier = Modifier.horizontalScroll(rememberScrollState())
                                        )
                                    }
                                    if (state.authenticatedAs != null &&
                                        preview.text.length <= 32_000 &&
                                        preview.blobSha.matches(Regex("[0-9a-fA-F]{40}"))) {
                                        OutlinedButton(onClick = {
                                            editedText = preview.text
                                            commitMessage = "Update " + preview.name
                                            editMode = true
                                        }) { Text("Edit and commit file") }
                                    }
                                }
                            } else {
                                Text(preview.message ?: "Preview not supported for this file.",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (preview.htmlUrl.startsWith("https://github.com/")) {
                                OutlinedButton(onClick = { browser.openUri(preview.htmlUrl) }) {
                                    Text("Open file on GitHub")
                                }
                            }
                        }
                    }
                }
            }
        } else {
            if (files == null) {
                item {
                    Text(if (state.loadingDirectoryKey == dirKey) "Loading directory…"
                        else "Directory unavailable. Try refreshing GitPilot.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else if (files.isEmpty()) {
                item { Text("Directory is empty.") }
            } else {
                items(files, key = { it.path }) { file ->
                    Card(
                        modifier = Modifier.fillMaxWidth().clickable {
                            when (file.type) {
                                GitHubEntryType.DIRECTORY -> currentDirectory = file.path
                                GitHubEntryType.FILE -> selectedFile = file
                                GitHubEntryType.SUBMODULE, GitHubEntryType.OTHER ->
                                    if (file.htmlUrl.startsWith("https://github.com/"))
                                        browser.openUri(file.htmlUrl)
                            }
                        },
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surface
                        )
                    ) {
                        Row(Modifier.fillMaxWidth().padding(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            androidx.compose.material3.Icon(
                                if (file.type == GitHubEntryType.DIRECTORY)
                                    Icons.Default.Folder else Icons.Default.Description,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Column(Modifier.weight(1f)) {
                                Text(file.name, fontWeight = FontWeight.Medium)
                                Text(
                                    when (file.type) {
                                        GitHubEntryType.DIRECTORY -> "Folder"
                                        GitHubEntryType.FILE -> "File · " + file.sizeBytes + " bytes"
                                        GitHubEntryType.SUBMODULE -> "Git submodule"
                                        GitHubEntryType.OTHER -> "External item"
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
            item {
                Text("Read-only browser · GitHub Contents API. Large, non-UTF-8 and binary files open on GitHub.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    if (confirmCommit && preview?.text != null) {
        AlertDialog(
            onDismissRequest = { confirmCommit = false },
            title = { Text("Commit changes to GitHub?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(repo.owner + "/" + repo.name + " · " + branch)
                    Text(preview.path, fontWeight = FontWeight.SemiBold)
                    Text("Message: " + commitMessage.trim())
                    Text("This writes one file and creates a commit on the remote branch. " +
                        "You can review the result in GitHub. No other files will change.")
                }
            },
            confirmButton = {
                Button(enabled = !state.loading,
                    onClick = {
                        model.commitExistingFile(repo, branch, preview, editedText, commitMessage)
                        confirmCommit = false
                    }) { Text("Commit on GitHub") }
            },
            dismissButton = {
                TextButton(onClick = { confirmCommit = false }) { Text("Cancel") }
            }
        )
    }
}
