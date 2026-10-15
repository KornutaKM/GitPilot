package dev.gitpilot.app

import android.app.Activity
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Offline-safe launch/lifecycle checks against the real installed APK.
 * No account credentials or GitHub writes are needed; background GitHub reads
 * are intentionally not asserted because the device may be offline.
 */
@RunWith(AndroidJUnit4::class)
class GitPilotLaunchSmokeTest {
    @Test fun appLaunchesAndAttachesItsComposeContent() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            scenario.onActivity { activity ->
                assertFalse(activity.isFinishing)
                val content = activity.findViewById<ViewGroup>(android.R.id.content)
                assertNotNull(content)
                assertTrue("Compose content should be mounted", content.childCount > 0)
            }
            assertEquals("dev.gitpilot.app",
                InstrumentationRegistry.getInstrumentation().targetContext.packageName)
        } finally {
            scenario.close()
        }
    }

    @Test fun recreatingTheActivityDoesNotCrashTheApplication() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            scenario.recreate()
            scenario.onActivity { activity ->
                assertFalse(activity.isFinishing)
                assertNotNull(activity.findViewById<ViewGroup>(android.R.id.content))
            }
        } finally {
            scenario.close()
        }
    }

    @Test fun returningFromBackgroundRestoresTheNativeActivity() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            scenario.moveToState(Lifecycle.State.STARTED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { activity: Activity ->
                assertFalse(activity.isFinishing)
                assertNotNull(activity.window.decorView)
            }
        } finally {
            scenario.close()
        }
    }
}
