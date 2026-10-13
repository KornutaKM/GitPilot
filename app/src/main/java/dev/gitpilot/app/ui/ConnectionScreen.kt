package dev.gitpilot.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.gitpilot.app.data.GitPilotState

@Composable
fun ConnectionScreen(
    state: GitPilotState,
    signInAvailable: Boolean,
    onUsernameChange: (String) -> Unit,
    onSignIn: () -> Unit,
    onCancel: () -> Unit,
    onSignOut: () -> Unit,
    onRefresh: () -> Unit
) {
    var username by remember(state.publicUsername) { mutableStateOf(state.publicUsername) }
    val uriHandler = LocalUriHandler.current

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("Connection", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("Choose a public GitHub profile or sign in with a GitHub App.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Public repositories", style = MaterialTheme.typography.titleMedium)
                    Text("Read-only browsing. No access token is needed.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedTextField(
                        modifier = Modifier.fillMaxWidth(),
                        value = username, onValueChange = { username = it },
                        singleLine = true, label = { Text("GitHub username") }
                    )
                    Button(modifier = Modifier.fillMaxWidth(), onClick = { onUsernameChange(username) }) {
                        Text("Browse public projects")
                    }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Authenticated GitHub", style = MaterialTheme.typography.titleMedium)
                    if (state.authenticatedAs != null) {
                        Text("Connected as @" + state.authenticatedAs)
                        Text("Private repositories and write actions depend on GitHub App installation permissions.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onSignOut) { Text("Sign out") }
                    } else if (!signInAvailable) {
                        Text("To enable sign-in, register a GitHub App with device flow enabled and configure the GitHub App client ID at build time. Never include a client secret in the app.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        Text("GitHub Device Flow: authorize in your browser. Tokens are encrypted with Android Keystore.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (state.deviceCode != null) {
                            Text("Enter this code on GitHub:", fontWeight = FontWeight.Medium)
                            SelectionContainer {
                                Text(state.deviceCode.userCode,
                                    style = MaterialTheme.typography.headlineMedium,
                                    color = MaterialTheme.colorScheme.primary)
                            }
                            Button(modifier = Modifier.fillMaxWidth(), onClick = {
                                uriHandler.openUri(state.deviceCode.verificationUri)
                            }) { Text("Open GitHub authorization") }
                            Text("Waiting for authorization…",
                                style = MaterialTheme.typography.bodySmall)
                            OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onCancel) {
                                Text("Cancel")
                            }
                        } else {
                            Button(modifier = Modifier.fillMaxWidth(),
                                enabled = !state.signingIn,
                                onClick = onSignIn) {
                                Text(if (state.signingIn) "Connecting…" else "Connect GitHub")
                            }
                        }
                    }
                }
            }
        }
        item {
            HorizontalDivider()
            Text("Manual refresh only. Public browsing is limited to recent repositories to respect GitHub API rate limits. All merge, review and rerun actions require authenticated GitHub access.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = onRefresh) { Text("Refresh workspace") }
        }
    }
}
