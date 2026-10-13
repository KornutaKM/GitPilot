package dev.gitpilot.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.gitpilot.app.ui.GitPilotApp
import dev.gitpilot.app.ui.GitPilotTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            GitPilotTheme {
                GitPilotApp()
            }
        }
    }
}
