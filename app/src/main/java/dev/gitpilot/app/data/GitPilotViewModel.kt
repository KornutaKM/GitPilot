package dev.gitpilot.app.data

import androidx.lifecycle.ViewModel

/** Replace this repository with the authorized API-backed implementation in the next phase. */
class GitPilotViewModel : ViewModel() {
    val workspace: Workspace = DemoWorkspaceRepository.snapshot()
}
